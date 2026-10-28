# shellcheck shell=bash
# menu.sh: the one picker every dotctl menu uses, so all menus share the rofi
# config and the active theme. Menus source it:
#   source "$DOTCTL_ROOT/modules/rofi/lib/menu.sh"
#
# $DOTCTL_MENU_PICKER replaces rofi (tests use it); it gets the prompt as its
# last argument and the entries on stdin, and prints the chosen entry.

# menu_pick <prompt>: entries on stdin; prints the chosen one, fails when cancelled.
menu_pick() {
    local prompt="$1" choice
    if [[ -n "${DOTCTL_MENU_PICKER:-}" ]]; then
        choice="$($DOTCTL_MENU_PICKER "$prompt")" || return 1
    else
        choice="$(rofi -dmenu -i -no-custom -p "$prompt")" || return 1
    fi
    [[ -n "$choice" ]] || return 1
    printf '%s\n' "$choice"
}

# menu_confirm <question>: true only when "Yes" is picked.
menu_confirm() {
    [[ "$(printf 'No\nYes\n' | menu_pick "$1")" == Yes ]]
}

# menu_terminal <command...>: run it in a terminal that stays open until Enter.
menu_terminal() {
    # shellcheck disable=SC2016 # expanded by the inner bash
    "${TERMINAL:-ghostty}" -e bash -c '"$@"; status=$?; echo; read -rp "exit $status, press Enter to close"' _ "$@"
}
