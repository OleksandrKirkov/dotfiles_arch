package bus

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
)

// NewHandler serves the bus API (see docs/bus.md):
//
//	GET  /v1/ping                    {"ok":true}
//	GET  /v1/topics                  {"topics":[Message...]}
//	GET  /v1/topics/{topic}          Message, 404 when nothing was published
//	PUT  /v1/topics/{topic}          body: JSON data; returns the new Message
//	GET  /v1/watch?topic=a&topic=b   NDJSON stream of Messages, current values first
func NewHandler(store *Store, log *slog.Logger) http.Handler {
	h := &handler{store: store, log: log}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/ping", h.ping)
	mux.HandleFunc("GET /v1/topics", h.list)
	mux.HandleFunc("GET /v1/topics/{topic}", h.get)
	mux.HandleFunc("PUT /v1/topics/{topic}", h.put)
	mux.HandleFunc("GET /v1/watch", h.watch)
	return mux
}

type handler struct {
	store *Store
	log   *slog.Logger
}

type errorBody struct {
	Error string `json:"error"`
}

func (h *handler) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		h.log.Debug("write response", "err", err)
	}
}

func (h *handler) fail(w http.ResponseWriter, status int, msg string) {
	h.writeJSON(w, status, errorBody{Error: msg})
}

func (h *handler) ping(w http.ResponseWriter, _ *http.Request) {
	h.writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *handler) list(w http.ResponseWriter, _ *http.Request) {
	h.writeJSON(w, http.StatusOK, map[string][]Message{"topics": h.store.List()})
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	topic := r.PathValue("topic")
	if !ValidTopic(topic) {
		h.fail(w, http.StatusBadRequest, ErrInvalidTopic.Error())
		return
	}
	m, ok := h.store.Get(topic)
	if !ok {
		h.fail(w, http.StatusNotFound, "nothing published on "+topic)
		return
	}
	h.writeJSON(w, http.StatusOK, m)
}

func (h *handler) put(w http.ResponseWriter, r *http.Request) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxDataBytes+1))
	var tooLarge *http.MaxBytesError
	switch {
	case errors.As(err, &tooLarge):
		h.fail(w, http.StatusRequestEntityTooLarge, ErrDataTooLarge.Error())
		return
	case err != nil:
		h.fail(w, http.StatusBadRequest, "read body: "+err.Error())
		return
	}
	m, err := h.store.Publish(r.PathValue("topic"), data)
	switch {
	case errors.Is(err, ErrDataTooLarge):
		h.fail(w, http.StatusRequestEntityTooLarge, err.Error())
		return
	case err != nil:
		h.fail(w, http.StatusBadRequest, err.Error())
		return
	}
	h.log.Debug("published", "topic", m.Topic, "seq", m.Seq)
	h.writeJSON(w, http.StatusOK, m)
}

func (h *handler) watch(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		h.fail(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}
	sub, err := h.store.Subscribe(r.URL.Query()["topic"])
	if err != nil {
		h.fail(w, http.StatusBadRequest, err.Error())
		return
	}
	defer h.store.Unsubscribe(sub)

	w.Header().Set("Content-Type", "application/x-ndjson")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	enc := json.NewEncoder(w)
	for {
		select {
		case <-r.Context().Done():
			return
		case m, open := <-sub.C:
			if !open {
				return // fell behind, or the daemon is stopping
			}
			if err := enc.Encode(m); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

// Listen opens the Unix socket at path for the current user only. A socket
// left behind by a daemon that is gone is replaced; one that still answers
// means another daemon is running, which is an error.
func Listen(path string) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	if _, err := os.Lstat(path); err == nil {
		if conn, err := net.Dial("unix", path); err == nil {
			conn.Close()
			return nil, errors.New("another dotctld is already listening on " + path)
		}
		if err := os.Remove(path); err != nil {
			return nil, err
		}
	}
	ln, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	return ln, nil
}
