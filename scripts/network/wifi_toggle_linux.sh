#!/usr/bin/env bash
# shellcheck shell=bash
# Alterna el radio Wi‑Fi completo sin requerir sudo ni conocer la interfaz.
set -Eeuo pipefail

command -v nmcli >/dev/null 2>&1 || {
  echo "No se encontró nmcli; instala NetworkManager." >&2
  exit 1
}

STATE="$(nmcli -t -f WIFI radio 2>/dev/null | tail -n 1)"
case "${1:-toggle}" in
  on)  nmcli radio wifi on; MESSAGE="Activado" ;;
  off) nmcli radio wifi off; MESSAGE="Desactivado" ;;
  toggle)
    if [[ "$STATE" == enabled ]]; then
      nmcli radio wifi off
      MESSAGE="Desactivado"
    else
      nmcli radio wifi on
      MESSAGE="Activado"
    fi
    ;;
  -h|--help)
    echo "Uso: $0 [toggle|on|off]"
    exit 0
    ;;
  *) echo "Uso: $0 [toggle|on|off]" >&2; exit 1 ;;
esac

FINAL_STATE="$(nmcli -t -f WIFI radio 2>/dev/null | tail -n 1)"
if [[ "$FINAL_STATE" == enabled ]]; then
  ICON="network-wireless"
  VALUE=100
  MESSAGE="Activado"
else
  ICON="network-wireless-disabled"
  VALUE=0
  MESSAGE="Desactivado"
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -u normal -t 1200 -i "$ICON" \
    -h int:value:"$VALUE" \
    -h string:x-canonical-private-synchronous:wifi \
    "Wi‑Fi" "$MESSAGE"
else
  printf 'Wi‑Fi: %s\n' "$MESSAGE"
fi
