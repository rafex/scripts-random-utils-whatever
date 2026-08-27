#!/usr/bin/env bash
# shellcheck shell=bash
# Ajusta el volumen usando wpctl (PipeWire) y pactl como fallback.
set -euo pipefail

STEP="${VOLUME_STEP:-5}"
SINK="${VOLUME_SINK:-@DEFAULT_AUDIO_SINK@}"

usage() {
  echo "Uso: $0 [up|down|mute]"
  exit 1
}

if command -v wpctl >/dev/null 2>&1; then
  case "${1:-}" in
    up)   wpctl set-volume "$SINK" "${STEP}%+" ;;
    down) wpctl set-volume "$SINK" "${STEP}%-" ;;
    mute) wpctl set-mute "$SINK" toggle ;;
    *)    usage ;;
  esac
  STATUS="$(wpctl get-volume "$SINK")"
  VOLUME="$(awk '{printf "%d%%", ($2 * 100) + 0.5}' <<<"$STATUS")"
  MUTE="$(grep -q '\[MUTED\]' <<<"$STATUS" && echo yes || echo no)"
elif command -v pactl >/dev/null 2>&1; then
  case "${1:-}" in
    up)   pactl set-sink-volume @DEFAULT_SINK@ "+${STEP}%" ;;
    down) pactl set-sink-volume @DEFAULT_SINK@ "-${STEP}%" ;;
    mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
    *)    usage ;;
  esac
  VOLUME="$(pactl get-sink-volume @DEFAULT_SINK@ | awk 'NR==1 {print $5}')"
  MUTE="$(pactl get-sink-mute @DEFAULT_SINK@ | awk 'NR==1 {print $2}')"
else
  echo "No se encontró wpctl ni pactl; instala PipeWire/PulseAudio." >&2
  exit 1
fi

if [[ "$MUTE" == "yes" ]]; then
  notify-send -t 1000 -i audio-volume-muted \
    -h string:x-canonical-private-synchronous:volume "Volumen" "Silenciado"
else
  notify-send -t 1000 -i audio-volume-high \
    -h int:value:"${VOLUME%%%}" \
    -h string:x-canonical-private-synchronous:volume "Volumen" "$VOLUME"
fi
