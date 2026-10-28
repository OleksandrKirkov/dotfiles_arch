package bus

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// startServer serves a fresh store on a Unix socket, as dotctld does, and
// returns an HTTP client bound to that socket.
func startServer(t *testing.T) (*Store, *http.Client, string) {
	t.Helper()
	sock := filepath.Join(t.TempDir(), "run", "bus.sock")
	ln, err := Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	store := newTestStore(t, "")
	srv := &http.Server{Handler: NewHandler(store, slog.New(slog.NewTextHandler(io.Discard, nil)))}
	go func() { _ = srv.Serve(ln) }()
	t.Cleanup(func() {
		store.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	})
	client := &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", sock)
		},
	}}
	return store, client, sock
}

func do(t *testing.T, c *http.Client, method, path, body string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(method, "http://dotctl"+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp, err := c.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, strings.TrimSpace(string(raw))
}

func TestHTTPPutGetList(t *testing.T) {
	_, c, _ := startServer(t)

	if code, body := do(t, c, "GET", "/v1/ping", ""); code != 200 || body != `{"ok":true}` {
		t.Fatalf("ping = %d %s", code, body)
	}
	if code, body := do(t, c, "GET", "/v1/topics/theme", ""); code != 404 || !strings.Contains(body, "nothing published on theme") {
		t.Fatalf("get before put = %d %s", code, body)
	}

	code, body := do(t, c, "PUT", "/v1/topics/theme", `{"name":"tokyonight"}`)
	if code != 200 {
		t.Fatalf("put = %d %s", code, body)
	}
	var m Message
	if err := json.Unmarshal([]byte(body), &m); err != nil {
		t.Fatal(err)
	}
	if m.Topic != "theme" || string(m.Data) != `{"name":"tokyonight"}` || m.Seq != 1 {
		t.Fatalf("put returned %+v", m)
	}

	if code, body := do(t, c, "GET", "/v1/topics/theme", ""); code != 200 || !strings.Contains(body, `"data":{"name":"tokyonight"}`) {
		t.Fatalf("get = %d %s", code, body)
	}
	if code, body := do(t, c, "GET", "/v1/topics", ""); code != 200 || !strings.Contains(body, `"topic":"theme"`) {
		t.Fatalf("list = %d %s", code, body)
	}
}

func TestHTTPRejectsBadPuts(t *testing.T) {
	_, c, _ := startServer(t)
	cases := []struct {
		name, path, body string
		code             int
	}{
		{"bad topic", "/v1/topics/Bad", `1`, 400},
		{"bad json", "/v1/topics/theme", `{`, 400},
		{"too large", "/v1/topics/theme", `"` + strings.Repeat("x", MaxDataBytes+10) + `"`, 413},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, body := do(t, c, "PUT", tc.path, tc.body)
			if code != tc.code || !strings.Contains(body, `"error"`) {
				t.Fatalf("= %d %s, want %d with an error", code, body, tc.code)
			}
		})
	}
	if code, _ := do(t, c, "POST", "/v1/topics/theme", `1`); code != 405 {
		t.Fatalf("POST = %d, want 405", code)
	}
}

func TestHTTPWatchStreamsCurrentThenNew(t *testing.T) {
	store, c, _ := startServer(t)
	mustPublish(t, store, "theme", `"a"`)

	resp, err := c.Get("http://dotctl/v1/watch?topic=theme&topic=updates")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "application/x-ndjson" {
		t.Fatalf("watch = %d %s", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	lines := bufio.NewScanner(resp.Body)

	expectLine(t, lines, "theme", `"a"`)
	mustPublish(t, store, "ignored", `0`)
	mustPublish(t, store, "updates", `{"packages":2}`)
	expectLine(t, lines, "updates", `{"packages":2}`)

	store.Close() // daemon stopping: the stream ends
	if lines.Scan() {
		t.Fatalf("stream continued: %s", lines.Text())
	}
}

func TestHTTPWatchNeedsATopic(t *testing.T) {
	_, c, _ := startServer(t)
	if code, body := do(t, c, "GET", "/v1/watch", ""); code != 400 || !strings.Contains(body, "at least one topic") {
		t.Fatalf("= %d %s", code, body)
	}
}

func TestListenRefusesRunningDaemonAndReplacesStaleSocket(t *testing.T) {
	_, _, sock := startServer(t)
	if _, err := Listen(sock); err == nil || !strings.Contains(err.Error(), "already listening") {
		t.Fatalf("second Listen = %v", err)
	}

	stale := filepath.Join(t.TempDir(), "stale.sock")
	ln, err := net.Listen("unix", stale)
	if err != nil {
		t.Fatal(err)
	}
	// Close without unlinking leaves the socket file behind, as a crash would.
	ln.(*net.UnixListener).SetUnlinkOnClose(false)
	ln.Close()
	ln, err = Listen(stale)
	if err != nil {
		t.Fatalf("Listen over a stale socket: %v", err)
	}
	defer ln.Close()
	info, err := os.Stat(stale)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Fatalf("socket mode = %o, want 600", perm)
	}
}

func expectLine(t *testing.T, s *bufio.Scanner, topic, data string) {
	t.Helper()
	done := make(chan bool, 1)
	go func() { done <- s.Scan() }()
	select {
	case ok := <-done:
		if !ok {
			t.Fatalf("stream ended, want %s (%v)", topic, s.Err())
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("no line, want %s", topic)
	}
	var m Message
	if err := json.Unmarshal(s.Bytes(), &m); err != nil {
		t.Fatalf("bad line %q: %v", s.Text(), err)
	}
	if m.Topic != topic || string(m.Data) != data {
		t.Fatalf("got %s %s, want %s %s", m.Topic, m.Data, topic, data)
	}
}
