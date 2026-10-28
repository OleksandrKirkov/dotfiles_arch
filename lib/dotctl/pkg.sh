# shellcheck shell=bash
# pkg.sh: install the packages and set the services modules declare.
#
# Privileged steps go through sudo; AUR packages through yay, which is built
# from the AUR the first time it is needed.

# pkg_collect <FIELD> <module...>: the field's values across modules, first
# occurrence order, duplicates dropped.
pkg_collect() {
    local field="$1" module out=""
    shift
    for module in "$@"; do
        out+="$(manifest_field "$module" "$field")"$'\n'
    done
    awk 'NF && !seen[$0]++' <<<"$out"
}

# _pkg_run <command...>: run it, or print it in a dry run.
_pkg_run() {
    if dry_run; then
        log "would run: $*"
        return 0
    fi
    log "run: $*"
    "$@"
}

_pkg_list() {
    local -n _out="$1"
    local values
    values="$(pkg_collect "$2" "${@:3}")"
    _out=()
    [[ -z "$values" ]] || mapfile -t _out <<<"$values"
}

pkg_ensure_yay() {
    command -v yay >/dev/null && return 0
    if dry_run; then
        log "would build yay-bin from the AUR"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    log "building yay-bin from the AUR"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf -- "$tmp"
}

# pkg_install <module...>: pacman, then AUR, flatpak, npm, then services.
pkg_install() {
    local -a list

    _pkg_list list PACMAN "$@"
    # -Syu with the install: a sync without the upgrade is a partial upgrade.
    ((${#list[@]} == 0)) || _pkg_run sudo pacman -Syu --needed --noconfirm "${list[@]}"

    _pkg_list list AUR "$@"
    if ((${#list[@]})); then
        pkg_ensure_yay
        _pkg_run yay -S --needed --noconfirm "${list[@]}"
    fi

    _pkg_list list FLATPAK "$@"
    ((${#list[@]} == 0)) || _pkg_run sudo flatpak install -y "${list[@]}"

    _pkg_list list NPM "$@"
    if ((${#list[@]})); then
        # The dev module's .npmrc sets the global prefix; read it from the repo
        # so this works before ~/.npmrc is linked.
        local npmrc="$DOTCTL_MODULES/dev/home/.npmrc"
        if [[ -f "$npmrc" ]]; then
            NPM_CONFIG_USERCONFIG="$npmrc" _pkg_run npm install -g "${list[@]}"
        else
            _pkg_run npm install -g "${list[@]}"
        fi
    fi

    _pkg_list list SERVICES "$@"
    ((${#list[@]} == 0)) || _pkg_run sudo systemctl enable "${list[@]}"

    _pkg_list list SERVICES_DISABLE "$@"
    ((${#list[@]} == 0)) || _pkg_run sudo systemctl disable "${list[@]}"
}
