#!/usr/bin/env bash
# tests/dotctl.sh: sandbox tests for dotctl.
#
# Copies bin/, lib/ and libexec/ into a temporary root, builds fixture modules
# there at runtime, and links into a temporary target. The real $HOME, state
# and modules are never touched.
#
# Usage: tests/dotctl.sh

# shellcheck disable=SC2016 # fixture hooks expand their own variables
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

ROOT="$SANDBOX/repo"
export DOTCTL_TARGET="$SANDBOX/home"
export DOTCTL_STATE="$SANDBOX/state"
export DOTCTL_HOOKS="$SANDBOX/user-hooks"
export NO_COLOR=1

passed=0
failed=0

reset_sandbox() {
    rm -rf "$ROOT" "$DOTCTL_TARGET" "$DOTCTL_STATE" "$DOTCTL_HOOKS"
    mkdir -p "$ROOT/modules" "$DOTCTL_TARGET"
    cp -r "$REPO/bin" "$REPO/lib" "$REPO/libexec" "$ROOT/"
}

# module <name> [DEPENDS...]: create a fixture module.
module() {
    local name="$1"
    shift
    mkdir -p "$ROOT/modules/$name/home"
    {
        printf 'DESCRIPTION="fixture %s"\n' "$name"
        printf 'SCOPE=user\n'
        printf 'DEPENDS=(%s)\n' "$*"
    } >"$ROOT/modules/$name/module.conf"
}

# file <module> <rel> <content>
file() {
    mkdir -p "$(dirname "$ROOT/modules/$1/home/$2")"
    printf '%s\n' "$3" >"$ROOT/modules/$1/home/$2"
}

# hook <module> <event> <name>: hook that appends "<module>" to $SANDBOX/hooks.log
hook() {
    mkdir -p "$ROOT/modules/$1/hooks/$2.d"
    printf '#!/usr/bin/env bash\necho "$DOTCTL_MODULE:$DOTCTL_EVENT" >>"%s/hooks.log"\n' "$SANDBOX" \
        >"$ROOT/modules/$1/hooks/$2.d/$3"
    chmod +x "$ROOT/modules/$1/hooks/$2.d/$3"
}

dotctl() { "$ROOT/bin/dotctl" "$@"; }

# fail <message>: record a failed assertion; the test keeps running so every
# broken assertion is reported.
fail() {
    printf '    %s\n' "$@" >&2
    : >"$SANDBOX/failed"
}

# links_to <path> <module> <rel>: path is a link resolving to the module file
links_to() {
    [[ -L "$1" ]] || fail "$1 is not a symlink"
    [[ "$(readlink -f "$1")" == "$ROOT/modules/$2/home/$3" ]] \
        || fail "$1 -> $(readlink -f "$1"), want $ROOT/modules/$2/home/$3"
}

backup_count() { find "$DOTCTL_STATE/backups" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l; }

# run <test>: run one test in a background subshell. Unlike `if test`, that
# keeps errexit active inside it, so an unexpected command failure fails the test.
run() {
    local name="$1" status=0
    reset_sandbox
    rm -f "$SANDBOX/failed" "$SANDBOX/hooks.log"
    (set -e; "$name") >"$SANDBOX/out" 2>&1 &
    wait $! || status=$?
    if ((status == 0)) && [[ ! -e "$SANDBOX/failed" ]]; then
        passed=$((passed + 1))
        printf 'ok   %s\n' "$name"
    else
        failed=$((failed + 1))
        printf 'FAIL %s (exit %d)\n' "$name" "$status"
        sed 's/^/    /' "$SANDBOX/out"
    fi
}

test_links_into_empty_target() {
    module zsh
    file zsh .zshrc "zsh"
    file zsh .config/zsh/aliases "aliases"
    dotctl apply
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    links_to "$DOTCTL_TARGET/.config/zsh/aliases" zsh .config/zsh/aliases
    # --no-folding: the directory is real, so other modules can share it
    [[ -d "$DOTCTL_TARGET/.config/zsh" && ! -L "$DOTCTL_TARGET/.config/zsh" ]] || fail ".config/zsh was folded"
    [[ "$(backup_count)" == 0 ]] || fail "unexpected backup"
}

test_backs_up_existing_file() {
    module zsh
    file zsh .zshrc "new"
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    dotctl apply
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    local id
    id="$(ls "$DOTCTL_STATE/backups")"
    [[ "$(cat "$DOTCTL_STATE/backups/$id/files/.zshrc")" == old ]] || fail "backup content lost"
    [[ "$(cat "$DOTCTL_STATE/backups/$id/MANIFEST")" == $'zsh\t.zshrc' ]] || fail "bad MANIFEST"
}

test_backs_up_foreign_symlink() {
    module zsh
    file zsh .zshrc "new"
    printf 'elsewhere\n' >"$SANDBOX/elsewhere"
    ln -s "$SANDBOX/elsewhere" "$DOTCTL_TARGET/.zshrc"
    dotctl apply
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    [[ "$(backup_count)" == 1 ]] || fail "foreign symlink not backed up"
    [[ "$(cat "$SANDBOX/elsewhere")" == elsewhere ]] || fail "link target was modified"
}

