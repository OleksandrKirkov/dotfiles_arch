# shellcheck shell=bash
# user.sh: the per-user file, ~/.config/dotctl/user.conf ($DOTCTL_USER_CONF).
#
# Plain bash assignments, data only, sourced in a clean subshell with HOME and
# USER set, so values may use $HOME:
#
#   GIT_NAME="Jane Doe"         # any KEY: becomes @KEY@ in *.tmpl files
#   GIT_EMAIL="jane@example.com"
#   REPO="$HOME/dotfiles_arch"  # the config repo, for a dotctl installed as a package
#
# Keys are [A-Z][A-Z0-9_]*, values one line. HOME and USER are always defined
# for templates and cannot be overridden here.

# _user_conf_dump: print a "KEY=value" line for each key the file defines.
_user_conf_dump() {
    local file="$DOTCTL_USER_CONF"
    [[ -f "$file" ]] || return 0
    # shellcheck disable=SC2016 # expanded by the inner bash
    env -i HOME="$HOME" USER="${USER:-$(id -un)}" bash --noprofile --norc -c '
        before="$(compgen -v)"
        source "$1" >/dev/null || exit 1
        while IFS= read -r name; do
            [[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
            case "$name" in HOME | USER | PIPESTATUS | BASH_*) continue ;; esac
            if [[ "${!name}" == *$'"'"'\n'"'"'* ]]; then
                echo "$name: values must be one line" >&2
                exit 1
            fi
            printf "%s=%s\n" "$name" "${!name}"
        done < <(comm -13 <(sort <<<"$before") <(compgen -v | sort))
    ' _ "$file" || die "$file: failed to load"
}

# user_conf_get <KEY>: print the value, or nothing when unset.
user_conf_get() {
    local dump entry
    dump="$(_user_conf_dump)"
    while IFS= read -r entry; do
        if [[ -n "$entry" && "${entry%%=*}" == "$1" ]]; then
            printf '%s\n' "${entry#*=}"
            return 0
        fi
    done <<<"$dump"
    return 0
}

# user_template_vars <assoc array name>: fill it with every template variable.
user_template_vars() {
    local -n _vars="$1"
    local dump entry
    dump="$(_user_conf_dump)"
    _vars=()
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        _vars[${entry%%=*}]="${entry#*=}"
    done <<<"$dump"
    _vars[HOME]="$DOTCTL_TARGET"
    _vars[USER]="${USER:-$(id -un)}"
}
