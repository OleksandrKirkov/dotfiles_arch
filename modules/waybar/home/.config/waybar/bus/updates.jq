# waybar custom module JSON from a bus "updates" message (docs/bus.md).
# Empty text hides the module, so it only shows while something is pending.
.data as $u
| (($u.packages // 0) + ($u.aur // 0) + ($u.repo // 0)) as $n
| {
    text: (if $n > 0 then "󰚰\n\($n)" else "" end),
    tooltip: "Updates (click for the menu)\npacman: \($u.packages // "?")\nAUR: \($u.aur // "?")\ndotfiles: \($u.repo // "?") commit(s)\nchecked \($u.checked // "never")",
    class: (if $n > 0 then "pending" else "none" end)
  }
