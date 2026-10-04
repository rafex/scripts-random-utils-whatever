#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_brightness_linux.sh v1.1.0
# Ajusta el brillo de pantalla con brightnessctl y muestra una notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STEP="${BRIGHTNESS_STEP:-5}"
if [[ ! "$STEP" =~ ^[0-9]+$ ]]; then
  echo "BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi
STEP=$((10#$STEP))
if (( STEP < 1 )); then
  echo "BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

case "${1:-}" in
  up|down) ACTION="$1" ;;
  *) usage ;;
esac

BRIGHTNESS="$(brightnessctl get)"
MAX="$(brightnessctl max)"
if [[ ! "$BRIGHTNESS" =~ ^[0-9]+$ || ! "$MAX" =~ ^[0-9]+$ || "$MAX" -eq 0 ]]; then
  echo "brightnessctl devolvió niveles inválidos: actual=$BRIGHTNESS máximo=$MAX" >&2
  exit 1
fi

PERCENT=$(((BRIGHTNESS * 100 + MAX / 2) / MAX))
(( PERCENT <= 100 )) || PERCENT=100

if [[ "$ACTION" == up ]]; then
  if (( PERCENT <= 20 )); then
    ACTION_STEP=2
  else
    ACTION_STEP="$STEP"
  fi
  brightnessctl set "+${ACTION_STEP}%" >/dev/null
else
  if (( PERCENT <= 20 )); then
    ACTION_STEP=1
    brightnessctl set "${ACTION_STEP}%-" >/dev/null
  elif (( PERCENT - STEP < 20 )); then
    brightnessctl set 20% >/dev/null
  else
    ACTION_STEP="$STEP"
    brightnessctl set "${ACTION_STEP}%-" >/dev/null
  fi
fi

BRIGHTNESS="$(brightnessctl get)"
PERCENT=$(((BRIGHTNESS * 100 + MAX / 2) / MAX))
(( PERCENT <= 100 )) || PERCENT=100
BAR=''
for ((index = 0; index < PERCENT / 5; index++)); do
  BAR+='█'
done

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 800 "💡 Brillo" "${BAR} ${PERCENT}%"
fi
