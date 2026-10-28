// Package monitor raises low-battery and high-RAM alerts and publishes them
// on the bus topic "alerts" (see docs/bus.md). It replaces the polling
// system-alerts script: one alert per threshold crossing, re-armed once the
// value recovers.
package monitor

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/OleksandrKirkov/dotfiles_arch/daemon/internal/bus"
)

// Topic is the bus topic alerts are published on.
const Topic = "alerts"

// Alert is one active condition. Its text is fixed when it is raised.
type Alert struct {
	ID      string `json:"id"`
	Urgency string `json:"urgency"`
	Icon    string `json:"icon"`
	Summary string `json:"summary"`
	Body    string `json:"body"`
}

// Data is the payload of the alerts topic.
type Data struct {
	Active []Alert `json:"active"`
}

// Config holds the thresholds and where the readings come from.
type Config struct {
	PowerSupplyDir    string        // /sys/class/power_supply
	MeminfoPath       string        // /proc/meminfo
	BatteryLowPercent int           // alert when discharging below this
	RAMHighBytes      uint64        // alert when used RAM exceeds this
	Interval          time.Duration // time between checks
}

// DefaultConfig matches the thresholds system-alerts used.
func DefaultConfig() Config {
	return Config{
		PowerSupplyDir:    "/sys/class/power_supply",
		MeminfoPath:       "/proc/meminfo",
		BatteryLowPercent: 10,
		RAMHighBytes:      28 * 1_000_000_000,
		Interval:          30 * time.Second,
	}
}

// Publisher is the part of the bus store the monitor needs.
type Publisher interface {
	Publish(topic string, data []byte) (bus.Message, error)
}

// Monitor checks the readings and publishes when the set of alerts changes.
type Monitor struct {
	cfg       Config
	pub       Publisher
	log       *slog.Logger
	active    []Alert
	published bool
}

// New returns a monitor for cfg.
func New(cfg Config, pub Publisher, log *slog.Logger) *Monitor {
	return &Monitor{cfg: cfg, pub: pub, log: log}
}

// Run checks every cfg.Interval until ctx ends.
func (m *Monitor) Run(ctx context.Context) {
	ticker := time.NewTicker(m.cfg.Interval)
	defer ticker.Stop()
	for {
		m.Tick()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// Tick runs one check and publishes if the active alerts changed (or on the
// first tick, so the topic always exists).
func (m *Monitor) Tick() {
	next := make([]Alert, 0, 2)
	for _, check := range []func() (Alert, bool, error){m.battery, m.memory} {
		alert, raised, err := check()
		if err != nil {
			m.log.Debug("alert check", "err", err)
		}
		if !raised {
			continue
		}
		// Keep the text of an alert that is still active from when it was raised.
		if i := slices.IndexFunc(m.active, func(a Alert) bool { return a.ID == alert.ID }); i >= 0 {
			alert = m.active[i]
		}
		next = append(next, alert)
	}

	if m.published && sameIDs(m.active, next) {
		return
	}
	raw, err := json.Marshal(Data{Active: next})
	if err != nil {
		m.log.Warn("encode alerts", "err", err)
		return
	}
	if _, err := m.pub.Publish(Topic, raw); err != nil {
		m.log.Warn("publish alerts", "err", err)
		return
	}
	m.active, m.published = next, true
}

func sameIDs(a, b []Alert) bool {
	return slices.EqualFunc(a, b, func(x, y Alert) bool { return x.ID == y.ID })
}

// battery raises "battery.low" while the first battery discharges below the threshold.
func (m *Monitor) battery() (Alert, bool, error) {
	dirs, err := filepath.Glob(filepath.Join(m.cfg.PowerSupplyDir, "BAT*"))
	if err != nil || len(dirs) == 0 {
		return Alert{}, false, err // no battery: nothing to watch
	}
	slices.Sort(dirs)
	for _, dir := range dirs {
		capacity, err := readInt(filepath.Join(dir, "capacity"))
		if err != nil {
			continue
		}
		status, err := os.ReadFile(filepath.Join(dir, "status"))
		if err != nil {
			return Alert{}, false, err
		}
		if strings.TrimSpace(string(status)) != "Discharging" || capacity >= m.cfg.BatteryLowPercent {
			return Alert{}, false, nil
		}
		return Alert{
			ID:      "battery.low",
			Urgency: "critical",
			Icon:    "battery-caution",
			Summary: "Low battery",
			Body:    fmt.Sprintf("%d%% left. Plug in the charger.", capacity),
		}, true, nil
	}
	return Alert{}, false, nil
}

// memory raises "memory.high" while MemTotal - MemAvailable exceeds the threshold.
func (m *Monitor) memory() (Alert, bool, error) {
	total, available, err := readMeminfo(m.cfg.MeminfoPath)
	if err != nil {
		return Alert{}, false, err
	}
	used := total - available
	if used <= m.cfg.RAMHighBytes {
		return Alert{}, false, nil
	}
	return Alert{
		ID:      "memory.high",
		Urgency: "critical",
		Icon:    "dialog-warning",
		Summary: "High RAM usage",
		Body: fmt.Sprintf("%.1f GB in use (limit %.0f GB).",
			float64(used)/1e9, float64(m.cfg.RAMHighBytes)/1e9),
	}, true, nil
}

func readInt(path string) (int, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(raw)))
}

// readMeminfo returns MemTotal and MemAvailable in bytes.
func readMeminfo(path string) (total, available uint64, err error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	found := 0
	s := bufio.NewScanner(f)
	for s.Scan() {
		fields := strings.Fields(s.Text())
		if len(fields) < 2 {
			continue
		}
		var dst *uint64
		switch fields[0] {
		case "MemTotal:":
			dst = &total
		case "MemAvailable:":
			dst = &available
		default:
			continue
		}
		kib, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			return 0, 0, fmt.Errorf("%s: %w", path, err)
		}
		*dst = kib * 1024
		found++
	}
	if err := s.Err(); err != nil {
		return 0, 0, err
	}
	if found != 2 {
		return 0, 0, fmt.Errorf("%s: MemTotal or MemAvailable missing", path)
	}
	return total, available, nil
}
