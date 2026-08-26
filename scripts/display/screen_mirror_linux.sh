#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_mirror_linux.sh
# Duplica la pantalla interna en el monitor externo detectados por xrandr.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

connected_outputs() { xrandr --query | awk '$2 == "connected" {print $1}'; }
INTERNAL="${SCREEN_INTERNAL:-$(connected_outputs | awk '/^(eDP|LVDS|DSI)-/ {print; exit}')}"
[[ -n "$INTERNAL" ]] || INTERNAL="$(connected_outputs | head -n1)"
EXTERNAL="${SCREEN_EXTERNAL:-$(connected_outputs | awk -v internal="$INTERNAL" '$0 != internal && $0 ~ /^(HDMI|DP|DVI|VGA)-/ {print; exit}')}"

[[ -n "$INTERNAL" ]] || { echo "No se detectó una salida interna." >&2; exit 1; }
[[ -n "$EXTERNAL" ]] || { echo "No se detectó un monitor externo." >&2; exit 1; }

xrandr \
  --output "$INTERNAL" --same-as "$EXTERNAL" --auto \
  --output "$EXTERNAL" --auto
