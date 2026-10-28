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
export DOTCTL_MENU_PICKER="$SANDBOX/stubs/picker" TERMINAL=terminal
export DOTCTL_BUS="$SANDBOX/run/bus.sock"
export DOTCTL_BUS_STATE="$SANDBOX/bus.json"
unset XDG_STATE_HOME

passed=0
failed=0

reset_sandbox() {
    rm -rf "$ROOT" "$DOTCTL_TARGET" "$DOTCTL_STATE" "$DOTCTL_HOOKS" "$SANDBOX"/{calls.log,missing,explicit,enabled,flatpaks,migrations.log,git,marker,installed,required-by,nm,run,bus.json,watch.out,aur-updates,repo-updates,picks,menu.log}
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
    -Q) grep -qxF -- "\$2" "$SANDBOX/installed" 2>/dev/null && { echo "\$2 1.0"; exit 0; }; exit 1 ;;
    -Qi) echo "Name            : \$2"
         echo "Required By     : \$(cat "$SANDBOX/required-by" 2>/dev/null || echo None)"; exit 0 ;;
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
[[ "\$1" == -Qua ]] && { cat "$SANDBOX/aur-updates" 2>/dev/null; exit 1; }
echo "yay \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/notify-send" <<STUB
#!/usr/bin/env bash
echo "notify-send \$*" >>"$SANDBOX/calls.log"
STUB
    cat >"$stubs/pkill" <<STUB
#!/usr/bin/env bash
echo "pkill \$*" >>"$SANDBOX/calls.log"
exit 1
STUB
    # picker: logs the prompt and entries, prints the first entry containing the
    # next line of $SANDBOX/picks (consumed); no picks left = cancelled
    cat >"$stubs/picker" <<STUB
#!/usr/bin/env bash
entries="\$(cat)"
printf 'prompt: %s\n%s\n' "\$1" "\$entries" >>"$SANDBOX/menu.log"
pick="\$(head -n1 "$SANDBOX/picks" 2>/dev/null)"
[[ -n "\$pick" ]] || exit 1
sed -i 1d "$SANDBOX/picks"
grep -F -m1 -- "\$pick" <<<"\$entries"
STUB
    local tool
    for tool in loginctl bluetoothctl rfkill terminal; do
        cat >"$stubs/$tool" <<STUB
#!/usr/bin/env bash
[[ "$tool \$1" == "bluetoothctl show" ]] && { echo "Powered: no"; exit 0; }
echo "$tool \$*" >>"$SANDBOX/calls.log"
STUB
    done
    cat >"$stubs/checkupdates" <<STUB
#!/usr/bin/env bash
[[ -s "$SANDBOX/repo-updates" ]] || exit 2
cat "$SANDBOX/repo-updates"
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

# start_daemon: run the dotctld built for this test run on $DOTCTL_BUS.
start_daemon() {
    "$SANDBOX/dotctld" -alerts=false >>"$SANDBOX/daemon.log" 2>&1 &
    echo $! >"$SANDBOX/daemon.pid"
    for _ in $(seq 50); do
        [[ -S "$DOTCTL_BUS" ]] && return 0
        sleep 0.1
    done
    fail "dotctld did not start: $(cat "$SANDBOX/daemon.log")"
}

stop_daemon() {
    [[ -f "$SANDBOX/daemon.pid" ]] || return 0
    kill "$(cat "$SANDBOX/daemon.pid")" 2>/dev/null || true
    wait "$(cat "$SANDBOX/daemon.pid")" 2>/dev/null || true
    rm -f "$SANDBOX/daemon.pid"
}

# wait_for_lines <file> <count>: wait up to 5 s for the file to hold <count> lines.
wait_for_lines() {
    for _ in $(seq 50); do
        [[ -f "$1" && "$(wc -l <"$1")" -ge "$2" ]] && return 0
        sleep 0.1
    done
    fail "$1 has $(wc -l <"$1" 2>/dev/null || echo 0) lines, want $2"
}

# real_module <module>: copy a whole module from this repo into the sandbox
# (replacing a fixture of the same name).
real_module() {
    rm -rf "$ROOT/modules/$1"
    cp -r "$REPO/modules/$1" "$ROOT/modules/$1"
}

