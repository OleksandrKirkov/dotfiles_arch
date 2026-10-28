// Command dotctld is the dotctl bus: it keeps the last message of every topic
// and streams new ones to the desktop tools over a Unix socket.
//
// Socket: $DOTCTL_BUS, default $XDG_RUNTIME_DIR/dotctl/bus.sock
// State:  $DOTCTL_BUS_STATE, default ${XDG_STATE_HOME:-~/.local/state}/dotctl/bus.json
//
// See docs/bus.md for the API and the topics.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/OleksandrKirkov/dotfiles_arch/daemon/internal/bus"
	"github.com/OleksandrKirkov/dotfiles_arch/daemon/internal/monitor"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "dotctld:", err)
		os.Exit(1)
	}
}

func run() error {
	socketPath, statePath, err := defaultPaths()
	if err != nil {
		return err
	}
	flag.StringVar(&socketPath, "socket", socketPath, "Unix socket to listen on")
	flag.StringVar(&statePath, "state", statePath, "file retained messages are saved to (empty: memory only)")
	debug := flag.Bool("debug", false, "log every publish")
	alertCfg := monitor.DefaultConfig()
	alerts := flag.Bool("alerts", true, `publish battery and RAM alerts on the "alerts" topic`)
	flag.IntVar(&alertCfg.BatteryLowPercent, "battery-low", alertCfg.BatteryLowPercent, "alert when discharging below this percent")
	ramHighGB := flag.Float64("ram-high-gb", float64(alertCfg.RAMHighBytes)/1e9, "alert when used RAM exceeds this many GB (10^9 bytes)")
	flag.DurationVar(&alertCfg.Interval, "alert-interval", alertCfg.Interval, "time between alert checks")
	flag.Parse()
	if *ramHighGB <= 0 || alertCfg.BatteryLowPercent < 0 || alertCfg.Interval <= 0 {
		return errors.New("-ram-high-gb and -alert-interval must be positive, -battery-low not negative")
	}
	alertCfg.RAMHighBytes = uint64(*ramHighGB * 1e9)

	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	store := bus.NewStore(statePath)
	store.OnSaveError = func(err error) { log.Warn("bus state not saved", "err", err) }
	if err := store.Load(); err != nil {
		log.Warn("starting without saved state", "err", err)
	}

	ln, err := bus.Listen(socketPath)
	if err != nil {
		return err
	}
	defer os.Remove(socketPath)

	srv := &http.Server{
		Handler:           bus.NewHandler(store, log),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()
	if *alerts {
		go monitor.New(alertCfg, store, log).Run(ctx)
	}
	log.Info("listening", "socket", socketPath, "state", statePath, "topics", len(store.List()))

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}

	log.Info("stopping")
	store.Close() // ends every watch stream so Shutdown does not wait on them
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func defaultPaths() (socketPath, statePath string, err error) {
	socketPath = os.Getenv("DOTCTL_BUS")
	if socketPath == "" {
		runtime := os.Getenv("XDG_RUNTIME_DIR")
		if runtime == "" {
			return "", "", errors.New("XDG_RUNTIME_DIR is not set; set DOTCTL_BUS or pass -socket")
		}
		socketPath = filepath.Join(runtime, "dotctl", "bus.sock")
	}

	statePath, ok := os.LookupEnv("DOTCTL_BUS_STATE")
	if !ok {
		stateHome := os.Getenv("XDG_STATE_HOME")
		if stateHome == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", "", err
			}
			stateHome = filepath.Join(home, ".local", "state")
		}
		statePath = filepath.Join(stateHome, "dotctl", "bus.json")
	}
	return socketPath, statePath, nil
}
