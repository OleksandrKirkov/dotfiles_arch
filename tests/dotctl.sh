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
export DOTCTL_HOST=sandbox

passed=0
failed=0

reset_sandbox() {
    rm -rf "$ROOT" "$DOTCTL_TARGET" "$DOTCTL_STATE" "$DOTCTL_HOOKS" "$SANDBOX"/{calls.log,missing,explicit,enabled,flatpaks,migrations.log}
    mkdir -p "$ROOT/modules" "$DOTCTL_TARGET"
    cp -r "$REPO/bin" "$REPO/lib" "$REPO/libexec" "$ROOT/"
    make_stubs
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

# field <module> <line>: append a manifest line, e.g. 'PACMAN=(tmux fzf)'
field() { printf '%s\n' "$2" >>"$ROOT/modules/$1/module.conf"; }

# Stubs for the package tools. Calls are appended to $SANDBOX/calls.log;
# queries answer from $SANDBOX/{missing,explicit,enabled,flatpaks}.
make_stubs() {
    local stubs="$SANDBOX/stubs"
    rm -rf "$stubs"
    mkdir -p "$stubs"
    cat >"$stubs/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    cat >"$stubs/pacman" <<STUB
#!/usr/bin/env bash
case "\$1" in
    -T) shift; rc=0
        for p in "\$@"; do grep -qxF -- "\$p" "$SANDBOX/missing" 2>/dev/null && { echo "\$p"; rc=127; }; done
        exit "\$rc" ;;
    -Qqe) cat "$SANDBOX/explicit" 2>/dev/null; exit 0 ;;
esac
echo "pacman \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/systemctl" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == is-enabled ]]; then
    grep -qxF -- "\$2" "$SANDBOX/enabled" 2>/dev/null && { echo enabled; exit 0; }
    echo disabled; exit 1
