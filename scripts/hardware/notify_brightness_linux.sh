#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_brightness_linux.sh
# Ajusta el brillo de pantalla con brightnessctl y muestra una notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STEP="${BRIGHTNESS_STEP:-5}"
if [[ ! "$STEP" =~ ^[0-9]+$ || "$STEP" -lt 1 ]]; then
  echo "BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

case "${1:-}" in
  up) brightnessctl set "+${STEP}%" >/dev/null ;;
  down) brightnessctl set "${STEP}%-" >/dev/null ;;
  *) usage ;;
esac

BRIGHTNESS="$(brightnessctl get)"
MAX="$(brightnessctl max)"
if [[ ! "$BRIGHTNESS" =~ ^[0-9]+$ || ! "$MAX" =~ ^[0-9]+$ || "$MAX" -eq 0 ]]; then
  echo "brightnessctl devolvió niveles inválidos: actual=$BRIGHTNESS máximo=$MAX" >&2
  exit 1
fi

PERCENT=$((BRIGHTNESS * 100 / MAX))
BAR=''
for ((index = 0; index < PERCENT / 5; index++)); do
  BAR+='█'
done

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 800 "💡 Brillo" "${BAR} ${PERCENT}%"
fi
