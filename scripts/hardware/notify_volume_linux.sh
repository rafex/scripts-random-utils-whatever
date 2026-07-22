#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_volume_linux.sh
# Ajusta el volumen con pactl (PipeWire/PulseAudio) y muestra notificación.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STEP="${VOLUME_STEP:-5}"

usage() {
  echo "Uso: $0 [up|down|mute]"
  exit 1
}

case "${1:-}" in
  up)   pactl set-sink-volume @DEFAULT_SINK@ +${STEP}% ;;
  down) pactl set-sink-volume @DEFAULT_SINK@ -${STEP}% ;;
  mute) pactl set-sink-mute   @DEFAULT_SINK@ toggle ;;
  *)    usage ;;
esac

VOLUME=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}' | head -n1)
MUTE=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')

if [[ "$MUTE" == "yes" ]]; then
  notify-send -t 800 "🔇 Volumen" "Mute"
else
  notify-send -t 800 "🔊 Volumen" "$VOLUME"
fi