# real_migration <module> <name>: copy a migration from this repo into the sandbox.
real_migration() {
    mkdir -p "$ROOT/modules/$1/migrations"
    cp "$REPO/modules/$1/migrations/$2" "$ROOT/modules/$1/migrations/$2"
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
    stop_daemon
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

test_apply_removes_links_of_dropped_files() {
    module waybar
    file waybar .config/waybar/config "c"
    file waybar .local/bin/old.sh "old"
    file waybar .local/bin/kept.sh "kept"
    dotctl apply
    rm -r "$ROOT/modules/waybar/home/.local"   # the module stops shipping its scripts
    printf 'mine\n' >"$SANDBOX/mine"
    ln -sfn "$SANDBOX/mine" "$DOTCTL_TARGET/.local/bin/kept.sh"   # the user repointed this one
    dotctl apply --dry-run
    [[ -L "$DOTCTL_TARGET/.local/bin/old.sh" ]] || fail "dry run removed a link"
    dotctl apply
    [[ ! -L "$DOTCTL_TARGET/.local/bin/old.sh" ]] || fail "dangling link of a dropped file left"
    [[ "$(readlink "$DOTCTL_TARGET/.local/bin/kept.sh")" == "$SANDBOX/mine" ]] || fail "user's link touched"
    links_to "$DOTCTL_TARGET/.config/waybar/config" waybar .config/waybar/config
}

test_apply_prunes_a_module_that_dropped_home() {
    module tablet
    file tablet .config/otd/settings.json "s"
    dotctl apply
    rm -r "$ROOT/modules/tablet/home"
    dotctl apply
    [[ ! -L "$DOTCTL_TARGET/.config/otd/settings.json" ]] || fail "dangling link left"
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

# git_fixture: make $ROOT a git repo with an origin at $SANDBOX/git/origin.git
# and a second clone at $SANDBOX/git/work for pushing "upstream" changes.
# Git config is sandboxed; the real ~/.gitconfig is never read.
git_fixture() {
    export GIT_CONFIG_GLOBAL="$SANDBOX/git/config" GIT_CONFIG_NOSYSTEM=1
    mkdir -p "$SANDBOX/git"
    git config --global user.name test
    git config --global user.email test@example.invalid
    git -C "$ROOT" init -q -b main
    git -C "$ROOT" add -A
    git -C "$ROOT" commit -qm init
    git clone -q --bare "$ROOT" "$SANDBOX/git/origin.git"
    git -C "$ROOT" remote add origin "$SANDBOX/git/origin.git"
    git -C "$ROOT" fetch -q origin
    git -C "$ROOT" branch -q --set-upstream-to=origin/main
    git clone -q "$SANDBOX/git/origin.git" "$SANDBOX/git/work"
}

# push_migration <module> <name>: commit a logging migration upstream.
push_migration() {
    local work="$SANDBOX/git/work"
    mkdir -p "$work/modules/$1/migrations"
    printf '#!/usr/bin/env bash\necho "$DOTCTL_MIGRATION" >>"%s/migrations.log"\n' "$SANDBOX" >"$work/modules/$1/migrations/$2"
    chmod +x "$work/modules/$1/migrations/$2"
    git -C "$work" add -A
    git -C "$work" commit -qm "add $2"
    git -C "$work" push -q origin main
}

test_update_pulls_then_installs_applies_migrates() {
    module zsh
    file zsh .zshrc "z"
    field zsh 'PACMAN=(zsh)'
    hook zsh update 50-log
    git_fixture
    push_migration zsh 0001-pulled
    dotctl update
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$SANDBOX/git/work" rev-parse HEAD)" ]] || fail "not pulled"
    [[ "$(cat "$SANDBOX/calls.log")" == "pacman -Syu --needed --noconfirm zsh" ]] || fail "calls: $(cat "$SANDBOX/calls.log")"
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    [[ "$(cat "$SANDBOX/migrations.log")" == zsh/0001-pulled ]] || fail "pulled migration did not run"
    [[ "$(cat "$SANDBOX/hooks.log")" == zsh:update ]] || fail "hooks: $(cat "$SANDBOX/hooks.log")"
}

test_update_continues_with_pulled_code() {
    module zsh
    git_fixture
    local work="$SANDBOX/git/work"
    sed -i "s|^log \"update complete\"$|echo pulled-code >>\"$SANDBOX/marker\"; log \"update complete\"|" \
        "$work/libexec/dotctl/dotctl-update"
    grep -q pulled-code "$work/libexec/dotctl/dotctl-update" || fail "fixture edit did not apply"
    git -C "$work" commit -qam "change update"
    git -C "$work" push -q origin main
    dotctl update --no-packages
    [[ "$(cat "$SANDBOX/marker" 2>/dev/null)" == pulled-code ]] || fail "update ran the old code"
}

