#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_auto_edge_mirror_linux.sh
# Duplica pantalla ajustando el externo al modo del panel interno.
# Si el externo no está conectado, vuelve a solo laptop.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

connected_outputs() { xrandr --query | awk '$2 == "connected" {print $1}'; }

INTERNAL="${SCREEN_INTERNAL:-$(connected_outputs | awk '/^(eDP|LVDS|DSI)-/ {print; exit}')}"
[[ -n "$INTERNAL" ]] || INTERNAL="$(connected_outputs | head -n1)"
EXTERNAL="${SCREEN_EXTERNAL:-$(connected_outputs | awk -v internal="$INTERNAL" '$0 != internal && $0 ~ /^(HDMI|DP|DVI|VGA)-/ {print; exit}')}"
[[ -n "$INTERNAL" ]] || { echo "No se detectó una salida interna." >&2; exit 1; }

if [[ -z "$EXTERNAL" ]] || ! xrandr | grep -q "^${EXTERNAL} connected"; then
  if [[ -n "$EXTERNAL" ]]; then xrandr --output "$EXTERNAL" --off; fi
  xrandr --output "$INTERNAL" --auto
  notify-send "Pantalla" "Solo laptop (${INTERNAL})"
  exit 0
fi

INTERNAL_MODE="$(xrandr | awk -v out="$INTERNAL" '
  $1==out {found=1}
  found && $0 ~ /\*/ {print $1; exit}
')"

: "${INTERNAL_MODE:=auto}"

xrandr \
  --output "$INTERNAL" --auto \
  --output "$EXTERNAL" --mode "$INTERNAL_MODE" --same-as "$INTERNAL"

notify-send "Pantalla" "Duplicando (${EXTERNAL}) a ${INTERNAL_MODE}"
