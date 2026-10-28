# shellcheck shell=bash
# link.sh: link modules/<name>/home/ into DOTCTL_TARGET with GNU Stow.
#
# Stow runs with --no-folding, so every file gets its own link and two modules
# can share a directory such as ~/.config. Before stow runs, whatever is in the
# way is cleared:
#   - a link into this repo (left by the old repo-root `stow .`) is removed;
#   - any other file, directory or link is moved to a backup, never deleted.

# path_is_repo_link <path>: true when <path> is a symlink pointing anywhere
# inside DOTCTL_ROOT, whether or not its target still exists.
path_is_repo_link() {
    local path="$1" dest
    [[ -L "$path" ]] || return 1
    dest="$(readlink -- "$path")"
    [[ "$dest" == /* ]] || dest="$(dirname -- "$path")/$dest"
    dest="$(realpath -m -- "$dest")"
    [[ "$dest" == "$DOTCTL_ROOT" || "$dest" == "$DOTCTL_ROOT"/* ]]
}

# Paths a dry run already reported: nothing is removed, so a folded directory
# link would otherwise be reported once per file below it.
declare -A _LINK_DRY_REMOVED=()

_link_remove_stale() {
    if dry_run; then
        [[ -z "${_LINK_DRY_REMOVED[$1]:-}" ]] || return 0
        _LINK_DRY_REMOVED[$1]=1
        log "would remove stale link ${1/#"$DOTCTL_TARGET"/\~}"
    else
        rm -- "$1"
        log "removed stale link ${1/#"$DOTCTL_TARGET"/\~}"
    fi
}

# Directories on the way to <rel> must be real directories.
_link_clear_parents() {
    local module="$1" rel="$2" path="$DOTCTL_TARGET" part
    local -a parts
    [[ "$rel" == */* ]] || return 0
    IFS='/' read -ra parts <<<"${rel%/*}"
    for part in "${parts[@]}"; do
        path="$path/$part"
        if path_is_repo_link "$path"; then
            # A folded directory link from the old `stow .`. Removing a live one
            # would unlink files that were not moved into this module.
            [[ ! -e "$path" ]] || die "${path/#"$DOTCTL_TARGET"/\~} is a directory link into $DOTCTL_ROOT that still resolves; move all of its files into module '$module' first"
            _link_remove_stale "$path"
            return 0
        elif [[ -L "$path" ]]; then
            return 0 # foreign directory link: leave it to stow
        elif [[ -e "$path" && ! -d "$path" ]]; then
            backup_path "$path" "$module"
            return 0
        elif [[ ! -e "$path" ]]; then
            return 0
        fi
    done
}

_link_clear_target() {
    local module="$1" rel="$2" target own
    target="$DOTCTL_TARGET/$rel"
    own="$(module_dir "$module")/home/$rel"
    if path_is_repo_link "$target"; then
        [[ "$(realpath -m -- "$target")" == "$(realpath -m -- "$own")" ]] || _link_remove_stale "$target"
    elif [[ -e "$target" || -L "$target" ]]; then
        backup_path "$target" "$module"
    fi
}

# link_module <module>
link_module() {
    local module="$1" pkg src rel count=0
    pkg="$(module_dir "$module")/home"
    if [[ ! -d "$pkg" ]]; then
        log "$module: no home/ to link"
        return 0
    fi

    while IFS= read -r -d '' src; do
        rel="${src#"$pkg"/}"
        _link_clear_parents "$module" "$rel"
        _link_clear_target "$module" "$rel"
        count=$((count + 1))
    done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)

    if dry_run; then
        log "$module: would link $count file(s)"
        return 0
    fi
    mkdir -p "$DOTCTL_TARGET"
    stow --no-folding --dir="$(module_dir "$module")" --target="$DOTCTL_TARGET" --restow home \
        || die "$module: stow failed"
    log "$module: linked $count file(s)"
}