test_update_no_pull_no_packages() {
    module zsh
    file zsh .zshrc "z"
    field zsh 'PACMAN=(zsh)'
    migration zsh 0001-local
    dotctl update --no-pull --no-packages
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "packages installed: $(cat "$SANDBOX/calls.log")"
    links_to "$DOTCTL_TARGET/.zshrc" zsh .zshrc
    [[ "$(cat "$SANDBOX/migrations.log")" == zsh/0001-local ]] || fail "migration did not run"
}

test_update_dry_run_lists_incoming_and_changes_nothing() {
    module zsh
    file zsh .zshrc "z"
    git_fixture
    push_migration zsh 0001-pulled
    local head out
    head="$(git -C "$ROOT" rev-parse HEAD)"
    out="$(dotctl update --dry-run 2>&1)" || fail "dry run failed:" "$out"
    [[ "$out" == *"add 0001-pulled"* ]] || fail "incoming commit not listed:" "$out"
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$head" ]] || fail "repo moved"
    [[ ! -L "$DOTCTL_TARGET/.zshrc" && ! -e "$SANDBOX/migrations.log" && ! -e "$SANDBOX/calls.log" ]] || fail "something changed"
}

test_update_without_upstream_fails() {
    module zsh
    export GIT_CONFIG_GLOBAL="$SANDBOX/git/config" GIT_CONFIG_NOSYSTEM=1
    git -C "$ROOT" init -q -b main
    local out
    if out="$(dotctl update 2>&1)"; then fail "update succeeded"; fi
    [[ "$out" == *"has no upstream"* ]] || fail "$out"
}

test_update_stops_on_failed_migration() {
    module zsh
    migration zsh 0001-broken 'exit 1'
    hook zsh update 50-log
    if dotctl update --no-pull --no-packages; then fail "update succeeded"; fi
    [[ ! -e "$SANDBOX/hooks.log" ]] || fail "update hooks ran after a failed migration"
}

test_theme_migration_links_dunst_theme() {
    module theme
    real_migration theme 0001-link-dunst-theme
    mkdir -p "$DOTCTL_TARGET/.local/state/theme/current"
    printf 'x\n' >"$DOTCTL_TARGET/.local/state/theme/current/dunst.conf"
    dotctl migrate
    [[ "$(readlink "$DOTCTL_TARGET/.config/dunst/dunstrc.d/90-theme.conf")" == "$DOTCTL_TARGET/.local/state/theme/current/dunst.conf" ]] \
        || fail "link not created"
}

test_theme_migration_leaves_existing_link_and_no_theme() {
    module theme
    real_migration theme 0001-link-dunst-theme
    dotctl migrate
    [[ ! -e "$DOTCTL_TARGET/.config/dunst" ]] || fail "created dunst config without a theme"
    rm "$DOTCTL_STATE/migrations"
    mkdir -p "$DOTCTL_TARGET/.local/state/theme/current" "$DOTCTL_TARGET/.config/dunst/dunstrc.d"
    printf 'x\n' >"$DOTCTL_TARGET/.local/state/theme/current/dunst.conf"
    ln -s /elsewhere "$DOTCTL_TARGET/.config/dunst/dunstrc.d/90-theme.conf"
    dotctl migrate
    [[ "$(readlink "$DOTCTL_TARGET/.config/dunst/dunstrc.d/90-theme.conf")" == /elsewhere ]] || fail "existing link replaced"
}

test_iwd_migration_noop_without_iwd() {
    module network
    real_migration network 0001-drop-iwd
    dotctl migrate
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "called: $(cat "$SANDBOX/calls.log")"
}

test_iwd_migration_removes_unused_iwd() {
    module network
    real_migration network 0001-drop-iwd
    printf 'iwd\n' >"$SANDBOX/installed"
    mkdir -p "$SANDBOX/nm/conf.d"
    DOTCTL_NM_CONF="$SANDBOX/nm" dotctl migrate
    [[ "$(cat "$SANDBOX/calls.log")" == $'systemctl disable --now iwd.service\npacman -Rns --noconfirm iwd' ]] \
        || fail "calls: $(cat "$SANDBOX/calls.log")"
}

