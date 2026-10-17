#!/bin/bash

read cpu u1 n1 s1 i1 iw1 irq1 sirq1 st1 _ < /proc/stat
IDLE1=$((i1 + iw1))
TOTAL1=$((u1 + n1 + s1 + i1 + iw1 + irq1 + sirq1 + st1))

sleep 1

read cpu u2 n2 s2 i2 iw2 irq2 sirq2 st2 _ < /proc/stat
IDLE2=$((i2 + iw2))
TOTAL2=$((u2 + n2 + s2 + i2 + iw2 + irq2 + sirq2 + st2))

DIFF_IDLE=$((IDLE2 - IDLE1))
DIFF_TOTAL=$((TOTAL2 - TOTAL1))

CPU=$(awk "BEGIN { printf \"%.0f\", (1 - $DIFF_IDLE / $DIFF_TOTAL) * 100 }")

RAW_TEMP=$(sensors 2>/dev/null | awk '
  /Package id 0:/ && /°C/ { gsub(/[+°C]/,"",$4); printf "%.0f", $4; exit }
  /Tctl:/               { gsub(/[+°C]/,"",$2); printf "%.0f", $2; exit }
')

if [[ "$RAW_TEMP" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  TEMP="${RAW_TEMP}°C"
else
  TEMP="N/A"
fi

# echo " ${CPU}% ${TEMP}"

case "$1" in
    icon) echo " " ;;
    percent) echo "${CPU}%" ;;
    temp) echo "${TEMP}" ;;
esac
