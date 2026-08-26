#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_kbd_brightness_linux.sh
# Ajusta el brillo del teclado retroiluminado y muestra notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ -n "${KBD_BACKLIGHT_DEVICE:-}" ]]; then
  DEVICE="$KBD_BACKLIGHT_DEVICE"
else
  DEVICE="$(find /sys/class/leds -maxdepth 1 -type d \( -name '*kbd_backlight' -o -name 'smc::kbd_backlight' \) -print -quit 2>/dev/null || true)"
fi
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

if [[ -z "$DEVICE" || ! -f "$DEVICE/brightness" || ! -f "$DEVICE/max_brightness" ]]; then
  echo "No se encontró un dispositivo de retroiluminación de teclado." >&2
  exit 1
fi

CURRENT=$(cat "$DEVICE/brightness")
MAX=$(cat "$DEVICE/max_brightness")

if [[ -z "${KBD_BRIGHTNESS_STEP:-}" && "$MAX" -le 10 ]]; then
  STEP=1
fi

if [[ "$MAX" -eq 0 ]]; then
  echo "El dispositivo de retroiluminación no admite cambios." >&2
  exit 1
fi

case "$1" in
  up)   NEW=$((CURRENT + STEP)) ;;
  down) NEW=$((CURRENT - STEP)) ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < 0 ))   && NEW=0

echo "$NEW" | tee "$DEVICE/brightness" > /dev/null

PERCENT=$(( NEW * 100 / MAX ))
notify-send -t 800 "⌨️ Brillo teclado" "${PERCENT}%"