test_iwd_migration_refuses_when_nm_uses_iwd() {
    module network
    real_migration network 0001-drop-iwd
    printf 'iwd\n' >"$SANDBOX/installed"
    mkdir -p "$SANDBOX/nm/conf.d"
    printf '[device]\nwifi.backend=iwd\n' >"$SANDBOX/nm/conf.d/wifi_backend.conf"
    local out
    if out="$(DOTCTL_NM_CONF="$SANDBOX/nm" dotctl migrate 2>&1)"; then fail "migrate succeeded"; fi
    [[ "$out" == *"NetworkManager still uses iwd"* ]] || fail "$out"
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "changed the system: $(cat "$SANDBOX/calls.log")"
}

test_iwd_migration_refuses_when_required() {
    module network
    real_migration network 0001-drop-iwd
    printf 'iwd\n' >"$SANDBOX/installed"
    printf 'some-package\n' >"$SANDBOX/required-by"
    mkdir -p "$SANDBOX/nm"
    local out
    if out="$(DOTCTL_NM_CONF="$SANDBOX/nm" dotctl migrate 2>&1)"; then fail "migrate succeeded"; fi
    [[ "$out" == *"still required by: some-package"* ]] || fail "$out"
    [[ ! -e "$SANDBOX/calls.log" ]] || fail "changed the system"
}

test_bus_publish_get_topics() {
    start_daemon
    dotctl bus ping
    dotctl bus publish theme '{"name":"tokyonight"}'
    printf '{"packages":3}' | dotctl bus publish updates -
    [[ "$(dotctl bus get --data theme)" == '{"name":"tokyonight"}' ]] || fail "get --data: $(dotctl bus get --data theme)"
    [[ "$(dotctl bus get theme | jq -r '.topic + " " + (.seq | tostring)')" == "theme 1" ]] || fail "get: $(dotctl bus get theme)"
    local out
    out="$(dotctl bus topics)"
    [[ "$out" == *theme*updates* ]] || fail "topics: $out"
}

test_bus_exit_codes() {
    local status=0
    dotctl bus get theme 2>"$SANDBOX/err" || status=$?
    [[ "$status" == 3 && "$(cat "$SANDBOX/err")" == *"dotctld is not running"* ]] || fail "not running: $status $(cat "$SANDBOX/err")"
    start_daemon
    status=0
    dotctl bus get theme 2>"$SANDBOX/err" || status=$?
    [[ "$status" == 4 && "$(cat "$SANDBOX/err")" == *"nothing published on theme"* ]] || fail "missing: $status $(cat "$SANDBOX/err")"
    status=0
    dotctl bus publish theme '{bad' 2>"$SANDBOX/err" || status=$?
    [[ "$status" == 1 && "$(cat "$SANDBOX/err")" == *"data must be valid JSON"* ]] || fail "bad json: $status $(cat "$SANDBOX/err")"
    status=0
    dotctl bus publish '../x' 1 2>"$SANDBOX/err" || status=$?
    [[ "$status" == 1 && "$(cat "$SANDBOX/err")" == *"invalid topic"* ]] || fail "bad topic: $status $(cat "$SANDBOX/err")"
}

test_bus_watch_streams_current_then_new() {
    start_daemon
    dotctl bus publish theme '"a"'
    dotctl bus watch --data theme updates >"$SANDBOX/watch.out" &
    local watcher=$!
    wait_for_lines "$SANDBOX/watch.out" 1
    dotctl bus publish other '0'
    dotctl bus publish updates '{"packages":1}'
    wait_for_lines "$SANDBOX/watch.out" 2
    [[ "$(cat "$SANDBOX/watch.out")" == $'"a"\n{"packages":1}' ]] || fail "watch: $(cat "$SANDBOX/watch.out")"
    stop_daemon # the stream ends with the daemon
    for _ in $(seq 50); do kill -0 "$watcher" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$watcher" 2>/dev/null; then kill "$watcher"; fail "watch kept running after dotctld stopped"; fi
}

test_bus_state_survives_restart() {
    start_daemon
    dotctl bus publish theme '"a"'
    stop_daemon
    start_daemon
    [[ "$(dotctl bus get --data theme)" == '"a"' ]] || fail "theme lost on restart"
}

