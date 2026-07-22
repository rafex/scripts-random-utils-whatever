#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_brightness_linux.sh
# Ajusta el brillo de pantalla con brightnessctl y muestra notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STEP="${BRIGHTNESS_STEP:-5}"

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

case "${1:-}" in
  up)   brightnessctl set +${STEP}% ;;
  down) brightnessctl set ${STEP}%- ;;
  *)    usage ;;
esac

BRIGHTNESS=$(brightnessctl get)
MAX=$(brightnessctl max)
PERCENT=$(( BRIGHTNESS * 100 / MAX ))

BAR=$(printf "%0.s█" $(seq 1 $((PERCENT / 5))))
notify-send -t 800 "💡 Brillo" "$BAR ${PERCENT}%"
