#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_auto_mirror_linux.sh
# Duplica pantalla si hay monitor externo conectado; si no, vuelve a solo laptop.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

connected_outputs() { xrandr --query | awk '$2 == "connected" {print $1}'; }

INTERNAL="${SCREEN_INTERNAL:-$(connected_outputs | awk '/^(eDP|LVDS|DSI)-/ {print; exit}')}"
if [[ -z "$INTERNAL" ]]; then
  INTERNAL="$(connected_outputs | head -n1)"
fi
EXTERNAL="${SCREEN_EXTERNAL:-$(connected_outputs | awk -v internal="$INTERNAL" '$0 != internal && $0 ~ /^(HDMI|DP|DVI|VGA)-/ {print; exit}')}"

[[ -n "$INTERNAL" ]] || { echo "No se detectó una salida interna." >&2; exit 1; }

if [[ -n "$EXTERNAL" ]] && xrandr | grep -q "^${EXTERNAL} connected"; then
  xrandr \
    --output "$EXTERNAL" --same-as "$INTERNAL" --auto \
    --output "$INTERNAL" --auto
  notify-send "Pantalla" "Duplicando (${EXTERNAL})"
else
  if [[ -n "$EXTERNAL" ]]; then
    xrandr --output "$EXTERNAL" --off --output "$INTERNAL" --auto
  else
    xrandr --output "$INTERNAL" --auto
  fi
  notify-send "Pantalla" "Solo laptop (${INTERNAL})"
fi
