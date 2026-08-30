#!/usr/bin/env bash
# shellcheck shell=bash
# Estado compacto para el executor de tint2; no requiere privilegios.
set -Eeuo pipefail

network="offline"
if command -v nmcli >/dev/null 2>&1; then
  network="$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" {print $2; exit}')"
  [[ -n "$network" ]] || network="offline"
fi

volume="n/a"
if command -v wpctl >/dev/null 2>&1; then
  volume_status="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
  if [[ -n "$volume_status" ]]; then
    volume="$(awk '{printf "%d%%", ($2 * 100) + 0.5}' <<<"$volume_status")"
    grep -q '\[MUTED\]' <<<"$volume_status" && volume="muted"
  fi
fi

battery="n/a"
if command -v upower >/dev/null 2>&1; then
  battery_device="$(upower -e 2>/dev/null | grep -m1 '/battery_' || true)"
  if [[ -n "$battery_device" ]]; then
    battery="$(upower -i "$battery_device" 2>/dev/null | awk '/percentage:/ {print $2; exit}')"
  fi
fi

load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf 'n/a')"
memory="n/a"
if command -v free >/dev/null 2>&1; then
  memory="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2; exit}')"
fi

printf 'NET:%s | VOL:%s | BAT:%s | CPU:%s | RAM:%s | %s\n' \
  "$network" "$volume" "$battery" "$load" "$memory" "$(date '+%H:%M')"
