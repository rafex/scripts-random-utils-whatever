#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_power_linux.sh
# Monitoriza cambios de estado de energía (AC/batería) y notifica.
# Se ejecuta como daemon: bloquea escuchando eventos de UPower.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if ! command -v upower >/dev/null 2>&1; then
  echo "ERROR: upower no está instalado." >&2
  exit 1
fi

if [[ -n "${POWER_DEVICE:-}" ]]; then
  DEVICE="$POWER_DEVICE"
else
  DEVICE="$(upower -e 2>/dev/null | awk '/line_power_/ {print; exit}')"
fi

if [[ -z "$DEVICE" ]]; then
  echo "No se encontró un dispositivo de alimentación AC en UPower." >&2
  exit 0
fi

notify_state() {
  local online
  online="$(upower -i "$DEVICE" 2>/dev/null | awk '/online:/ {print $2; exit}')"
  if [[ "$online" == "yes" ]]; then
    notify-send -u low -t 3000 "🔌 Energía" "Cargando"
  elif [[ "$online" == "no" ]]; then
    notify-send -u low -t 3000 "🔋 Energía" "Usando batería"
  fi
}

upower -m | while read -r line; do
  if [[ "$line" == *"$DEVICE"* || "$line" == *"line_power_"* ]]; then
    notify_state
  fi
done
