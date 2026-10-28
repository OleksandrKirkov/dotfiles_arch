# shellcheck shell=bash
# common.sh: paths, logging and shared helpers for every dotctl command.
#
# Sourced, never executed. Expects DOTCTL_ROOT to be set by bin/dotctl.
#
# Two roots:
#   DOTCTL_ROOT   the tool: bin/, lib/, libexec/ (and daemon/ in a checkout).
#                 A git checkout, or /usr/lib/dotctl when installed as a package.
#   DOTCTL_REPO   the config: modules/, hosts/, themes/. Resolved in order:
#                   1. $DOTCTL_REPO
#                   2. DOTCTL_ROOT, when it holds modules/ (a checkout uses its own config)
#                   3. REPO= in the user file
#
# Env overrides (used by tests and by multi-user setups):
#   DOTCTL_USER_CONF  the user file (default: ${XDG_CONFIG_HOME:-~/.config}/dotctl/user.conf)
#   DOTCTL_TARGET   directory module files are linked into (default: $HOME)
#   DOTCTL_STATE    state directory (default: ${XDG_STATE_HOME:-~/.local/state}/dotctl)
#   DOTCTL_HOOKS    user hook directory (default: ${XDG_CONFIG_HOME:-~/.config}/dotctl/hooks)

[[ -n "${DOTCTL_ROOT:-}" ]] || {
    echo "dotctl: DOTCTL_ROOT is not set; run commands through bin/dotctl" >&2
    exit 1
}

# errexit inside $(...) too: otherwise a failure in a nested command
# substitution is ignored and the caller carries on with partial output.
shopt -s inherit_errexit

DOTCTL_VERSION="0.1.0"
DOTCTL_LIB="$DOTCTL_ROOT/lib/dotctl"
DOTCTL_USER_CONF="${DOTCTL_USER_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/dotctl/user.conf}"
DOTCTL_TARGET="${DOTCTL_TARGET:-$HOME}"
DOTCTL_STATE="${DOTCTL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotctl}"
DOTCTL_HOOKS="${DOTCTL_HOOKS:-${XDG_CONFIG_HOME:-$HOME/.config}/dotctl/hooks}"
DOTCTL_DRY_RUN="${DOTCTL_DRY_RUN:-0}"
export DOTCTL_VERSION DOTCTL_ROOT DOTCTL_USER_CONF DOTCTL_TARGET DOTCTL_STATE DOTCTL_HOOKS DOTCTL_DRY_RUN

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    _c_dim=$'\e[2m' _c_yellow=$'\e[33m' _c_red=$'\e[31m' _c_reset=$'\e[0m'
else
    _c_dim="" _c_yellow="" _c_red="" _c_reset=""
fi

log()  { printf '%s::%s %s\n' "$_c_dim" "$_c_reset" "$*" >&2; }
warn() { printf '%swarn:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; exit 1; }

dry_run() { [[ "$DOTCTL_DRY_RUN" == 1 ]]; }

# One id per dotctl invocation, shared by every backup taken during it and
# inherited by the commands and hooks it starts. Set here, at load time: set
# inside a $(...) it would be lost and every backup would get its own id.
# Nanoseconds keep two runs in the same second apart.
DOTCTL_RUN_ID="${DOTCTL_RUN_ID:-$(date +%Y%m%dT%H%M%S%N)}"
export DOTCTL_RUN_ID

dotctl_run_id() { printf '%s\n' "$DOTCTL_RUN_ID"; }

# shellcheck source=user.sh
source "$DOTCTL_LIB/user.sh"

if [[ -z "${DOTCTL_REPO:-}" ]]; then
    if [[ -d "$DOTCTL_ROOT/modules" ]]; then
        DOTCTL_REPO="$DOTCTL_ROOT"
    else
        DOTCTL_REPO="$(user_conf_get REPO)"
        [[ -n "$DOTCTL_REPO" ]] \
            || die "no config repo: set REPO=<path to your dotfiles checkout> in $DOTCTL_USER_CONF, or DOTCTL_REPO"
    fi
fi
[[ -d "$DOTCTL_REPO/modules" ]] || die "$DOTCTL_REPO is not a dotctl config repo (no modules/)"
# Physical path: links are recognised as ours by comparing resolved paths.
DOTCTL_REPO="$(cd "$DOTCTL_REPO" && pwd -P)"
DOTCTL_MODULES="$DOTCTL_REPO/modules"
export DOTCTL_REPO

# shellcheck source=manifest.sh
source "$DOTCTL_LIB/manifest.sh"
# shellcheck source=backup.sh
source "$DOTCTL_LIB/backup.sh"
# shellcheck source=link.sh
source "$DOTCTL_LIB/link.sh"
# shellcheck source=hooks.sh
source "$DOTCTL_LIB/hooks.sh"
# shellcheck source=state.sh
source "$DOTCTL_LIB/state.sh"
# shellcheck source=pkg.sh
source "$DOTCTL_LIB/pkg.sh"
# shellcheck source=migrate.sh
source "$DOTCTL_LIB/migrate.sh"
# shellcheck source=bus.sh
source "$DOTCTL_LIB/bus.sh"
