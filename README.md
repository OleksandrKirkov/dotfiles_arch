# dotfiles_arch

## Installation

```sh
git clone git@github.com:OleksandrKirkov/dotfiles_arch.git ~/dotfiles_arch
cd ~/dotfiles_arch
./install.sh
```

`install.sh` installs packages, links the repo root into `~` with `stow .`, then links every module with
`dotctl apply`.

## dotctl

`dotctl` turns the repo into modules. It is linked to `~/.local/bin/dotctl`.

```sh
dotctl list                  # modules, scope, last applied
dotctl apply --dry-run tmux  # show what would change
dotctl apply                 # link every module, dependencies first
dotctl backup list           # files dotctl moved out of the way
dotctl backup restore <id>   # put them back
```

A module is a directory under `modules/`:

```
modules/<name>/
  module.conf          DESCRIPTION, SCOPE=user, DEPENDS=(other modules)
  home/                linked into ~ with stow --no-folding
  hooks/<event>.d/     executables run in name order after the event (event: link)
```

Anything already at a module's target path is moved to `~/.local/state/dotctl/backups/<id>/`, never deleted.
Links left by the old repo-root `stow .` are replaced. Your own hooks go in `~/.config/dotctl/hooks/<event>.d/`.

Configs not yet moved into `modules/` are still linked by `stow .` from the repo root.

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