test_updates_counts() {
    module base
    module dev
    real_module bus
    printf 'linux 1 -> 2\nmesa 1 -> 2\n' >"$SANDBOX/repo-updates"
    printf 'yay-bin 1 -> 2\n' >"$SANDBOX/aur-updates"
    local out
    out="$(dotctl updates)"
    [[ "$(jq -c 'del(.checked)' <<<"$out")" == '{"repo":null,"packages":2,"aur":1}' ]] || fail "$out"
    rm "$SANDBOX/repo-updates" "$SANDBOX/aur-updates"
    out="$(dotctl updates)"
    [[ "$(jq -c 'del(.checked)' <<<"$out")" == '{"repo":null,"packages":0,"aur":0}' ]] || fail "$out"
}

test_updates_counts_repo_commits() {
    module base
    module dev
    real_module bus
    git_fixture
    push_migration base 0001-x
    local out
    out="$(dotctl updates)"
    [[ "$(jq '.repo' <<<"$out")" == 1 ]] || fail "$out"
}

test_updates_publish() {
    module base
    module dev
    real_module bus
    local status=0
    dotctl updates --publish >/dev/null 2>&1 || status=$?
    [[ "$status" == 3 ]] || fail "without dotctld: exit $status, want 3"
    start_daemon
    printf 'linux 1 -> 2\n' >"$SANDBOX/repo-updates"
    dotctl updates --publish >/dev/null
    [[ "$(dotctl bus get --data updates | jq '.packages')" == 1 ]] || fail "$(dotctl bus get updates)"
}

test_bus_module_builds_and_enables_dotctld() {
    module base
    module dev
    real_module bus
    cp -r "$REPO/daemon" "$ROOT/daemon"
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    dotctl install bus
    [[ -x "$DOTCTL_TARGET/.local/bin/dotctld" ]] || fail "dotctld not built"
    grep -qx 'systemctl --user try-restart dotctld.service' "$SANDBOX/calls.log" || fail "no restart after a new build"
    : >"$SANDBOX/calls.log"
    local out
    out="$(dotctl install bus 2>&1)"
    [[ "$out" == *"dotctld is up to date"* ]] || fail "rebuild not detected as unchanged:" "$out"
    ! grep -q try-restart "$SANDBOX/calls.log" || fail "restarted an unchanged dotctld"
    : >"$SANDBOX/calls.log"
    dotctl apply bus
    links_to "$DOTCTL_TARGET/.config/systemd/user/dotctld.service" bus .config/systemd/user/dotctld.service
    [[ "$(cat "$SANDBOX/calls.log")" == $'systemctl --user daemon-reload\nsystemctl --user enable --now dotctld.service dotctl-updates.timer' ]] \
        || fail "calls: $(cat "$SANDBOX/calls.log")"
}

test_notify_alerts_shows_each_new_alert_once() {
    module bus
    real_module dunst
    start_daemon
    local low='{"id":"battery.low","urgency":"critical","icon":"battery-caution","summary":"Low battery","body":"9% left."}'
    local ram='{"id":"memory.high","urgency":"critical","icon":"dialog-warning","summary":"High RAM usage","body":"30 GB."}'
    dotctl bus publish alerts "{\"active\":[$low]}"
    dotctl notify-alerts &
    local notifier=$!
    wait_for_lines "$SANDBOX/calls.log" 1
    dotctl bus publish alerts "{\"active\":[$low,$ram]}"   # only the RAM alert is new
    wait_for_lines "$SANDBOX/calls.log" 2
    dotctl bus publish alerts '{"active":[]}'                # both clear
    dotctl bus publish alerts "{\"active\":[$low]}"         # battery crosses again
    wait_for_lines "$SANDBOX/calls.log" 3
    stop_daemon
    for _ in $(seq 50); do kill -0 "$notifier" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$notifier" 2>/dev/null; then kill "$notifier"; fail "notifier kept running after dotctld stopped"; fi
    local want
    want="notify-send -u critical -a dotctl -i battery-caution Low battery 9% left.
notify-send -u critical -a dotctl -i dialog-warning High RAM usage 30 GB.
notify-send -u critical -a dotctl -i battery-caution Low battery 9% left."
    [[ "$(cat "$SANDBOX/calls.log")" == "$want" ]] || fail "calls:" "$(cat "$SANDBOX/calls.log")"
}

