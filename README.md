# dotfiles_arch

## Installation

```sh
git clone git@github.com:OleksandrKirkov/dotfiles_arch.git ~/dotfiles_arch
cd ~/dotfiles_arch
./install.sh
```

`install.sh` runs `dotctl install` (packages, services, install hooks), `dotctl apply` (links),
`theme-switch --apply`, then `dotctl migrate`.

Later, `dotctl update` keeps the machine in sync: `git pull --ff-only`, then install, apply, migrate and the
`update` hooks, using the dotctl that was just pulled.

## dotctl

`dotctl` turns the repo into modules. It is linked to `~/.local/bin/dotctl`.

```sh
dotctl list                    # modules, scope, last applied
dotctl install --dry-run       # packages, services and install hooks it would run
dotctl install                 # install them
dotctl apply --dry-run tmux    # show what linking would change
dotctl apply                   # link modules, dependencies first
dotctl update [--dry-run]      # pull, install, apply, migrate, update hooks
dotctl migrate [--status]      # run pending one-time migrations, or list them
dotctl doctor [--drift]        # links, packages, services, migrations; --drift lists undeclared packages
dotctl backup list             # files dotctl moved out of the way or copied
dotctl backup add <path>       # copy a file into a backup (migrations call this before a change)
dotctl backup restore <id>     # put them back
dotctl bus watch theme         # dotctld topics (see docs/bus.md)
dotctl updates                 # pending repo, pacman and AUR updates (module bus)
dotctl menu [power|bluetooth|theme|updates]   # rofi menus (module rofi)
```

A module can add commands: `modules/<name>/libexec/dotctl-<command>` becomes `dotctl <command>`, and menus:
`modules/<name>/menus/<menu>` becomes `dotctl menu <menu>`.

With no module names, commands use `hosts/<hostname>.conf` (`MODULES=(...)`), or every module when this
machine has no host file.

A module is a directory under `modules/`:

```
modules/<name>/
  module.conf          DESCRIPTION, SCOPE=user, DEPENDS=(...),
                       PACMAN=(...), AUR=(...), FLATPAK=(...), NPM=(...),
                       SERVICES=(...), SERVICES_DISABLE=(...)
  home/                linked into ~ with stow --no-folding
  libexec/dotctl-<cmd> a dotctl command
  menus/<menu>         a rofi menu (sources modules/rofi/lib/menu.sh for the shared picker)
  hooks/install.d/     run by dotctl install, after packages and services
  hooks/link.d/        run by dotctl apply, after the module is linked
  hooks/update.d/      run by dotctl update, last
  migrations/NNNN-slug run once per machine by dotctl migrate, after linking
```

A migration moves a machine from an older layout to the current one. It must be a no-op where there is nothing
to migrate (a fresh install), copy any file it changes with `dotctl backup add` first, and exit non-zero to stop
for a person to decide. Ran migrations are recorded in `~/.local/state/dotctl/migrations`.

Anything already at a module's target path is moved to `~/.local/state/dotctl/backups/<id>/`, never deleted.
Each apply records what a module linked (`~/.local/state/dotctl/links/<module>`); when a module stops
shipping a file, the next apply removes the link that now points at nothing. Your own hooks go in
`~/.config/dotctl/hooks/<event>.d/`.

`themes/` holds theme packages read by `theme-switch` (module `theme`).

## Bus

`dotctld` (source in `daemon/`, module `bus`) keeps the last value of every topic and streams changes to the
desktop tools, so they react to events instead of polling. Topics, API and the rules for adding one:
[docs/bus.md](docs/bus.md).

How the tools use it:

| Tool | Reads | Through |
| --- | --- | --- |
| waybar `custom/updates` | `updates` | `dotctl bus watch --format ~/.config/waybar/bus/updates.jq updates` |
| dunst | `alerts` (battery, RAM) | `dotctl-notify.service` → `dotctl notify-alerts` → `notify-send` |
| rofi `dotctl menu updates` | `updates` | `dotctl bus get` |

Everything else on the bar (battery, network, audio, bluetooth, workspaces) uses waybar's own event-driven
modules. Every tool keeps working when `dotctld` is down; the bus-backed parts just show nothing.

Tests: `tests/dotctl.sh` (runs in a temporary directory, never touches `~`; builds dotctld, so it needs Go) and
`go -C daemon test -race ./...`.

## Secrets

Secrets are never tracked. Put them in `~/.zshrc.local` (sourced by `.zshrc`):

```sh
export ARTIFACTKEEPER_TOKEN=...
export MSSQL_SA_PASSWORD=...
```

```sh
chmod 600 ~/.zshrc.local
```
