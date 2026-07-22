#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_power_linux.sh
# Monitoriza cambios de estado de energía (AC/batería) y notifica.
# Se ejecuta como daemon: bloquea escuchando eventos de UPower.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DEVICE="${POWER_DEVICE:-/org/freedesktop/UPower/devices/line_power_ADP1}"

upower -m | while read -r line; do
  if echo "$line" | grep -q "$DEVICE"; then
    ONLINE=$(upower -i "$DEVICE" | awk '/online:/ {print $2}')
    if [[ "$ONLINE" == "yes" ]]; then
      notify-send -u low -t 3000 "🔌 Energía" "Cargando"
    else
      notify-send -u low -t 3000 "🔋 Energía" "Usando batería"
    fi
  fi
done
