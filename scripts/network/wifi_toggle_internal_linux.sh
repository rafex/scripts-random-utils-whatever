#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# wifi_toggle_internal_linux.sh
# Activa/desactiva la gestión de la interfaz WiFi interna wlp2s0.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IFACE="${WIFI_TOGGLE_IFACE:-wlp2s0}"
STATE="$(nmcli -t -f DEVICE,STATE device | awk -F: -v dev="$IFACE" '$1==dev{print $2}')"

case "$STATE" in
  unmanaged)
    nmcli device set "$IFACE" managed yes
    notify-send -t 1200 "📶 Wi-Fi interno" "Encendido (managed=yes)"
    ;;
  *)
    nmcli device set "$IFACE" managed no
    notify-send -t 1200 "📶 Wi-Fi interno" "Apagado (managed=no)"
    ;;
esac
