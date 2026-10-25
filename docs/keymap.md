# Keymap

- [Hyprland](#hyprland)
- [tmux](#tmux)

## Hyprland

Config: `.config/hypr/binds.lua`, app choices in `.config/hypr/apps.lua`. `SUPER` is the main modifier.
`hyprctl binds` lists what the running session has loaded.

### Apps

| Keys | Action |
|---|---|
| `SUPER+Q` | Terminal (ghostty) |
| `SUPER+B` | Browser (Brave) |
| `SUPER+E` | Terminal file manager (yazi in ghostty) |
| `SUPER+SHIFT+E` | File manager (nautilus) |
| `SUPER+Space`, `SUPER+D` | App launcher (rofi) |
| `SUPER+O` | Obsidian |
| `SUPER+SHIFT+V` | Clipboard history (cliphist in rofi; the pick is copied) |
| `ALT+S` | Screenshot of a selected area to the clipboard (grim + slurp) |

### Windows

| Keys | Action |
|---|---|
| `SUPER+W` | Close the window |
| `SUPER+V`, `ALT+F` | Toggle floating |
| `SUPER+F` | Toggle fullscreen |
| `SUPER+H` / `J` / `K` / `L` | Focus the window left / below / above / right |
| `SUPER+SHIFT+H` / `J` / `K` / `L` | Move the window left / below / above / right |
| `SUPER+Arrows` | Resize the window by 20 px (hold to repeat) |
| `SUPER+SHIFT+Arrows` | Resize the window by 50 px (hold to repeat) |
| `ALT+Tab` / `ALT+SHIFT+Tab` | Cycle to the next / previous window |
| `SUPER+Left drag` | Move the window with the mouse |
| `SUPER+Right drag` | Resize the window with the mouse |

### Workspaces

| Keys | Action |
|---|---|
| `SUPER+1` .. `SUPER+0` | Go to workspace 1..10 |
| `SUPER+SHIFT+1` .. `SUPER+SHIFT+0` | Move the window to workspace 1..10 |
| `SUPER+ALT+1` .. `SUPER+ALT+0` | Go to workspace 11..20 |
| `SUPER+SHIFT+ALT+1` .. `SUPER+SHIFT+ALT+0` | Move the window to workspace 11..20 |
| `SUPER+Tab` | Previous workspace |
| `SUPER+Scroll down` / `SUPER+Scroll up` | Next / previous workspace |

### System

| Keys | Action |
|---|---|
| `SUPER+Escape` | Lock the screen |
| `SUPER+T` | Apply the current theme (`theme-switch --apply`) |
| `SUPER+SHIFT+T` | Pick a theme (`theme-switch --pick`) |
| `SUPER+M` | Start waybar |
| `SUPER+N` | Stop waybar |

### Media keys

These also work on the lock screen. Volume and brightness repeat while held.

| Keys | Action |
|---|---|
| Volume up / down | Volume ±5% (up to 140%) |
| Mute | Mute / unmute the output |
| Mic mute | Mute / unmute the microphone |
| Brightness up / down | Brightness ±10% |
| Play/Pause, Next, Previous | Media player control (playerctl) |

## tmux

Config: `.config/tmux/tmux.conf`, helper scripts in `.config/tmux/scripts/`.
The prefix is `Ctrl+Space`: press it, release, then press the key. `Prefix ?` lists every bind, `Prefix /` describes one key.

Status bar badges: `PREFIX` (yellow) after the prefix, `COPY` (blue) in copy mode, `ZOOM` (magenta) on a zoomed pane,
`SYNC` (red) while panes are synchronized. A red bell on a window means a program in the background rang the bell.

### Panes

| Keys | Action |
|---|---|
| `Prefix \|` | Split right in the current directory |
| `Prefix -` | Split below in the current directory |
| `Ctrl+H` / `Ctrl+J` / `Ctrl+K` / `Ctrl+L` | Move to the pane left / below / above / right (passes through to nvim splits and fzf) |
| `Prefix h` / `j` / `k` / `l` | Move to the pane left / below / above / right |
| `Prefix H` / `J` / `K` / `L` | Resize the pane by 5 cells (hold to repeat) |
| `Prefix T` | Rename the pane (title shown on the border when a window has 2+ panes) |
| `Prefix z` | Zoom / unzoom the pane (tmux default) |
| `Prefix x` | Kill the pane (tmux default) |

### Windows

| Keys | Action |
|---|---|
| `Prefix c` | New window in the current directory |
| `Alt+H` / `Alt+L` | Previous / next window |
| `Alt+Space`, `Prefix Tab` | Last window |
| `Alt+1` .. `Alt+9` | Jump to window 1..9 |
| `Alt+Shift+H` / `Alt+Shift+L` | Move the window left / right |
| `Prefix ,` | Rename the window (tmux default) |
| `Prefix &` | Kill the window (tmux default) |

### Apps and popups

| Keys | Action |
|---|---|
| `Prefix g` | New window running lazygit |
| `Prefix d` | New window running lazydocker |
| `Prefix y` | New window running yazi |
| ``Prefix ` `` | Popup shell in the pane's directory |
| `Prefix u` | URL picker from the scrollback: Enter opens, `Ctrl+Y` copies, Tab selects several (needs fzf) |
| `Prefix e` | File-tree sidebar (tmux-sidebar) |
| `Prefix E` | File-tree sidebar, focused |
| `Prefix f` | Hints on URLs, paths, SHAs, IPs: the letter copies, `Ctrl+letter` opens, `Shift+letter` pastes, Tab selects several (needs tmux-fingers; without it `Prefix f` is tmux's find-window) |
| `Prefix F` | Hints, jump mode: the cursor goes to the match in copy mode (needs tmux-fingers) |

### Sessions

| Keys | Action |
|---|---|
| `Prefix C` | New session (the name is required and must be unique) |
| `Prefix X`, `Prefix Ctrl+X` | Kill-session picker: Tab selects several, Enter kills after a y/N (needs fzf) |
| `Prefix Q` | Kill the current session (confirm) and land in a fresh unnamed one |
| `Prefix D` | Detach |
| `Prefix s` | Choose a session (tmux default) |
| `Prefix $` | Rename the session (tmux default) |

### Snapshots (tmux-resurrect)

Snapshots are only saved by hand; there is no autosave. Files live in `~/.local/share/tmux/resurrect/`.

| Keys | Action |
|---|---|
| `Prefix S`, `Prefix Ctrl+S` | Save a snapshot under a unique name |
| `Prefix R`, `Prefix Ctrl+R` | Restore a snapshot from an fzf list with a preview; `Ctrl+D` / `Ctrl+X` deletes one (needs fzf) |
| `Prefix N` | Save the current session under its name (asks for one if it is unnamed), then start a new unnamed session |

### Copy mode (vi)

Everything copied goes to the Wayland clipboard (`wl-copy`).

| Keys | Action |
|---|---|
| `Prefix [`, `Prefix Esc` | Enter copy mode |
| `v` | Begin selection |
| `V` | Select the line |
| `Ctrl+V` | Toggle rectangle selection |
| `y` | Copy and leave |
| `Esc` | Leave copy mode |
| Mouse drag | Copy the selection |
| Double click / triple click | Copy the word / the line (outside copy mode too, unless the app uses the mouse) |

### Other

| Keys | Action |
|---|---|
| `Prefix r` | Reload `tmux.conf` |
| `Prefix Ctrl+Space` | Send the prefix to the program inside |
| `Prefix I` / `Prefix U` / `Prefix Alt+U` | TPM: install / update / remove plugins |

Taken from other programs: `Ctrl+L` no longer clears the shell (use `clear`), and `Alt+H` / `Alt+L` no longer reach zsh or nvim.
