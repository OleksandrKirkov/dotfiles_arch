# shellcheck shell=bash
# backup.sh: move files out of the way instead of deleting them, or copy them
# before a migration changes them.
#
# Every dotctl run that backs something up gets one backup directory:
#   $DOTCTL_STATE/backups/<run-id>/
#     MANIFEST   one "<module>\t<path relative to DOTCTL_TARGET>\t<kind>" line per
#                entry; kind is "move" (displaced, the default) or "copy"
#     files/     the files, at their original relative paths
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
    printf '%s\t%s\tmove\n' "$module" "$rel" >>"$dir/MANIFEST"
    log "backed up ~/${rel} -> ${dir/#"$HOME"/\~}/files/$rel"
}

# backup_copy <absolute path inside DOTCTL_TARGET> <module>: copy it into this
# run's backup and leave it in place. A path copied once per run is kept as first seen.
backup_copy() {
    local path="$1" module="$2" rel dir
    [[ "$path" == /* ]] || path="$PWD/$path"
    rel="${path#"$DOTCTL_TARGET"/}"
    [[ "$rel" != "$path" ]] || die "refusing to back up '$path': outside $DOTCTL_TARGET"
    [[ -e "$path" || -L "$path" ]] || die "nothing to back up at $path"

    if dry_run; then
        log "would copy ~/${rel} into a backup ($module)"
        return 0
    fi

    dir="$(backup_root)/$(dotctl_run_id)"
    if [[ -f "$dir/MANIFEST" ]] && awk -F'\t' -v r="$rel" '$2 == r { found = 1 } END { exit !found }' "$dir/MANIFEST"; then
        return 0
    fi
    mkdir -p "$dir/files/$(dirname "$rel")"
    cp -a -- "$path" "$dir/files/$rel"
    printf '%s\t%s\tcopy\n' "$module" "$rel" >>"$dir/MANIFEST"
    log "copied ~/${rel} -> ${dir/#"$HOME"/\~}/files/$rel"
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
# place are removed. For a moved file, anything else in the way aborts before a
# file moves. For a copied file, what is there now is the changed version: it is
# moved into a new backup first, so a restore never loses it either.
backup_restore() {
    local id="$1" dir module rel kind dest blocked=0
    backup_require "$id"
    [[ "$id" != *.restored ]] || die "backup '$id' was already restored"
    dir="$(backup_root)/$id"

    while IFS=$'\t' read -r module rel kind; do
        dest="$DOTCTL_TARGET/$rel"
        [[ -e "$dir/files/$rel" || -L "$dir/files/$rel" ]] || die "backup '$id' is missing files/$rel"
        [[ "${kind:-move}" == move ]] || continue
        if [[ -e "$dest" || -L "$dest" ]] && ! path_is_repo_link "$dest"; then
            warn "$dest exists and was not created by dotctl"
            blocked=1
        fi
    done <"$dir/MANIFEST"
    ((blocked == 0)) || die "restore aborted; move the files above aside first"

    while IFS=$'\t' read -r module rel kind; do
        dest="$DOTCTL_TARGET/$rel"
        if dry_run; then
            log "would restore ~/$rel ($module)"
            continue
        fi
        if path_is_repo_link "$dest"; then
            rm -- "$dest"
        elif [[ "${kind:-move}" == copy ]] && [[ -e "$dest" || -L "$dest" ]]; then
            backup_path "$dest" "$module"
        fi
        mkdir -p "$(dirname "$dest")"
        mv -- "$dir/files/$rel" "$dest"
        log "restored ~/$rel ($module)"
    done <"$dir/MANIFEST"

    dry_run || mv -- "$dir" "$dir.restored"
}
