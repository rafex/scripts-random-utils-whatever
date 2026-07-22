#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wifi_toggle_internal_linux.sh
# Activa/desactiva la gestión de la interfaz WiFi interna.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IFACE="${WIFI_TOGGLE_IFACE:-wlp2s0}"

notify() {
    local title="$1" msg="$2"
    if command -v notify-send &>/dev/null; then
        notify-send -t 1200 "$title" "$msg"
    else
        echo -e "  \033[0;32m✓\033[0m $title — $msg"
    fi
}

STATE="$(nmcli -t -f DEVICE,STATE device | awk -F: -v dev="$IFACE" '$1==dev{print $2}')"

if [[ -z "$STATE" ]]; then
    echo -e "\033[0;31m  ✗ ERROR:\033[0m interfaz \033[1m${IFACE}\033[0m no encontrada en NetworkManager." >&2
    echo "  Interfaces WiFi disponibles:"
    nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2=="wifi"{printf "    %s (%s)\n", $1, $3}'
    exit 1
fi

case "$STATE" in
  unmanaged)
    nmcli device set "$IFACE" managed yes
    notify "📶 Wi-Fi interno" "Encendido (managed=yes)"
    ;;
  *)
    nmcli device set "$IFACE" managed no
    notify "📶 Wi-Fi interno" "Apagado (managed=no)"
    ;;
esac
