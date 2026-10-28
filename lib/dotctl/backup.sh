# shellcheck shell=bash
# backup.sh: move files out of the way instead of deleting them.
#
# Every dotctl run that displaces something gets one backup directory:
#   $DOTCTL_STATE/backups/<run-id>/
#     MANIFEST   one "<module>\t<path relative to DOTCTL_TARGET>" line per entry
#     files/     the displaced files, at their original relative paths
# A restored backup is renamed to <run-id>.restored and keeps its MANIFEST.

backup_root() { printf '%s/backups\n' "$DOTCTL_STATE"; }

# backup_path <absolute path inside DOTCTL_TARGET> <module>
backup_path() {
    local path="$1" module="$2" rel dir
    rel="${path#"$DOTCTL_TARGET"/}"
    [[ "$rel" != "$path" ]] || die "refusing to back up '$path': outside $DOTCTL_TARGET"

    if dry_run; then
        log "would back up ~/${rel} ($module)"
        return 0
    fi

    dir="$(backup_root)/$(dotctl_run_id)"
    mkdir -p "$dir/files/$(dirname "$rel")"
    mv -- "$path" "$dir/files/$rel"
    printf '%s\t%s\n' "$module" "$rel" >>"$dir/MANIFEST"
    log "backed up ~/${rel} -> ${dir/#"$HOME"/\~}/files/$rel"
}

backup_ids() {
    local dir
    for dir in "$(backup_root)"/*/; do
        [[ -f "$dir/MANIFEST" ]] || continue
        dir="${dir%/}"
        printf '%s\n' "${dir##*/}"
    done
}

backup_require() {
    [[ "$1" =~ ^[0-9T]+(\.restored)?$ && -f "$(backup_root)/$1/MANIFEST" ]] || die "no backup named '$1' (see 'dotctl backup list')"
}

# backup_restore <id>: put every file back. Links dotctl created in their
# place are removed; anything else in the way aborts before a file moves.
backup_restore() {
    local id="$1" dir module rel dest blocked=0
    backup_require "$id"
    [[ "$id" != *.restored ]] || die "backup '$id' was already restored"
    dir="$(backup_root)/$id"

    while IFS=$'\t' read -r module rel; do
        dest="$DOTCTL_TARGET/$rel"
        [[ -e "$dir/files/$rel" || -L "$dir/files/$rel" ]] || die "backup '$id' is missing files/$rel"
        if [[ -e "$dest" || -L "$dest" ]] && ! path_is_repo_link "$dest"; then
            warn "$dest exists and was not created by dotctl"
            blocked=1
        fi
    done <"$dir/MANIFEST"
    ((blocked == 0)) || die "restore aborted; move the files above aside first"

    while IFS=$'\t' read -r module rel; do
        dest="$DOTCTL_TARGET/$rel"
        if dry_run; then
            log "would restore ~/$rel ($module)"
            continue
        fi
        if path_is_repo_link "$dest"; then
            rm -- "$dest"
        fi
        mkdir -p "$(dirname "$dest")"
        mv -- "$dir/files/$rel" "$dest"
        log "restored ~/$rel ($module)"
    done <"$dir/MANIFEST"

    dry_run || mv -- "$dir" "$dir.restored"
}
