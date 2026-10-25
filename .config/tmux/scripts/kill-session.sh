#!/usr/bin/env bash
# Bound to prefix+X / prefix+Ctrl-x, runs inside a tmux popup.
# fzf list of every session with a preview of its windows; Tab selects several, Enter kills (after a y/N).
# Clients on a killed session move to their previous session, or to a fresh `main` when nothing else is left.
#
#   kill-session.sh            interactive picker
#   kill-session.sh --list     picker rows (name<TAB>display)
#   kill-session.sh --preview <session>
set -euo pipefail

current_session() {
  tmux display-message -p '#{session_name}' 2>/dev/null || echo ""
}

list_sessions() {
  local curr name nwin created attached mark att
  curr="$(current_session)"
  while IFS=$'\t' read -r name nwin created attached; do
    mark=" "; att="detached"
    [ "$attached" -gt 0 ] && att="attached"
    if [ "$name" = "$curr" ]; then mark="*"; att="current"; fi
    printf '%s\t%s %-16s (%d win)  %s  [%s]\n' "$name" "$mark" "$name" "$nwin" \
      "$(date -d "@$created" '+%Y-%m-%d %H:%M')" "$att"
  done < <(tmux list-sessions -F '#{session_name}	#{session_windows}	#{session_created}	#{session_attached}' 2>/dev/null)
}

preview_session() {
  local s="${1:-}"
  if [ -z "$s" ] || ! tmux has-session -t "=$s" 2>/dev/null; then
    echo "Session '$s' not found."
    return 0
  fi
  echo "Session: $s"
  echo ""
  echo "Windows:"
  tmux list-windows -t "=$s" -F '  #I: #W #{?window_active,[active],} (#{window_panes} panes)  [#{pane_current_command}] #{pane_current_path}'
}

safe_kill() {
  local -a targets=("$@") all=()
  local curr survivor="" last s t includes_curr=0
  curr="$(current_session)"
  mapfile -t all < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  is_target() { local x; for x in "${targets[@]}"; do [ "$1" = "$x" ] && return 0; done; return 1; }
  is_target "$curr" && includes_curr=1

  # survivor: the client's previous session first, otherwise any session not being killed
  last="$(tmux display-message -p '#{client_last_session}' 2>/dev/null || echo "")"
  if [ -n "$last" ] && tmux has-session -t "=$last" 2>/dev/null && ! is_target "$last"; then
    survivor="$last"
  else
    for s in "${all[@]}"; do is_target "$s" || { survivor="$s"; break; }; done
  fi

  # killing the last session(s) would stop the server: create a fresh one for the client
  if [ "$includes_curr" -eq 1 ] && [ -z "$survivor" ]; then
    local fresh="main" i=1
    while tmux has-session -t "=$fresh" 2>/dev/null || is_target "$fresh"; do fresh="main-$i"; i=$((i + 1)); done
    tmux new-session -d -s "$fresh" -c "$HOME"
    survivor="$fresh"
  fi
  [ "$includes_curr" -eq 1 ] && tmux switch-client -t "=$survivor" 2>/dev/null || true

  for t in "${targets[@]}"; do
    tmux kill-session -t "=$t" 2>/dev/null || true
  done
  tmux display-message "Sessions killed: ${#targets[@]}" 2>/dev/null || true
}

case "${1:-}" in
  --list) list_sessions; exit 0 ;;
  --preview) preview_session "${2:-}"; exit 0 ;;
esac

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is not installed (pacman -S fzf)."
  read -n1 -r -p "press any key..."
  exit 1
fi

chosen="$(list_sessions | fzf -m --prompt='kill> ' --delimiter=$'\t' --with-nth=2.. \
  --header='Tab select   Enter kill   Esc quit' \
  --preview="bash '$0' --preview {1}" --preview-window='right,50%,wrap')" || exit 0

targets=()
while IFS= read -r l; do
  [ -n "$l" ] && targets+=("${l%%$'\t'*}")
done <<<"$chosen"
[ ${#targets[@]} -gt 0 ] || exit 0

printf '\nKill %d session(s): %s? [y/N]: ' "${#targets[@]}" "${targets[*]}"
read -r ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  safe_kill "${targets[@]}"
else
  echo "Cancelled."
  sleep 0.3
fi
