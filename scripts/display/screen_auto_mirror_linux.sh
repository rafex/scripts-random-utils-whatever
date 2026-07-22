#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_auto_mirror_linux.sh
# Duplica pantalla si hay monitor externo conectado; si no, vuelve a solo laptop.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INTERNAL="${SCREEN_INTERNAL:-LVDS1}"
EXTERNAL="${SCREEN_EXTERNAL:-HDMI1}"

if xrandr | grep -q "^${EXTERNAL} connected"; then
  xrandr \
    --output "$EXTERNAL" --same-as "$INTERNAL" --auto \
    --output "$INTERNAL" --auto
  notify-send "Pantalla" "Duplicando (${EXTERNAL})"
else
  xrandr \
    --output "$EXTERNAL" --off \
    --output "$INTERNAL" --auto
  notify-send "Pantalla" "Solo laptop (${INTERNAL})"
fi
