// Package bus keeps the last message of every topic and fans new messages out
// to watchers. It is the state behind dotctld; see docs/bus.md for the topics.
package bus

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"sync"
	"time"
)

// MaxDataBytes bounds the JSON data of a single message.
const MaxDataBytes = 64 << 10

// subscriberBuffer is how many messages a watcher may fall behind before it
// is dropped. Publishers never wait on a slow watcher.
const subscriberBuffer = 64

var topicPattern = regexp.MustCompile(`^[a-z][a-z0-9.-]{0,63}$`)

// ErrInvalidTopic is returned for a topic name outside topicPattern.
var ErrInvalidTopic = errors.New("topic must match " + topicPattern.String())

// ErrInvalidData is returned for data that is not a single JSON value.
var ErrInvalidData = errors.New("data must be valid JSON")

// ErrDataTooLarge is returned for data over MaxDataBytes.
var ErrDataTooLarge = fmt.Errorf("data is larger than %d bytes", MaxDataBytes)

// Message is one published value of a topic.
type Message struct {
	Topic string          `json:"topic"`
	Data  json.RawMessage `json:"data"`
	Seq   uint64          `json:"seq"`
	Time  time.Time       `json:"time"`
}

// Subscription receives the messages of the topics it watches. C is closed
// when the subscription ends: by Unsubscribe, by falling more than
// subscriberBuffer messages behind, or by Store.Close.
type Subscription struct {
	C      <-chan Message
	ch     chan Message
	topics map[string]bool
}

// Store holds the retained messages and the active subscriptions.
type Store struct {
	mu        sync.Mutex
	values    map[string]Message
	seq       uint64
	subs      map[*Subscription]struct{}
	statePath string
	now       func() time.Time
	closed    bool

	// OnSaveError, when set, is told about a failed write of the state file.
	// The publish itself still succeeds: the message is retained in memory.
	OnSaveError func(error)
}

// NewStore returns a store that persists retained messages to statePath
// after every publish; an empty statePath keeps them in memory only.
func NewStore(statePath string) *Store {
	return &Store{
		values:    map[string]Message{},
		subs:      map[*Subscription]struct{}{},
		statePath: statePath,
		now:       time.Now,
	}
}

// ValidTopic reports whether name is an acceptable topic name.
func ValidTopic(name string) bool { return topicPattern.MatchString(name) }

// Load restores retained messages from the state file. A missing file is not
// an error; the sequence continues after the highest restored one.
func (s *Store) Load() error {
	if s.statePath == "" {
		return nil
	}
	raw, err := os.ReadFile(s.statePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read bus state: %w", err)
	}
	var saved []Message
	if err := json.Unmarshal(raw, &saved); err != nil {
		return fmt.Errorf("parse bus state %s: %w", s.statePath, err)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, m := range saved {
		if !ValidTopic(m.Topic) || !json.Valid(m.Data) {
			continue
		}
		s.values[m.Topic] = m
		s.seq = max(s.seq, m.Seq)
	}
	return nil
}

// Publish retains data as the topic's current message and delivers it to
// every watcher of the topic. It fails only for an invalid topic or data.
func (s *Store) Publish(topic string, data []byte) (Message, error) {
	if !ValidTopic(topic) {
		return Message{}, ErrInvalidTopic
	}
	if len(data) > MaxDataBytes {
		return Message{}, ErrDataTooLarge
	}
	if !json.Valid(data) {
		return Message{}, ErrInvalidData
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	m := Message{
		Topic: topic,
		Data:  append(json.RawMessage(nil), data...),
		Seq:   s.seq,
		Time:  s.now().UTC(),
	}
	s.values[topic] = m
	for sub := range s.subs {
		if !sub.topics[topic] {
			continue
		}
		select {
		case sub.ch <- m:
		default:
			s.dropLocked(sub)
		}
	}
	if err := s.saveLocked(); err != nil && s.OnSaveError != nil {
		s.OnSaveError(err)
	}
	return m, nil
}

// Get returns the topic's current message.
func (s *Store) Get(topic string) (Message, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m, ok := s.values[topic]
	return m, ok
}

// List returns every retained message, sorted by topic.
func (s *Store) List() []Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Message, 0, len(s.values))
	for _, m := range s.values {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Topic < out[j].Topic })
	return out
}

// Subscribe watches topics. The current message of each topic that has one
// is already queued on the subscription, in the order the topics are given.
func (s *Store) Subscribe(topics []string) (*Subscription, error) {
	if len(topics) == 0 {
		return nil, errors.New("watch at least one topic")
	}
	set := make(map[string]bool, len(topics))
	for _, t := range topics {
		if !ValidTopic(t) {
			return nil, ErrInvalidTopic
		}
		set[t] = true
	}

	ch := make(chan Message, subscriberBuffer+len(topics))
	sub := &Subscription{C: ch, ch: ch, topics: set}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		close(ch)
		return sub, nil
	}
	seen := make(map[string]bool, len(topics))
	for _, t := range topics {
		if m, ok := s.values[t]; ok && !seen[t] {
			ch <- m
		}
		seen[t] = true
	}
	s.subs[sub] = struct{}{}
	return sub, nil
}

// Unsubscribe ends sub. It is safe to call more than once.
func (s *Store) Unsubscribe(sub *Subscription) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.dropLocked(sub)
}

// Close ends every subscription; later subscriptions start closed.
func (s *Store) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
	for sub := range s.subs {
		s.dropLocked(sub)
	}
}

func (s *Store) dropLocked(sub *Subscription) {
	if _, ok := s.subs[sub]; !ok {
		return
	}
	delete(s.subs, sub)
	close(sub.ch)
}

// saveLocked writes the retained messages atomically (temp file + rename).
func (s *Store) saveLocked() error {
	if s.statePath == "" {
		return nil
	}
	out := make([]Message, 0, len(s.values))
	for _, m := range s.values {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Topic < out[j].Topic })
	raw, err := json.Marshal(out)
	if err != nil {
		return fmt.Errorf("encode bus state: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(s.statePath), 0o700); err != nil {
		return fmt.Errorf("create bus state dir: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(s.statePath), ".bus-*.json")
	if err != nil {
		return fmt.Errorf("write bus state: %w", err)
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(raw); err != nil {
		tmp.Close()
		return fmt.Errorf("write bus state: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("write bus state: %w", err)
	}
	if err := os.Rename(tmp.Name(), s.statePath); err != nil {
		return fmt.Errorf("write bus state: %w", err)
	}
	return nil
}
