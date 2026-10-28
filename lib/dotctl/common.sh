# shellcheck shell=bash
# common.sh: paths, logging and shared helpers for every dotctl command.
#
# Sourced, never executed. Expects DOTCTL_ROOT to be set by bin/dotctl.
#
# Env overrides (used by tests and by multi-user setups later):
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
DOTCTL_MODULES="$DOTCTL_ROOT/modules"
DOTCTL_TARGET="${DOTCTL_TARGET:-$HOME}"
DOTCTL_STATE="${DOTCTL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotctl}"
DOTCTL_HOOKS="${DOTCTL_HOOKS:-${XDG_CONFIG_HOME:-$HOME/.config}/dotctl/hooks}"
DOTCTL_DRY_RUN="${DOTCTL_DRY_RUN:-0}"
export DOTCTL_VERSION DOTCTL_ROOT DOTCTL_TARGET DOTCTL_STATE DOTCTL_HOOKS DOTCTL_DRY_RUN

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