test_replaces_stale_repo_links_without_backup() {
    module tmux
    file tmux .config/tmux/tmux.conf "conf"
    file tmux .zshrc "zsh"
    # what the old repo-root `stow .` left after the files moved into modules/
    mkdir -p "$DOTCTL_TARGET/.config"
    ln -s "$ROOT/.config/tmux" "$DOTCTL_TARGET/.config/tmux"
    ln -s "$ROOT/.zshrc" "$DOTCTL_TARGET/.zshrc"
    dotctl apply
    links_to "$DOTCTL_TARGET/.config/tmux/tmux.conf" tmux .config/tmux/tmux.conf
    links_to "$DOTCTL_TARGET/.zshrc" tmux .zshrc
    [[ "$(backup_count)" == 0 ]] || fail "repo links were backed up"
}

test_refuses_live_folded_repo_link() {
    module tmux
    file tmux .config/tmux/tmux.conf "conf"
    mkdir -p "$ROOT/.config/tmux" "$DOTCTL_TARGET/.config"
    printf 'not moved yet\n' >"$ROOT/.config/tmux/other"
    ln -s "$ROOT/.config/tmux" "$DOTCTL_TARGET/.config/tmux"
    if dotctl apply; then fail "apply succeeded"; fi
    [[ -L "$DOTCTL_TARGET/.config/tmux" ]] || fail "live folded link was removed"
}

test_reapply_is_idempotent() {
    module zsh
    file zsh .zshrc "zsh"
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    dotctl apply
    dotctl apply
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    [[ "$(backup_count)" == 1 ]] || fail "second apply took another backup"
}

test_dry_run_changes_nothing() {
    module zsh
    file zsh .zshrc "zsh"
    hook zsh link 50-log
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    dotctl apply --dry-run
    [[ ! -L "$DOTCTL_TARGET/.zshrc" && "$(cat "$DOTCTL_TARGET/.zshrc")" == old ]] || fail "target changed"
    [[ ! -e "$DOTCTL_STATE" ]] || fail "state written"
    [[ ! -e "$SANDBOX/hooks.log" ]] || fail "hook ran"
}

test_dependencies_apply_first() {
    module tmux zsh
    module zsh
    hook tmux link 50-log
    hook zsh link 50-log
    mkdir -p "$DOTCTL_HOOKS/link.d"
    printf '#!/usr/bin/env bash\necho "user:$DOTCTL_EVENT" >>"%s/hooks.log"\n' "$SANDBOX" >"$DOTCTL_HOOKS/link.d/10-user"
    chmod +x "$DOTCTL_HOOKS/link.d/10-user"
    dotctl apply tmux
    [[ "$(cat "$SANDBOX/hooks.log")" == $'zsh:link\nuser:link\ntmux:link\nuser:link' ]] \
        || fail "hook order: $(tr '\n' ' ' <"$SANDBOX/hooks.log")"
}

test_hook_name_filter() {
    module zsh
    hook zsh link 50-log
    hook zsh link 60-log.bak
    dotctl apply
    [[ "$(cat "$SANDBOX/hooks.log")" == "zsh:link" ]] || fail "a .bak hook ran"
}

test_failed_hook_fails_apply_and_skips_state() {
    module zsh
    mkdir -p "$ROOT/modules/zsh/hooks/link.d"
    printf '#!/usr/bin/env bash\nexit 3\n' >"$ROOT/modules/zsh/hooks/link.d/50-fail"
    chmod +x "$ROOT/modules/zsh/hooks/link.d/50-fail"
    if dotctl apply; then fail "apply succeeded"; fi
    [[ -z "$(dotctl list | awk '$1 == "zsh" && $3 != "-"')" ]] || fail "zsh marked applied"
}

test_dependency_cycle() {
    module a b
    module b a
    local out
    if out="$(dotctl apply a 2>&1)"; then fail "apply succeeded"; fi
    [[ "$out" == *"dependency cycle"* ]] || fail "got: $out"
}

test_unknown_module_and_field() {
    module zsh
    local out
    if out="$(dotctl apply nope 2>&1)"; then fail "unknown module accepted"; fi
    [[ "$out" == *"unknown module: nope"* ]] || fail "got: $out"
    printf 'PACKAGES=(x)\n' >>"$ROOT/modules/zsh/module.conf"
    if out="$(dotctl apply zsh 2>&1)"; then fail "unknown field accepted"; fi
    [[ "$out" == *"unknown field 'PACKAGES'"* ]] || fail "got: $out"
}

test_backup_restore_round_trip() {
    module zsh
    file zsh .zshrc "new"
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    dotctl apply
    local id
    id="$(dotctl backup list | awk 'NR == 2 { print $1 }')"
    dotctl backup restore "$id"
    [[ ! -L "$DOTCTL_TARGET/.zshrc" && "$(cat "$DOTCTL_TARGET/.zshrc")" == old ]] || fail "not restored"
    [[ -d "$DOTCTL_STATE/backups/$id.restored" ]] || fail "backup not marked restored"
}

test_backup_restore_refuses_foreign_file() {
    module zsh
    file zsh .zshrc "new"
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    dotctl apply
    local id
    id="$(dotctl backup list | awk 'NR == 2 { print $1 }')"
    rm "$DOTCTL_TARGET/.zshrc"
    printf 'edited by hand\n' >"$DOTCTL_TARGET/.zshrc"
    if dotctl backup restore "$id"; then fail "restore succeeded"; fi
    [[ "$(cat "$DOTCTL_TARGET/.zshrc")" == "edited by hand" ]] || fail "foreign file overwritten"
}

for t in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    run "$t"
done
printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
