#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_kbd_brightness_linux.sh
# Ajusta el brillo del teclado retroiluminado y muestra notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DEVICE="${KBD_BACKLIGHT_DEVICE:-/sys/class/leds/smc::kbd_backlight}"
STEP="${KBD_BRIGHTNESS_STEP:-20}"

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

case "${1:-}" in
  up)   ;;
  down) ;;
  *)    usage ;;
esac

CURRENT=$(cat "$DEVICE/brightness")
MAX=$(cat "$DEVICE/max_brightness")

case "$1" in
  up)   NEW=$((CURRENT + STEP)) ;;
  down) NEW=$((CURRENT - STEP)) ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < 0 ))   && NEW=0

echo "$NEW" | tee "$DEVICE/brightness" > /dev/null

PERCENT=$(( NEW * 100 / MAX ))
notify-send -t 800 "⌨️ Brillo teclado" "${PERCENT}%"
