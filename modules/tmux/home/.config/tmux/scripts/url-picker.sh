#!/usr/bin/env bash
# Pick URLs from the current pane's scrollback (prefix+u, runs in a popup).
# Enter opens in the browser, Ctrl-y copies to the Wayland clipboard; Tab selects several.
set -euo pipefail

pane="${1:-${TMUX_PANE:-}}"
[ -n "$pane" ] || exit 1

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "url-picker: fzf is not installed (pacman -S fzf)"
  exit 0
fi

urls=$(tmux capture-pane -J -p -S -3000 -t "$pane" |
  grep -oE "(https?|ftp|file)://[-[:alnum:]_+&@#/%?=~|!:,.;]*[-[:alnum:]_+&@#/%=~|]" |
  awk '!seen[$0]++' | tac) || true
[ -n "$urls" ] || { tmux display-message "no URLs in pane"; exit 0; }

out=$(printf '%s\n' "$urls" |
  fzf -m --no-sort --prompt='url> ' --header='Enter open   Ctrl-y copy   Tab select' --expect=ctrl-y) || exit 0
key=$(head -1 <<<"$out")
sel=$(tail -n +2 <<<"$out")
[ -n "$sel" ] || exit 0

if [ "$key" = "ctrl-y" ]; then
  printf '%s' "$sel" | wl-copy
  tmux display-message "copied $(wc -l <<<"$sel") URL(s)"
else
  while IFS= read -r u; do
    nohup xdg-open "$u" >/dev/null 2>&1 &
  done <<<"$sel"
fi
