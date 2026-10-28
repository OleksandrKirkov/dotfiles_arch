package monitor

import (
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/OleksandrKirkov/dotfiles_arch/daemon/internal/bus"
)

type fixture struct {
	t     *testing.T
	dir   string
	store *bus.Store
	mon   *Monitor
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	f := &fixture{t: t, dir: dir, store: bus.NewStore("")}
	cfg := Config{
		PowerSupplyDir:    filepath.Join(dir, "power_supply"),
		MeminfoPath:       filepath.Join(dir, "meminfo"),
		BatteryLowPercent: 10,
		RAMHighBytes:      28 * 1_000_000_000,
	}
	if err := os.MkdirAll(cfg.PowerSupplyDir, 0o755); err != nil {
		t.Fatal(err)
	}
	f.mon = New(cfg, f.store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	f.memory(32_000_000, 30_000_000) // 2 GB used
	return f
}

func (f *fixture) write(rel, content string) {
	f.t.Helper()
	path := filepath.Join(f.dir, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) battery(capacity, status string) {
	f.write("power_supply/BAT0/capacity", capacity+"\n")
	f.write("power_supply/BAT0/status", status+"\n")
}

// memory sets MemTotal and MemAvailable, in KiB as /proc/meminfo lists them.
func (f *fixture) memory(totalKiB, availableKiB int) {
	f.write("meminfo", "MemTotal:       "+itoa(totalKiB)+" kB\nMemFree:        1 kB\nMemAvailable:   "+itoa(availableKiB)+" kB\n")
}

func itoa(n int) string { b, _ := json.Marshal(n); return string(b) }

// published returns the alerts topic and its seq.
func (f *fixture) published() (Data, uint64) {
	f.t.Helper()
	m, ok := f.store.Get(Topic)
	if !ok {
		f.t.Fatal("alerts never published")
	}
	var d Data
	if err := json.Unmarshal(m.Data, &d); err != nil {
		f.t.Fatal(err)
	}
	return d, m.Seq
}

func ids(d Data) []string {
	out := []string{}
	for _, a := range d.Active {
		out = append(out, a.ID)
	}
	return out
}

func TestFirstTickPublishesEmpty(t *testing.T) {
	f := newFixture(t)
	f.battery("80", "Discharging")
	f.mon.Tick()
	d, _ := f.published()
	if len(d.Active) != 0 {
		t.Fatalf("active = %+v", d.Active)
	}
	raw, _ := f.store.Get(Topic)
	if string(raw.Data) != `{"active":[]}` {
		t.Fatalf("data = %s, want an empty list, not null", raw.Data)
	}
}

func TestBatteryLowRaisesOnceAndRearms(t *testing.T) {
	f := newFixture(t)
	f.battery("9", "Discharging")
	f.mon.Tick()
	d, seq := f.published()
	if got := ids(d); len(got) != 1 || got[0] != "battery.low" {
		t.Fatalf("ids = %v", got)
	}
	want := Alert{ID: "battery.low", Urgency: "critical", Icon: "battery-caution",
		Summary: "Low battery", Body: "9% left. Plug in the charger."}
	if d.Active[0] != want {
		t.Fatalf("alert = %+v, want %+v", d.Active[0], want)
	}

	f.battery("8", "Discharging") // still low: no new publish, text kept
	f.mon.Tick()
	if _, again := f.published(); again != seq {
		t.Fatalf("republished while still low (seq %d -> %d)", seq, again)
	}

	f.battery("8", "Charging") // recovered
	f.mon.Tick()
	if d, _ := f.published(); len(d.Active) != 0 {
		t.Fatalf("still active after charging: %v", ids(d))
	}

	f.battery("7", "Discharging") // crosses again: raised again
	f.mon.Tick()
	if d, _ := f.published(); len(d.Active) != 1 || d.Active[0].Body != "7% left. Plug in the charger." {
		t.Fatalf("not re-raised: %+v", d.Active)
	}
}

func TestBatteryAtThresholdOrChargingIsFine(t *testing.T) {
	cases := []struct{ capacity, status string }{
		{"10", "Discharging"},
		{"5", "Charging"},
		{"5", "Full"},
	}
	for _, tc := range cases {
		t.Run(tc.capacity+" "+tc.status, func(t *testing.T) {
			f := newFixture(t)
			f.battery(tc.capacity, tc.status)
			f.mon.Tick()
			if d, _ := f.published(); len(d.Active) != 0 {
				t.Fatalf("active = %v", ids(d))
			}
		})
	}
}

func TestNoBatteryIsFine(t *testing.T) {
	f := newFixture(t)
	f.mon.Tick()
	if d, _ := f.published(); len(d.Active) != 0 {
		t.Fatalf("active = %v", ids(d))
	}
}

func TestMemoryHigh(t *testing.T) {
	f := newFixture(t)
	// 30 000 000 KiB used = 30.72 GB > 28 GB
	f.memory(32_000_000, 2_000_000)
	f.battery("9", "Discharging")
	f.mon.Tick()
	d, _ := f.published()
	if got := ids(d); len(got) != 2 || got[0] != "battery.low" || got[1] != "memory.high" {
		t.Fatalf("ids = %v", got)
	}
	if body := d.Active[1].Body; body != "30.7 GB in use (limit 28 GB)." {
		t.Fatalf("body = %q", body)
	}
}

func TestUnreadableMeminfoRaisesNothing(t *testing.T) {
	f := newFixture(t)
	f.write("meminfo", "garbage\n")
	f.mon.Tick()
	if d, _ := f.published(); len(d.Active) != 0 {
		t.Fatalf("active = %v", ids(d))
	}
}
