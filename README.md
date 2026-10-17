# dotfiles_arch

## Installation

```sh
git clone git@github.com:OleksandrKirkov/dotfiles_arch.git ~/dotfiles_arch
cd ~/dotfiles_arch
./install.sh
```

`install.sh` installs packages, removes existing configs, and links this repo into `~` with `stow .`.

## Secrets

Secrets are never tracked. Put them in `~/.zshrc.local` (sourced by `.zshrc`):

```sh
export ARTIFACTKEEPER_TOKEN=...
export MSSQL_SA_PASSWORD=...
```

```sh
chmod 600 ~/.zshrc.local
```
