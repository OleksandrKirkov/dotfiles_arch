#!/bin/bash

MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_AVAILABLE=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)

MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))

PERCENT=$(awk "BEGIN { printf \"%.0f\", ($MEM_USED / $MEM_TOTAL) * 100 }")

USED_GB=$(awk "BEGIN { printf \"%.0f\", $MEM_USED / 1024 / 1024 }")

# echo "  ${PERCENT}% ${USED_GB}G"

case "$1" in
    icon) echo "" ;;
    percent) echo "${PERCENT}%" ;;
    gb) echo "${USED_GB}G" ;;
esac
