# shellcheck shell=bash
# state.sh: record which modules were applied and when.
#
#   $DOTCTL_STATE/applied   one "<module>\t<ISO-8601 time>" line per module

state_applied_file() { printf '%s/applied\n' "$DOTCTL_STATE"; }

state_mark_applied() {
    local module="$1" file tmp
    dry_run && return 0
    file="$(state_applied_file)"
    mkdir -p "$DOTCTL_STATE"
    tmp="$(mktemp "$file.XXXXXX")"
    if [[ -f "$file" ]]; then
        awk -F'\t' -v m="$module" '$1 != m' "$file" >"$tmp"
    fi
    printf '%s\t%s\n' "$module" "$(date --iso-8601=seconds)" >>"$tmp"
    mv -- "$tmp" "$file"
}

# state_applied_at <module>: print when it was last applied, or nothing.
state_applied_at() {
    local file
    file="$(state_applied_file)"
    [[ -f "$file" ]] || return 0
    awk -F'\t' -v m="$1" '$1 == m { print $2 }' "$file"
}
