# shellcheck shell=bash
# manifest.sh: read modules/<name>/module.conf, hosts/<host>.conf, and order
# modules by DEPENDS.
#
# module.conf is plain bash holding data only, sourced in a subshell so a
# manifest can never change dotctl's own state:
#
#   DESCRIPTION="tmux config, scripts and snapshots"
#   SCOPE=user              # user: linked into $HOME; system: reserved for /etc (not yet supported)
#   DEPENDS=(zsh)           # modules handled before this one
#   PACMAN=(tmux)           # repo packages        (dotctl install)
#   AUR=(tmux-fingers)      # AUR packages via yay (dotctl install)
#   FLATPAK=(com.x.App)     # flatpak apps         (dotctl install)
#   NPM=(eslint_d)          # global npm packages  (dotctl install)
#   SERVICES=(tlp.service)  # system units to enable
#   SERVICES_DISABLE=(...)  # system units to disable
#
# hosts/<host>.conf picks the modules a machine uses when none are named:
#
#   MODULES=(base zsh tmux ...)
#
# <host> is $DOTCTL_HOST, default `uname -n`. No host file means every module.

MANIFEST_FIELDS=(DESCRIPTION SCOPE DEPENDS PACMAN AUR FLATPAK NPM SERVICES SERVICES_DISABLE)

module_dir() { printf '%s/%s\n' "$DOTCTL_MODULES" "$1"; }

module_exists() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]] && [[ -f "$(module_dir "$1")/module.conf" ]]
}

# Every module name, sorted.
module_all() {
    local conf
    for conf in "$DOTCTL_MODULES"/*/module.conf; do
        [[ -f "$conf" ]] || continue
        conf="${conf%/module.conf}"
        printf '%s\n' "${conf##*/}"
    done
}

# manifest_field <module> <FIELD>: print the field's values, one per line.
# An unset field prints nothing.
manifest_field() {
    local module="$1" field="$2"
    local conf
    conf="$(module_dir "$module")/module.conf"
    module_exists "$module" || die "unknown module: $module"
    (
        set +u # an empty array reads as unset under nounset
        # shellcheck disable=SC1090
        source "$conf" || exit 1
        declare -p "$field" &>/dev/null || exit 0
        declare -n value="$field"
        ((${#value[@]})) || exit 0
        printf '%s\n' "${value[@]}"
    ) || die "$conf: failed to load"
}

# manifest_check <module>: reject unknown fields, bad scope and unknown deps.
manifest_check() {
    local module="$1" conf var vars scope dep
    conf="$(module_dir "$module")/module.conf"
    module_exists "$module" || die "unknown module: $module"

    # Variables the manifest defines that are not in MANIFEST_FIELDS.
    # shellcheck disable=SC2016 # expanded by the inner bash
    vars="$(
        env -i bash --noprofile --norc -c '
            before="$(compgen -v)"
            source "$1" >/dev/null || exit 1
            comm -13 <(sort <<<"$before") <(compgen -v | sort) | grep -vxE "before|_|PIPESTATUS|BASH_[A-Z_]+"
            exit 0
        ' _ "$conf"
    )" || die "$conf: failed to load"
    while IFS= read -r var; do
        [[ -z "$var" || " ${MANIFEST_FIELDS[*]} " == *" $var "* ]] || die "$conf: unknown field '$var'"
    done <<<"$vars"

    scope="$(manifest_field "$module" SCOPE)"
    case "$scope" in
        user) ;;
        system) die "$module: SCOPE=system is not supported yet" ;;
        *) die "$conf: SCOPE must be 'user' or 'system', got '${scope}'" ;;
    esac

    local deps
    deps="$(manifest_field "$module" DEPENDS)"
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        module_exists "$dep" || die "$module: depends on unknown module '$dep'"
    done <<<"$deps"
}

# module_resolve <module...>: print the modules plus their dependencies,
# dependencies first. Dies on an unknown module or a dependency cycle.
module_resolve() {
    local -A _state=()
    local -a _order=()
    local module

    _module_visit() {
        local m="$1" dep deps
        case "${_state[$m]:-}" in
            done) return 0 ;;
            visiting) die "dependency cycle through module '$m'" ;;
        esac
        module_exists "$m" || die "unknown module: $m"
        _state[$m]=visiting
        # Command substitution, not a process substitution: a die inside
        # manifest_field must stop this function too.
        deps="$(manifest_field "$m" DEPENDS)"
        while IFS= read -r dep; do
            if [[ -n "$dep" ]]; then _module_visit "$dep"; fi
        done <<<"$deps"
        _state[$m]="done"
        _order+=("$m")
    }

    for module in "$@"; do
        _module_visit "$module"
    done
    unset -f _module_visit
    ((${#_order[@]})) && printf '%s\n' "${_order[@]}"
    return 0
}

dotctl_host() { printf '%s\n' "${DOTCTL_HOST:-$(uname -n)}"; }

host_file() { printf '%s/hosts/%s.conf\n' "$DOTCTL_ROOT" "$(dotctl_host)"; }

# module_selected [module...]: the named modules, else the host's MODULES,
# else every module; dependencies included, dependencies first.
module_selected() {
    local file list
    if (($#)); then
        module_resolve "$@"
        return
    fi
    file="$(host_file)"
    if [[ -f "$file" ]]; then
        list="$(
            set +u
            # shellcheck disable=SC1090
            source "$file" || exit 1
            ((${#MODULES[@]})) || exit 2
            printf '%s\n' "${MODULES[@]}"
        )" || die "$file: failed to load, or MODULES is empty"
    else
        list="$(module_all)"
        [[ -n "$list" ]] || die "no modules in $DOTCTL_MODULES"
    fi
    local -a names
    mapfile -t names <<<"$list"
    module_resolve "${names[@]}"
}
