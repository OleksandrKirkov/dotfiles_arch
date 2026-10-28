package bus

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var fixedTime = time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC)

func newTestStore(t *testing.T, statePath string) *Store {
	t.Helper()
	s := NewStore(statePath)
	s.now = func() time.Time { return fixedTime }
	return s
}

func TestPublishRetainsLatestAndCountsSeq(t *testing.T) {
	s := newTestStore(t, "")
	if _, err := s.Publish("theme", []byte(`{"name":"a"}`)); err != nil {
		t.Fatal(err)
	}
	m, err := s.Publish("theme", []byte(`{"name":"b"}`))
	if err != nil {
		t.Fatal(err)
	}
	got, ok := s.Get("theme")
	if !ok {
		t.Fatal("theme not retained")
	}
	want := Message{Topic: "theme", Data: json.RawMessage(`{"name":"b"}`), Seq: 2, Time: fixedTime}
	if got.Topic != want.Topic || string(got.Data) != string(want.Data) || got.Seq != want.Seq || !got.Time.Equal(want.Time) {
		t.Fatalf("Get = %+v, want %+v", got, want)
	}
	if m.Seq != got.Seq {
		t.Fatalf("Publish returned seq %d, Get %d", m.Seq, got.Seq)
	}
}

func TestPublishRejectsBadInput(t *testing.T) {
	s := newTestStore(t, "")
	cases := []struct {
		name  string
		topic string
		data  string
		want  error
	}{
		{"uppercase topic", "Theme", `{}`, ErrInvalidTopic},
		{"empty topic", "", `{}`, ErrInvalidTopic},
		{"slash in topic", "a/b", `{}`, ErrInvalidTopic},
		{"not json", "theme", `{name`, ErrInvalidData},
		{"empty data", "theme", ``, ErrInvalidData},
		{"too large", "theme", `"` + strings.Repeat("x", MaxDataBytes) + `"`, ErrDataTooLarge},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := s.Publish(tc.topic, []byte(tc.data)); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
	if got := s.List(); len(got) != 0 {
		t.Fatalf("rejected publishes were retained: %+v", got)
	}
}

func TestSubscribeGetsCurrentThenNew(t *testing.T) {
	s := newTestStore(t, "")
	mustPublish(t, s, "theme", `"a"`)
	mustPublish(t, s, "other", `1`)

	sub, err := s.Subscribe([]string{"theme", "updates", "theme"})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Unsubscribe(sub)

	expectMessage(t, sub, "theme", `"a"`)
	mustPublish(t, s, "other", `2`) // not watched
	mustPublish(t, s, "updates", `{"packages":3}`)
	expectMessage(t, sub, "updates", `{"packages":3}`)
	select {
	case m := <-sub.C:
		t.Fatalf("unexpected message %+v", m)
	default:
	}
}

func TestSlowSubscriberIsDroppedWithoutBlocking(t *testing.T) {
	s := newTestStore(t, "")
	sub, err := s.Subscribe([]string{"t"})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < subscriberBuffer+10; i++ {
		mustPublish(t, s, "t", `0`)
	}
	n := 0
	for range sub.C {
		n++
	}
	// room for the buffer plus one current value per watched topic
	if want := subscriberBuffer + 1; n != want {
		t.Fatalf("received %d messages before the drop, want %d", n, want)
	}
	s.Unsubscribe(sub) // already dropped: must not panic
}

func TestCloseEndsSubscriptions(t *testing.T) {
	s := newTestStore(t, "")
	sub, err := s.Subscribe([]string{"t"})
	if err != nil {
		t.Fatal(err)
	}
	s.Close()
	if _, open := <-sub.C; open {
		t.Fatal("subscription still open after Close")
	}
	late, err := s.Subscribe([]string{"t"})
	if err != nil {
		t.Fatal(err)
	}
	if _, open := <-late.C; open {
		t.Fatal("subscription after Close is open")
	}
}

func TestStatePersistsAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state", "bus.json")
	s := newTestStore(t, path)
	mustPublish(t, s, "theme", `{"name":"a"}`)
	mustPublish(t, s, "updates", `{"packages":1}`)

	info, err := os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o700 {
		t.Fatalf("state dir mode = %o, want 700", perm)
	}

	restarted := newTestStore(t, path)
	if err := restarted.Load(); err != nil {
		t.Fatal(err)
	}
	got, ok := restarted.Get("theme")
	if !ok || string(got.Data) != `{"name":"a"}` {
		t.Fatalf("theme after restart = %+v, %v", got, ok)
	}
	m := mustPublish(t, restarted, "theme", `{"name":"b"}`)
	if m.Seq != 3 {
		t.Fatalf("seq after restart = %d, want 3", m.Seq)
	}
}

func TestLoadMissingFileIsEmpty(t *testing.T) {
	s := newTestStore(t, filepath.Join(t.TempDir(), "nope.json"))
	if err := s.Load(); err != nil {
		t.Fatal(err)
	}
	if got := s.List(); len(got) != 0 {
		t.Fatalf("List = %+v", got)
	}
}

func TestLoadCorruptFileFails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bus.json")
	if err := os.WriteFile(path, []byte("{"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := newTestStore(t, path).Load(); err == nil {
		t.Fatal("Load accepted a corrupt file")
	}
}

func TestSaveErrorDoesNotFailPublish(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "file")
	if err := os.WriteFile(blocker, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	s := newTestStore(t, filepath.Join(blocker, "bus.json")) // parent is a file
	var saveErr error
	s.OnSaveError = func(err error) { saveErr = err }
	if _, err := s.Publish("theme", []byte(`1`)); err != nil {
		t.Fatalf("Publish = %v", err)
	}
	if saveErr == nil {
		t.Fatal("OnSaveError not called")
	}
	if _, ok := s.Get("theme"); !ok {
		t.Fatal("message not retained after a save error")
	}
}

func mustPublish(t *testing.T, s *Store, topic, data string) Message {
	t.Helper()
	m, err := s.Publish(topic, []byte(data))
	if err != nil {
		t.Fatalf("Publish(%q, %s): %v", topic, data, err)
	}
	return m
}

func expectMessage(t *testing.T, sub *Subscription, topic, data string) {
	t.Helper()
	select {
	case m, open := <-sub.C:
		if !open {
			t.Fatalf("subscription closed, want %s", topic)
		}
		if m.Topic != topic || string(m.Data) != data {
			t.Fatalf("got %s %s, want %s %s", m.Topic, m.Data, topic, data)
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("no message, want %s", topic)
	}
}
