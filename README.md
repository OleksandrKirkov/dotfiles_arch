# dotfiles_arch

## Installation

```sh
git clone git@github.com:OleksandrKirkov/dotfiles_arch.git ~/dotfiles_arch
cd ~/dotfiles_arch
./install.sh
```

`install.sh` runs `dotctl install` (packages, services, install hooks), `dotctl apply` (links), then
`theme-switch --apply`.

## dotctl

`dotctl` turns the repo into modules. It is linked to `~/.local/bin/dotctl`.

```sh
dotctl list                    # modules, scope, last applied
dotctl install --dry-run       # packages, services and install hooks it would run
dotctl install                 # install them
dotctl apply --dry-run tmux    # show what linking would change
dotctl apply                   # link modules, dependencies first
dotctl doctor [--drift]        # links, packages, services; --drift lists undeclared packages
dotctl backup list             # files dotctl moved out of the way
dotctl backup restore <id>     # put them back
```

With no module names, commands use `hosts/<hostname>.conf` (`MODULES=(...)`), or every module when this
machine has no host file.

A module is a directory under `modules/`:

```
modules/<name>/
  module.conf          DESCRIPTION, SCOPE=user, DEPENDS=(...),
                       PACMAN=(...), AUR=(...), FLATPAK=(...), NPM=(...),
                       SERVICES=(...), SERVICES_DISABLE=(...)
  home/                linked into ~ with stow --no-folding
  hooks/install.d/     run by dotctl install, after packages and services
  hooks/link.d/        run by dotctl apply, after the module is linked
```

Anything already at a module's target path is moved to `~/.local/state/dotctl/backups/<id>/`, never deleted.
Your own hooks go in `~/.config/dotctl/hooks/<event>.d/`.

`themes/` holds theme packages read by `theme-switch` (module `theme`).

Tests: `tests/dotctl.sh` (runs in a temporary directory, never touches `~`).

## Secrets

Secrets are never tracked. Put them in `~/.zshrc.local` (sourced by `.zshrc`):

```sh
export ARTIFACTKEEPER_TOKEN=...
export MSSQL_SA_PASSWORD=...
```

```sh
chmod 600 ~/.zshrc.local
```
