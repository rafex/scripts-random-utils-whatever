#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_auto_edge_mirror_linux.sh
# Duplica pantalla ajustando el externo al modo del panel interno.
# Si el externo no está conectado, vuelve a solo laptop.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INTERNAL="${SCREEN_INTERNAL:-LVDS1}"
EXTERNAL="${SCREEN_EXTERNAL:-HDMI1}"

if ! xrandr | grep -q "^${EXTERNAL} connected"; then
  xrandr --output "$EXTERNAL" --off --output "$INTERNAL" --auto
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
