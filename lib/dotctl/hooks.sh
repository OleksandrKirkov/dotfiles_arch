# shellcheck shell=bash
# hooks.sh: run event hooks, module hooks first, then the user's own.
#
#   modules/<module>/hooks/<event>.d/<hook>
#   $DOTCTL_HOOKS/<event>.d/<hook>
#
# Like run-parts: hooks run in name order, and only executable files whose
# name is made of [A-Za-z0-9_-] run (so "50-reload" runs, "50-reload.bak" does not).
# Each hook gets DOTCTL_ROOT, DOTCTL_TARGET, DOTCTL_EVENT and DOTCTL_MODULE
# (empty for user hooks). A failing hook is reported; the rest still run.
#
# Events so far: link (after a module's files are linked).

_hooks_run_dir() {
    local dir="$1" event="$2" module="$3" hook name status failed=0
    [[ -d "$dir" ]] || return 0
    for hook in "$dir"/*; do
        name="${hook##*/}"
        [[ -f "$hook" && "$name" =~ ^[A-Za-z0-9_-]+$ ]] || continue
        if [[ ! -x "$hook" ]]; then
            warn "skipping non-executable hook $hook"
            continue
        fi
        if dry_run; then
            log "would run $event hook ${hook/#"$DOTCTL_ROOT"\//}"
            continue
        fi
        log "$event hook ${hook/#"$DOTCTL_ROOT"\//}"
        status=0
        DOTCTL_EVENT="$event" DOTCTL_MODULE="$module" "$hook" || status=$?
        if ((status != 0)); then
            warn "hook exited $status: $hook"
            failed=1
        fi
    done
    return "$failed"
}

# hooks_run <event> <module...>
hooks_run() {
    local event="$1" module failed=0
    shift
    for module in "$@"; do
        _hooks_run_dir "$(module_dir "$module")/hooks/$event.d" "$event" "$module" || failed=1
    done
    _hooks_run_dir "$DOTCTL_HOOKS/$event.d" "$event" "" || failed=1
    return "$failed"
}
