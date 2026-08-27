#!/usr/bin/env bash
# shellcheck shell=bash
# Alterna el mute de la fuente de audio predeterminada mediante PipeWire.
set -Eeuo pipefail

SOURCE="${MICROPHONE_SOURCE:-@DEFAULT_AUDIO_SOURCE@}"
STEP="${MICROPHONE_STEP:-toggle}"

usage() {
  cat <<'EOF'
Uso: notify_microphone_linux.sh [toggle|mute|unmute]

Variables:
  MICROPHONE_SOURCE  Fuente de audio para wpctl (default: @DEFAULT_AUDIO_SOURCE@)
EOF
}

command -v wpctl >/dev/null 2>&1 || {
  echo "No se encontró wpctl; instala PipeWire/WirePlumber." >&2
  exit 1
}

case "${1:-$STEP}" in
  toggle) wpctl set-mute "$SOURCE" toggle ;;
  mute) wpctl set-mute "$SOURCE" 1 ;;
  unmute) wpctl set-mute "$SOURCE" 0 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

STATUS="$(wpctl get-volume "$SOURCE")"
if grep -q '\[MUTED\]' <<<"$STATUS"; then
  notify-send -t 1200 -i microphone-sensitivity-muted \
    -h string:x-canonical-private-synchronous:microphone \
    "Micrófono" "Silenciado"
else
  notify-send -t 1200 -i microphone-sensitivity-high \
    -h string:x-canonical-private-synchronous:microphone \
    "Micrófono" "Activo"
fi