fi
echo "systemctl \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/flatpak" <<STUB
#!/usr/bin/env bash
[[ "\$1" == list ]] && { cat "$SANDBOX/flatpaks" 2>/dev/null; exit 0; }
echo "flatpak \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/yay" <<STUB
#!/usr/bin/env bash
echo "yay \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/npm" <<STUB
#!/usr/bin/env bash
echo "npm \$* userconfig=\${NPM_CONFIG_USERCONFIG:-}" >>"$SANDBOX/calls.log"
STUB
    chmod +x "$stubs"/*
}

# migration <module> <name> [body]: executable migration; by default it
# appends "<module>/<name>" to $SANDBOX/migrations.log
migration() {
    local body="${3:-echo \"\$DOTCTL_MIGRATION\" >>\"$SANDBOX/migrations.log\"}"
    mkdir -p "$ROOT/modules/$1/migrations"
    printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$body" >"$ROOT/modules/$1/migrations/$2"
    chmod +x "$ROOT/modules/$1/migrations/$2"
}

dotctl() { PATH="$SANDBOX/stubs:$PATH" "$ROOT/bin/dotctl" "$@"; }

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
    [[ "$(cat "$DOTCTL_STATE/backups/$id/MANIFEST")" == $'zsh\t.zshrc\tmove' ]] || fail "bad MANIFEST"
}

test_one_backup_per_run() {
    module zsh
    file zsh .zshrc "new"
    file zsh .zprofile "new"
    printf 'old\n' >"$DOTCTL_TARGET/.zshrc"
    printf 'old\n' >"$DOTCTL_TARGET/.zprofile"
    dotctl apply
    [[ "$(backup_count)" == 1 ]] || fail "$(backup_count) backups for one run"
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

test_dry_run_reports_folded_link_once() {
    module tmux
    file tmux .config/tmux/tmux.conf "conf"
    file tmux .config/tmux/scripts/a.sh "a"
    mkdir -p "$DOTCTL_TARGET/.config"
    ln -s "$ROOT/.config/tmux" "$DOTCTL_TARGET/.config/tmux"
    local out
    out="$(dotctl apply --dry-run 2>&1)"
    [[ "$(grep -c 'would remove stale link' <<<"$out")" == 1 ]] || fail "got: $out"
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

test_backup_restore_reads_two_column_manifest() {
    local dir="$DOTCTL_STATE/backups/20200101T000000"
    mkdir -p "$dir/files"
    printf 'old\n' >"$dir/files/.zshrc"
    printf 'zsh\t.zshrc\n' >"$dir/MANIFEST"
    module zsh
    dotctl backup restore 20200101T000000
    [[ "$(cat "$DOTCTL_TARGET/.zshrc")" == old ]] || fail "not restored"
}

test_backup_add_copies_and_restore_keeps_changed_file() {
    module zsh
    printf 'v1\n' >"$DOTCTL_TARGET/notes"
    local id
    id="$(DOTCTL_MODULE=zsh dotctl backup add "$DOTCTL_TARGET/notes" "$DOTCTL_TARGET/notes")"
    [[ "$(cat "$DOTCTL_TARGET/notes")" == v1 ]] || fail "original not left in place"
    [[ "$(cat "$DOTCTL_STATE/backups/$id/MANIFEST")" == $'zsh\tnotes\tcopy' ]] || fail "MANIFEST: $(cat "$DOTCTL_STATE/backups/$id/MANIFEST")"
    printf 'v2\n' >"$DOTCTL_TARGET/notes"
    dotctl backup restore "$id"
    [[ "$(cat "$DOTCTL_TARGET/notes")" == v1 ]] || fail "copy not restored"
    # the changed version went to a new backup instead of being overwritten
    grep -rqx v2 "$DOTCTL_STATE/backups" --include=notes || fail "changed version lost"
}

test_backup_add_rejects_paths_outside_target() {
    module zsh
    printf 'x\n' >"$SANDBOX/outside"
    if dotctl backup add "$SANDBOX/outside"; then fail "accepted a path outside the target"; fi
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

test_install_runs_package_tools_in_order() {
    module base
    module tmux base
    module dev
    field base 'PACMAN=(git stow)'
    field tmux 'PACMAN=(tmux git)'
    field tmux 'AUR=(tmux-fingers)'
    field dev 'FLATPAK=(com.example.App)'
    field dev 'NPM=(eslint_d)'
    field dev 'SERVICES=(docker.service)'
    field dev 'SERVICES_DISABLE=(nvidia-powerd.service)'
    printf 'prefix=/tmp/npm\n' >"$ROOT/modules/dev/home/.npmrc"
    hook dev install 50-log
    hook base install 50-log
    dotctl install
    local want
    want="pacman -Syu --needed --noconfirm git stow tmux
yay -S --needed --noconfirm tmux-fingers
flatpak install -y com.example.App
npm install -g eslint_d userconfig=$ROOT/modules/dev/home/.npmrc
systemctl enable docker.service
systemctl disable nvidia-powerd.service"
    [[ "$(cat "$SANDBOX/calls.log")" == "$want" ]] || fail "calls:" "$(cat "$SANDBOX/calls.log")"
    # module_all order is alphabetical, dependencies first: base, dev, tmux
    [[ "$(cat "$SANDBOX/hooks.log")" == $'base:install\ndev:install' ]] || fail "hooks: $(cat "$SANDBOX/hooks.log")"
}

test_install_dry_run_calls_nothing() {
    module base
    field base 'PACMAN=(git)'
    field base 'SERVICES=(x.service)'
    hook base install 50-log
    dotctl install --dry-run
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "called: $(cat "$SANDBOX/calls.log")"
    [[ ! -e "$SANDBOX/hooks.log" ]] || fail "hook ran"
}

test_install_without_packages_calls_nothing() {
    module zsh
    dotctl install
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "called: $(cat "$SANDBOX/calls.log")"
}

test_host_file_selects_modules() {
    module zsh
    module tmux zsh
    module waybar
    file zsh .zshrc "z"
    file tmux .tmux "t"
    file waybar .waybar "w"
    mkdir -p "$ROOT/hosts"
    printf 'MODULES=(tmux)\n' >"$ROOT/hosts/sandbox.conf"
    dotctl apply
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    links_to "$DOTCTL_TARGET/.tmux" tmux .tmux
    [[ ! -e "$DOTCTL_TARGET/.waybar" ]] || fail "waybar applied though not in host file"
    DOTCTL_HOST=other dotctl apply
    links_to "$DOTCTL_TARGET/.waybar" waybar .waybar
}

test_host_file_without_modules_fails() {
    module zsh
    mkdir -p "$ROOT/hosts"
    printf 'MODULES=()\n' >"$ROOT/hosts/sandbox.conf"
    local out
    if out="$(dotctl apply 2>&1)"; then fail "apply succeeded"; fi
    [[ "$out" == *"MODULES is empty"* ]] || fail "got: $out"
}

test_doctor_healthy() {
    module base
    file base .gitconfig "g"
    field base 'PACMAN=(git)'
    field base 'FLATPAK=(com.example.App)'
    field base 'SERVICES=(a.service)'
    field base 'SERVICES_DISABLE=(b.service)'
    printf 'a.service\n' >"$SANDBOX/enabled"
    printf 'com.example.App\n' >"$SANDBOX/flatpaks"
    printf 'git\nhtop\n' >"$SANDBOX/explicit"
    dotctl apply
    local out
    out="$(dotctl doctor --drift)" || fail "doctor failed:" "$out"
    [[ "$out" == *"1 explicitly installed package(s) no module declares"* ]] || fail "drift count:" "$out"
    [[ "$out" == *"    htop"* ]] || fail "drift list:" "$out"
    [[ "$out" == *healthy ]] || fail "$out"
}

test_doctor_reports_problems() {
    module base
    file base .gitconfig "g"
    field base 'PACMAN=(git)'
    field base 'FLATPAK=(com.example.App)'
    field base 'SERVICES=(a.service)'
    field base 'SERVICES_DISABLE=(b.service)'
    printf 'git\n' >"$SANDBOX/missing"
    printf 'b.service\n' >"$SANDBOX/enabled"
    local out
    if out="$(dotctl doctor)"; then fail "doctor passed"; fi
    for want in "base: ~/.gitconfig is not linked" "not installed: git" "flatpak not installed: com.example.App" \
        "a.service is disabled, want enabled" "b.service is enabled, want disabled" "base was never applied" \
        "6 problem(s)"; do
        [[ "$out" == *"$want"* ]] || fail "missing '$want' in:" "$out"
    done
}

test_doctor_drift_without_declared_packages() {
    module zsh
    printf 'git\nhtop\n' >"$SANDBOX/explicit"
    dotctl apply
    local out
    out="$(dotctl doctor)" || fail "doctor failed:" "$out"
    [[ "$out" == *"2 explicitly installed package(s)"* ]] || fail "$out"
}

test_migrations_run_once_in_order() {
    module zsh
    module tmux zsh
    migration tmux 0001-first
    migration zsh 0002-second
    migration zsh 0001-first
    dotctl migrate
    [[ "$(cat "$SANDBOX/migrations.log")" == $'zsh/0001-first\nzsh/0002-second\ntmux/0001-first' ]] \
        || fail "order: $(tr '\n' ' ' <"$SANDBOX/migrations.log")"
    dotctl migrate
    [[ "$(wc -l <"$SANDBOX/migrations.log")" == 3 ]] || fail "a migration ran twice"
    local out
    out="$(dotctl migrate --status)"
    [[ "$out" != *pending* ]] || fail "$out"
}

test_failed_migration_stops_and_is_not_recorded() {
    module zsh
    migration zsh 0001-ok
    migration zsh 0002-broken 'exit 4'
    migration zsh 0003-later
    if dotctl migrate; then fail "migrate succeeded"; fi
    [[ "$(cat "$SANDBOX/migrations.log")" == zsh/0001-ok ]] || fail "ran: $(cat "$SANDBOX/migrations.log")"
    local out
    out="$(dotctl migrate --status)"
    [[ "$out" == *"zsh/0002-broken"*pending* && "$out" == *"zsh/0003-later"*pending* ]] || fail "$out"
}

test_migrate_dry_run_changes_nothing() {
    module zsh
    migration zsh 0001-first
    dotctl migrate --dry-run
    [[ ! -e "$SANDBOX/migrations.log" ]] || fail "migration ran"
    [[ ! -e "$DOTCTL_STATE/migrations" ]] || fail "ledger written"
}

test_migration_name_is_checked() {
    module zsh
    migration zsh first
    local out
    if out="$(dotctl migrate 2>&1)"; then fail "accepted a bad name"; fi
    [[ "$out" == *"migrations are named NNNN-slug"* ]] || fail "$out"
}

test_migration_backups_share_the_run() {
    module zsh
    printf 'a\n' >"$DOTCTL_TARGET/a"
    printf 'b\n' >"$DOTCTL_TARGET/b"
    migration zsh 0001-a 'dotctl backup add "$DOTCTL_TARGET/a" >/dev/null; echo changed >"$DOTCTL_TARGET/a"'
    migration zsh 0002-b 'dotctl backup add "$DOTCTL_TARGET/b" >/dev/null; echo changed >"$DOTCTL_TARGET/b"'
    dotctl migrate
    [[ "$(backup_count)" == 1 ]] || fail "$(backup_count) backups"
    local id
    id="$(ls "$DOTCTL_STATE/backups")"
    [[ "$(cat "$DOTCTL_STATE/backups/$id/MANIFEST")" == $'zsh\ta\tcopy\nzsh\tb\tcopy' ]] \
        || fail "MANIFEST: $(cat "$DOTCTL_STATE/backups/$id/MANIFEST")"
}

test_doctor_reports_pending_migration() {
    module zsh
    migration zsh 0001-first
    dotctl apply
    local out
    if out="$(dotctl doctor)"; then fail "doctor passed"; fi
    [[ "$out" == *"pending migration: zsh/0001-first"* ]] || fail "$out"
    dotctl migrate
    out="$(dotctl doctor)" || fail "doctor failed after migrate:" "$out"
}

for t in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    run "$t"
done
printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
