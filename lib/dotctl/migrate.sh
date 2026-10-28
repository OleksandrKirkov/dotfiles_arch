# shellcheck shell=bash
# migrate.sh: run each module's one-time migrations and record them.
#
#   modules/<module>/migrations/NNNN-<slug>   executable, e.g. 0001-drop-iwd
#   $DOTCTL_STATE/migrations                  ledger: "<module>/<name>\t<ISO time>"
#
# A migration moves a machine from an older layout to the current one. It runs
# after its module is linked ('dotctl migrate', also the last step of
# 'dotctl update'), at most once per machine, and must be safe to run on a
# fresh install where there is nothing to migrate. Before changing a file it
# copies it with 'dotctl backup add <path>'.
#
# Modules run in dependency order, migrations in name order. The first failure
# stops the run and is not recorded, so it runs again next time.
#
# Each migration gets DOTCTL_ROOT, DOTCTL_TARGET, DOTCTL_RUN_ID, DOTCTL_MODULE
# and DOTCTL_MIGRATION (<module>/<name>), and bin/ first on PATH for dotctl.

migration_ledger() { printf '%s/migrations\n' "$DOTCTL_STATE"; }

# migration_list <module...>: print "<module>/<name>" for every migration.
migration_list() {
    local module path name
    for module in "$@"; do
        for path in "$(module_dir "$module")"/migrations/*; do
            [[ -e "$path" ]] || continue
            name="${path##*/}"
            [[ "$name" =~ ^[0-9]{4}-[a-z0-9-]+$ ]] || die "$path: migrations are named NNNN-slug"
            [[ -f "$path" && -x "$path" ]] || die "$path: not an executable file"
            printf '%s/%s\n' "$module" "$name"
        done
    done
}

# migration_done_at <module/name>: print when it ran, or nothing.
migration_done_at() {
    local ledger
    ledger="$(migration_ledger)"
    [[ -f "$ledger" ]] || return 0
    awk -F'\t' -v id="$1" '$1 == id { print $2; exit }' "$ledger"
}

migration_record() {
    dry_run && return 0
    mkdir -p "$DOTCTL_STATE"
    printf '%s\t%s\n' "$1" "$(date --iso-8601=seconds)" >>"$(migration_ledger)"
}

# migration_pending <module...>: the migrations not yet in the ledger.
migration_pending() {
    local list id
    list="$(migration_list "$@")"
    while IFS= read -r id; do
        if [[ -n "$id" && -z "$(migration_done_at "$id")" ]]; then printf '%s\n' "$id"; fi
    done <<<"$list"
}

# migrate_run <module...>
migrate_run() {
    local pending id module status count=0
    pending="$(migration_pending "$@")"
    if [[ -z "$pending" ]]; then
        log "no pending migrations"
        return 0
    fi
    while IFS= read -r id; do
        module="${id%%/*}"
        if dry_run; then
            log "would run migration $id"
            continue
        fi
        log "migration $id"
        status=0
        PATH="$DOTCTL_ROOT/bin:$PATH" DOTCTL_MODULE="$module" DOTCTL_MIGRATION="$id" \
            "$(module_dir "$module")/migrations/${id#*/}" || status=$?
        ((status == 0)) || die "migration $id exited $status; fix it and run 'dotctl migrate' again"
        migration_record "$id"
        count=$((count + 1))
    done <<<"$pending"
    dry_run || log "$count migration(s) applied"
}
