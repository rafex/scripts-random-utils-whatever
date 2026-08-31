#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_kbd_brightness_linux.sh
# Ajusta el brillo del teclado retroiluminado y muestra una notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

case "${1:-}" in
  up|down) ;;
  *) usage ;;
esac

find_backlight_device() {
  if [[ -n "${KBD_BACKLIGHT_DEVICE:-}" ]]; then
    printf '%s\n' "$KBD_BACKLIGHT_DEVICE"
    return 0
  fi

  local candidate
  shopt -s nullglob
  for candidate in \
    /sys/class/leds/tpacpi::kbd_backlight \
    /sys/class/leds/*kbd_backlight \
    /sys/class/leds/*keyboard*; do
    if [[ -f "$candidate/brightness" && -f "$candidate/max_brightness" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if ! DEVICE="$(find_backlight_device)"; then
  echo "No se encontró retroiluminación de teclado (tpacpi::kbd_backlight u otro LED compatible)." >&2
  exit 1
fi

if [[ ! -f "$DEVICE/brightness" || ! -f "$DEVICE/max_brightness" ]]; then
  echo "El dispositivo de teclado no expone brightness/max_brightness: $DEVICE" >&2
  exit 1
fi

DEVICE_NAME="${DEVICE##*/}"
BACKEND=sysfs
CURRENT=''
MAX=''

if command -v brightnessctl >/dev/null 2>&1 \
  && CURRENT="$(brightnessctl --device "$DEVICE_NAME" get 2>/dev/null)" \
  && MAX="$(brightnessctl --device "$DEVICE_NAME" max 2>/dev/null)"; then
  BACKEND=brightnessctl
else
  CURRENT="$(<"$DEVICE/brightness")"
  MAX="$(<"$DEVICE/max_brightness")"
fi

if [[ ! "$CURRENT" =~ ^[0-9]+$ || ! "$MAX" =~ ^[0-9]+$ ]]; then
  echo "El dispositivo de teclado devolvió niveles inválidos: actual=$CURRENT máximo=$MAX" >&2
  exit 1
fi
if (( MAX == 0 )); then
  echo "El dispositivo de retroiluminación no admite cambios." >&2
  exit 1
fi

STEP="${KBD_BRIGHTNESS_STEP:-20}"
if [[ ! "$STEP" =~ ^[0-9]+$ || "$STEP" -lt 1 ]]; then
  echo "KBD_BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi
if [[ -z "${KBD_BRIGHTNESS_STEP:-}" && "$MAX" -le 10 ]]; then
  STEP=1
fi

if [[ "$1" == up ]]; then
  NEW=$((CURRENT + STEP))
else
  NEW=$((CURRENT - STEP))
fi
(( NEW > MAX )) && NEW=$MAX
(( NEW < 0 )) && NEW=0

if [[ "$BACKEND" == brightnessctl ]]; then
  brightnessctl --device "$DEVICE_NAME" set "$NEW" >/dev/null
else
  if [[ ! -w "$DEVICE/brightness" ]]; then
    echo "No hay permisos de usuario para modificar $DEVICE/brightness; no se usará sudo." >&2
    exit 1
  fi
  printf '%s\n' "$NEW" > "$DEVICE/brightness"
fi

PERCENT=$((NEW * 100 / MAX))
if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 800 "⌨️ Brillo teclado" "${PERCENT}%"
fi
