# dotctl bus

`dotctld` keeps the last message of every topic and streams new ones to whoever watches. Desktop tools
(waybar, rofi, dunst, scripts) read from it instead of each polling the system on a timer. Publishers are
scripts and hooks: they push a value when it changes.

- Retained: a watcher first gets the current value of each topic it asks for, then every new one.
- Persistent: values survive a daemon restart (`${XDG_STATE_HOME:-~/.local/state}/dotctl/bus.json`).
- Local and private: a Unix socket at `$XDG_RUNTIME_DIR/dotctl/bus.sock`, mode `0600`.
- Optional: every tool must keep working when `dotctld` is not running. Publishers ignore exit status 3.

Source: `daemon/` (Go, standard library only). Service: `dotctld.service` (module `bus`).

## CLI

```sh
dotctl bus ping                          # is dotctld running?
dotctl bus topics                        # every retained topic
dotctl bus get [--data] <topic>          # current message (or just its data)
dotctl bus publish <topic> '<json>'      # '-' reads the data from stdin
dotctl bus watch [--data] <topic>...     # current values, then each new one, one JSON object per line
```

Exit status: `0` ok, `1` rejected (bad topic or data), `3` dotctld not running, `4` nothing published yet.

## Messages

```json
{"topic": "theme", "data": {"name": "tokyonight", "wallpaper": "/path.jpg"}, "seq": 42, "time": "2026-10-28T12:00:00Z"}
```

- `topic`: `^[a-z][a-z0-9.-]{0,63}$`
- `data`: any JSON value, at most 64 KiB
- `seq`: increases with every publish on any topic
- `time`: when it was published, UTC

## HTTP API

The socket speaks HTTP/1.1, so `curl --unix-socket` is the client; the host name is ignored.

| Request | Response |
| --- | --- |
| `GET /v1/ping` | `{"ok": true}` |
| `GET /v1/topics` | `{"topics": [message...]}`, sorted by topic |
| `GET /v1/topics/{topic}` | the message; `404` when nothing was published |
| `PUT /v1/topics/{topic}` | body: the JSON data; returns the new message |
| `GET /v1/watch?topic=a&topic=b` | `application/x-ndjson` stream of messages |

Errors are `{"error": "..."}` with `400` (bad topic or data), `404`, `405` or `413` (data too large).
A watcher that falls 64 messages behind is disconnected rather than slowing publishers down; the stream also
ends when `dotctld` stops. Watchers reconnect.

## Topics

### `theme`

The active desktop theme. Published by `theme-switch` after every switch and `--apply`.

```json
{"name": "tokyonight", "wallpaper": "/home/me/Pictures/Wallpapers/x.jpg"}
```

### `updates`

Pending updates. Published by `dotctl updates --publish`: hourly by `dotctl-updates.timer`, and after every
`dotctl update`.

```json
{"repo": 0, "packages": 14, "aur": 2, "checked": "2026-10-28T14:00:00+02:00"}
```

- `repo`: commits on this repo's upstream not pulled yet
- `packages`: pacman updates (`checkupdates`)
- `aur`: AUR updates (`yay -Qua`)

A count is `null` when it cannot be known: no upstream, tool missing, or the check failed.

### `alerts`

Conditions that need attention now. Published by `dotctld` itself, which checks every 30 s and publishes only
when the set of active alerts changes: one alert per threshold crossing, re-armed once the value recovers.
Its text is fixed when it is raised.

```json
{"active": [
  {"id": "battery.low", "urgency": "critical", "icon": "battery-caution",
   "summary": "Low battery", "body": "9% left. Plug in the charger."}
]}
```

| id | raised while | flag (default) |
| --- | --- | --- |
| `battery.low` | the first battery is discharging below the threshold | `-battery-low` (10 %) |
| `memory.high` | MemTotal − MemAvailable is above the threshold | `-ram-high-gb` (28 GB, 10^9 bytes) |

`-alert-interval` (30s) sets the check period; `-alerts=false` turns the checks off.
`dotctl notify-alerts` (module `dunst`) turns new alerts into desktop notifications.

## Adding a topic

1. Pick a name no other topic uses; prefer one word, use `.` for a family (`power.profile`).
2. Document its data here before the first publish: the shape is the contract with every consumer.
3. Publish on change, from the script or hook that causes the change, with `dotctl bus publish`.
   Treat exit status `3` as "nobody is listening", never as a failure.
4. Only add a topic for state that waybar, rofi or dunst cannot already read event-driven on their own
   (battery, network, audio, bluetooth and Hyprland already have native modules).
