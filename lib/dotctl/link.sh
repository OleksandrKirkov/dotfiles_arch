# shellcheck shell=bash
# link.sh: link modules/<name>/home/ into DOTCTL_TARGET with GNU Stow.
#
# Stow runs with --no-folding, so every file gets its own link and two modules
# can share a directory such as ~/.config. Before stow runs, whatever is in the
# way is cleared:
#   - a link into this repo (left by the old repo-root `stow .`) is removed;
#   - any other file, directory or link is moved to a backup, never deleted.
#
# Templates: a file named <name>.tmpl is not linked itself. Its @KEY@ markers
# are replaced with the user's values (HOME, USER and the keys of user.conf,
# see user.sh), the result is written to $DOTCTL_STATE/render/<module>/home/<name>,
# and that is linked at ~/<name>. An unset key stops the apply. The render
# directory is regenerated on every apply.
#
# Each apply records the files a module linked in $DOTCTL_STATE/links/<module>.
# A file the module no longer ships leaves a link that points at nothing; the
# next apply removes it (only dangling links into this repo, nothing else).

render_root() { printf '%s/render\n' "$DOTCTL_STATE"; }

# path_is_repo_link <path>: true when <path> is a symlink dotctl owns: one
# pointing anywhere inside DOTCTL_REPO or the render directory, whether or not
# its target still exists.
path_is_repo_link() {
    local path="$1" dest render
    [[ -L "$path" ]] || return 1
    dest="$(readlink -- "$path")"
    [[ "$dest" == /* ]] || dest="$(dirname -- "$path")/$dest"
    dest="$(realpath -m -- "$dest")"
    render="$(realpath -m -- "$(render_root)")"
    [[ "$dest" == "$DOTCTL_REPO" || "$dest" == "$DOTCTL_REPO"/* || "$dest" == "$render"/* ]]
}

# render_template <src> <dst> <vars assoc name>: write src with @KEY@ replaced.
render_template() {
    local src="$1" dst="$2" content out="" rest key match tmp
    local -n _tvars="$3"
    # read it all, trailing newlines included
    content="$(cat -- "$src"; printf x)"
    content="${content%x}"
    rest="$content"
    while [[ "$rest" =~ @([A-Z][A-Z0-9_]*)@ ]]; do
        match="${BASH_REMATCH[0]}"
        key="${BASH_REMATCH[1]}"
        [[ -v "_tvars[$key]" ]] \
            || die "${src#"$DOTCTL_REPO"/} uses @$key@, which is not set; add $key=... to $DOTCTL_USER_CONF"
        out+="${rest%%"$match"*}${_tvars[$key]}"
        rest="${rest#*"$match"}"
    done
    out+="$rest"
    mkdir -p "$(dirname -- "$dst")"
    tmp="$(mktemp "$dst.XXXXXX")"
    printf '%s' "$out" >"$tmp"
    chmod --reference="$src" "$tmp"
    mv -- "$tmp" "$dst"
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
            [[ ! -e "$path" ]] || die "${path/#"$DOTCTL_TARGET"/\~} is a directory link into $DOTCTL_REPO that still resolves; move all of its files into module '$module' first"
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

# _link_clear_target <module> <rel> <the file ~/<rel> should link to>
_link_clear_target() {
    local module="$1" rel="$2" own="$3" target
    target="$DOTCTL_TARGET/$rel"
    if path_is_repo_link "$target"; then
        [[ "$(realpath -m -- "$target")" == "$(realpath -m -- "$own")" ]] || _link_remove_stale "$target"
    elif [[ -e "$target" || -L "$target" ]]; then
        backup_path "$target" "$module"
    fi
}

_link_state_file() { printf '%s/links/%s\n' "$DOTCTL_STATE" "$1"; }

# _link_prune <module> <rels linked now, one per line>: remove the dangling
# repo links of files the module linked last time but no longer ships.
_link_prune() {
    local module="$1" current="$2" file rel target
    file="$(_link_state_file "$module")"
    [[ -f "$file" ]] || return 0
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        grep -qxF -- "$rel" <<<"$current" && continue
        target="$DOTCTL_TARGET/$rel"
        if path_is_repo_link "$target" && [[ ! -e "$target" ]]; then
            _link_remove_stale "$target"
        fi
    done <"$file"
}

_link_record() {
    local file
    dry_run && return 0
    file="$(_link_state_file "$1")"
    mkdir -p "$(dirname "$file")"
    printf '%s' "$2" >"$file"
}

# link_module <module>
link_module() {
    local module="$1" pkg src rel own render count=0 current=""
    local -a templates=()
    pkg="$(module_dir "$module")/home"
    render="$(render_root)/$module"
    if [[ ! -d "$pkg" ]]; then
        _link_prune "$module" ""
        _link_record "$module" ""
        dry_run || rm -rf -- "$render"
        log "$module: no home/ to link"
        return 0
    fi

    while IFS= read -r -d '' src; do
        rel="${src#"$pkg"/}"
        own="$src"
        if [[ "$rel" == *.tmpl ]]; then
            rel="${rel%.tmpl}"
            [[ ! -e "$pkg/$rel" && ! -L "$pkg/$rel" ]] || die "$module: both $rel and $rel.tmpl exist"
            own="$render/home/$rel"
            templates+=("$rel")
        fi
        _link_clear_parents "$module" "$rel"
        _link_clear_target "$module" "$rel" "$own"
        current+="$rel"$'\n'
        count=$((count + 1))
    done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)

    if dry_run; then
        if ((${#templates[@]})); then
            # Render into a scratch directory so a missing key fails the dry run too.
            # shellcheck disable=SC2034 # filled and read through namerefs
            local -A vars=()
            local scratch
            user_template_vars vars
            scratch="$(mktemp -d)"
            for rel in "${templates[@]}"; do
                render_template "$pkg/$rel.tmpl" "$scratch/$rel" vars
            done
            rm -rf -- "$scratch"
        fi
        _link_prune "$module" "$current"
        log "$module: would link $count file(s), ${#templates[@]} rendered"
        return 0
    fi

    # Regenerate the renders; a template dropped since the last apply leaves a
    # dangling link that the prune below removes.
    rm -rf -- "$render"
    if ((${#templates[@]})); then
        # shellcheck disable=SC2034 # filled and read through namerefs
        local -A vars=()
        user_template_vars vars
        for rel in "${templates[@]}"; do
            render_template "$pkg/$rel.tmpl" "$render/home/$rel" vars
        done
    fi
    _link_prune "$module" "$current"

    mkdir -p "$DOTCTL_TARGET"
    stow --no-folding --ignore='\.tmpl' --dir="$(module_dir "$module")" --target="$DOTCTL_TARGET" --restow home \
        || die "$module: stow failed"
    if ((${#templates[@]})); then
        stow --no-folding --dir="$render" --target="$DOTCTL_TARGET" --restow home \
            || die "$module: stow of rendered templates failed"
    fi
    _link_record "$module" "$current"
    log "$module: linked $count file(s), ${#templates[@]} rendered"
}
