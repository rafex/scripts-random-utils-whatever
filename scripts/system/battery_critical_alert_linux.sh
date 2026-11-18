#!/usr/bin/env bash
# v1.0.0
set -euo pipefail

for battery in /sys/class/power_supply/BAT*; do
  [[ -r "$battery/capacity" && -r "$battery/status" ]] || continue
  read -r status < "$battery/status" || continue
  [[ "$status" == Discharging ]] || continue
  read -r capacity < "$battery/capacity" || continue
  [[ "$capacity" =~ ^[0-9]{1,3}$ ]] || continue
  (( 10#$capacity <= 10 )) || continue

  notify-send --app-name='Batería' --urgency=critical --expire-time=0 \
    --icon=battery-caution --hint=string:x-dunst-stack-tag:rafex-battery-critical \
    "Batería crítica: ${capacity} %" 'Conecta el cargador ahora para evitar que se apague el equipo.'
  break
done