test_retire_alert_script_migration() {
    module system-tools
    real_migration system-tools 0001-retire-alert-script
    mkdir -p "$DOTCTL_TARGET/.local/bin"
    ln -s "$ROOT/.local/bin/system-alerts" "$DOTCTL_TARGET/.local/bin/system-alerts"   # dangling, ours
    ln -s /elsewhere/gone "$DOTCTL_TARGET/.local/bin/other"                            # dangling, not ours
    dotctl migrate
    [[ ! -L "$DOTCTL_TARGET/.local/bin/system-alerts" ]] || fail "dangling repo link left"
    [[ -L "$DOTCTL_TARGET/.local/bin/other" ]] || fail "removed a link that is not ours"
    [[ "$(cat "$SANDBOX/calls.log")" == "pkill -f -- /system-alerts\$" ]] || fail "calls: $(cat "$SANDBOX/calls.log")"
}

# picks <entry>...: the menu choices the picker stub makes, in order
picks() { printf '%s\n' "$@" >"$SANDBOX/picks"; }

test_menu_lists_and_dispatches() {
    real_module rofi
    local out
    out="$(dotctl menu --help)"
    [[ "$out" == *power* && "$out" == *bluetooth* && "$out" == *updates* ]] || fail "$out"
    if dotctl menu nope 2>/dev/null; then fail "unknown menu accepted"; fi
    picks power Lock
    dotctl menu
    [[ "$(cat "$SANDBOX/calls.log")" == "loginctl lock-session" ]] || fail "calls: $(cat "$SANDBOX/calls.log")"
}

test_power_menu_confirms_destructive_entries() {
    real_module rofi
    picks Suspend
    dotctl menu power
    picks Reboot No
    dotctl menu power
    picks "Shut down" Yes
    dotctl menu power
    picks "Log out" Yes
    XDG_SESSION_ID=7 dotctl menu power
    picks Reboot   # cancelled at the confirmation
    dotctl menu power
    [[ "$(cat "$SANDBOX/calls.log")" == $'systemctl suspend\nsystemctl poweroff\nloginctl terminate-session 7' ]] \
        || fail "calls: $(cat "$SANDBOX/calls.log")"
    dotctl menu power   # cancelled outright: exit 0, nothing run
}

test_updates_menu() {
    module base
    module dev
    real_module bus
    real_module rofi
    start_daemon
    dotctl bus publish updates '{"repo":0,"packages":3,"aur":1,"checked":"x"}'
    picks "Update now"
    dotctl menu updates
    grep -q 'Update now (pacman 3 · AUR 1 · repo 0)' "$SANDBOX/menu.log" || fail "menu: $(cat "$SANDBOX/menu.log")"
    grep -q "^terminal -e bash -c .* $ROOT/bin/dotctl update\$" "$SANDBOX/calls.log" || fail "calls: $(cat "$SANDBOX/calls.log")"
    printf 'linux 1 -> 2\n' >"$SANDBOX/repo-updates"
    picks "Check again"
    dotctl menu updates
    [[ "$(dotctl bus get --data updates | jq .packages)" == 1 ]] || fail "not rechecked: $(dotctl bus get updates)"
}

test_bluetooth_menu_powers_on() {
    real_module rofi
    picks "Power: off"
    dotctl menu bluetooth
    grep -qx 'bluetoothctl power on' "$SANDBOX/calls.log" || fail "calls: $(cat "$SANDBOX/calls.log")"
}

test_waybar_updates_format() {
    local jqf="$REPO/modules/waybar/home/.config/waybar/bus/updates.jq"
    start_daemon
    dotctl bus publish updates '{"repo":1,"packages":2,"aur":null,"checked":"t"}'
    dotctl bus watch --format "$jqf" updates >"$SANDBOX/watch.out" &
    local watcher=$!
    wait_for_lines "$SANDBOX/watch.out" 1
    dotctl bus publish updates '{"repo":0,"packages":0,"aur":0,"checked":"t2"}'
    wait_for_lines "$SANDBOX/watch.out" 2
    stop_daemon
    wait "$watcher" 2>/dev/null || true
    [[ "$(sed -n 1p "$SANDBOX/watch.out" | jq -c '{text, class}')" == '{"text":"󰚰\n3","class":"pending"}' ]] \
        || fail "pending: $(sed -n 1p "$SANDBOX/watch.out")"
    [[ "$(sed -n 1p "$SANDBOX/watch.out" | jq -r .tooltip)" == *"AUR: ?"* ]] || fail "unknown count not shown as ?"
    [[ "$(sed -n 2p "$SANDBOX/watch.out" | jq -c '{text, class}')" == '{"text":"","class":"none"}' ]] \
        || fail "none: $(sed -n 2p "$SANDBOX/watch.out")"
}

