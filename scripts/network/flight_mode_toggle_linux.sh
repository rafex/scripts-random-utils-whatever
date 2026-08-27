#!/usr/bin/env bash
# shellcheck shell=bash
# Alterna Wi‑Fi, WWAN y Bluetooth como modo avión, sin usar sudo.
set -Eeuo pipefail

command -v nmcli >/dev/null 2>&1 || {
  echo "No se encontró nmcli; instala NetworkManager." >&2
  exit 1
}

usage() { echo "Uso: $0 [toggle|on|off]"; }

wifi_state="$(nmcli -t -f WIFI radio 2>/dev/null | tail -n 1)"
wwan_state="$(nmcli -t -f WWAN radio 2>/dev/null | tail -n 1 || true)"
bluetooth_state="unknown"
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetooth_state="$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')"
fi

case "${1:-toggle}" in
  on) target=on ;;
  off) target=off ;;
  toggle)
    if [[ "$wifi_state" == enabled || "$wwan_state" == enabled || "$bluetooth_state" == "yes" ]]; then
      target=off
    else
      target=on
    fi
    ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

if [[ "$target" == on ]]; then
  nmcli radio wifi on
  nmcli radio wwan on 2>/dev/null || true
  if command -v bluetoothctl >/dev/null 2>&1; then bluetoothctl power on >/dev/null 2>&1 || true; fi
  MESSAGE="Activado"
else
  nmcli radio wifi off
  nmcli radio wwan off 2>/dev/null || true
  if command -v bluetoothctl >/dev/null 2>&1; then bluetoothctl power off >/dev/null 2>&1 || true; fi
  MESSAGE="Desactivado"
fi

notify-send -t 1400 -i airplane-mode \
  -h string:x-canonical-private-synchronous:flight-mode "Modo avión" "$MESSAGE"