test_bus_watch_exit_code_without_daemon() {
    local status=0
    dotctl bus watch --data updates 2>/dev/null || status=$?
    [[ "$status" == 3 ]] || fail "exit $status, want 3"
}

test_waybar_config_references_exist() {
    local cfg="$REPO/modules/waybar/home/.config/waybar/config"
    jq empty "$cfg" || fail "waybar config is not valid JSON"
    local cmd
    while IFS= read -r cmd; do
        # shellcheck disable=SC2088 # the config holds a literal ~ that waybar's shell expands
        case "$cmd" in
            "~/.local/bin/dotctl menu "*) [[ -x "$REPO/modules/rofi/menus/${cmd##* }" ]] || fail "no menu for: $cmd" ;;
            "~/.local/bin/dotctl bus watch --format "*)
                local f="${cmd#*--format \~/}"
                f="${f%% *}"
                [[ -f "$REPO/modules/waybar/home/$f" ]] || fail "no jq file for: $cmd" ;;
            *dotctl*) fail "unchecked dotctl command: $cmd" ;;
        esac
    done < <(jq -r '.[] | objects | (.exec, ."on-click") // empty' "$cfg")
}

test_remove_wofi_links_migration() {
    module rofi
    real_migration rofi 0001-remove-wofi-links
    mkdir -p "$DOTCTL_TARGET/.config/wofi" "$DOTCTL_TARGET/.local/bin" "$ROOT/still-here"
    ln -s "$ROOT/modules/wofi/home/.config/wofi/config" "$DOTCTL_TARGET/.config/wofi/config"          # dangling, ours
    ln -s "$ROOT/modules/wofi/home/.config/wofi/style.css" "$DOTCTL_TARGET/.config/wofi/style.css"    # dangling, ours
    printf 'x\n' >"$ROOT/still-here/bt"
    ln -s "$ROOT/still-here/bt" "$DOTCTL_TARGET/.local/bin/wofi-bluetooth"                           # ours, still resolves
    dotctl migrate
    [[ ! -e "$DOTCTL_TARGET/.config/wofi" ]] || fail ".config/wofi left: $(ls -A "$DOTCTL_TARGET/.config/wofi")"
    [[ -L "$DOTCTL_TARGET/.local/bin/wofi-bluetooth" ]] || fail "removed a link that still resolves"

    # a file of the user's own keeps the directory
    rm "$DOTCTL_STATE/migrations"
    mkdir -p "$DOTCTL_TARGET/.config/wofi"
    ln -s "$ROOT/modules/wofi/home/.config/wofi/config" "$DOTCTL_TARGET/.config/wofi/config"
    printf 'mine\n' >"$DOTCTL_TARGET/.config/wofi/style.css"
    dotctl migrate
    [[ ! -L "$DOTCTL_TARGET/.config/wofi/config" ]] || fail "dangling link left"
    [[ "$(cat "$DOTCTL_TARGET/.config/wofi/style.css")" == mine ]] || fail "user file touched"
}

test_remove_bar_scripts_migration() {
    module waybar
    real_migration waybar 0001-remove-bar-scripts
    mkdir -p "$DOTCTL_TARGET/.local/bin"
    ln -s "$ROOT/modules/waybar/home/.local/bin/cpu_watts.sh" "$DOTCTL_TARGET/.local/bin/cpu_watts.sh"   # dangling, ours
    printf 'mine\n' >"$DOTCTL_TARGET/.local/bin/memory_usage.sh"                                         # the user's own file
    dotctl migrate
    [[ ! -L "$DOTCTL_TARGET/.local/bin/cpu_watts.sh" ]] || fail "dangling link left"
    [[ "$(cat "$DOTCTL_TARGET/.local/bin/memory_usage.sh")" == mine ]] || fail "user file touched"
}

command -v go >/dev/null || { echo "tests need go to build dotctld" >&2; exit 1; }
go -C "$REPO/daemon" build -o "$SANDBOX/dotctld" ./cmd/dotctld

for t in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    run "$t"
done
printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
