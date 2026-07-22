#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_extend_auto_linux.sh
# Extiende el escritorio al monitor externo (a la derecha).
# Si el externo no está conectado, vuelve a solo laptop.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INTERNAL="${SCREEN_INTERNAL:-LVDS1}"
EXTERNAL="${SCREEN_EXTERNAL:-HDMI1}"

if ! xrandr | grep -q "^${EXTERNAL} connected"; then
  xrandr --output "$EXTERNAL" --off --output "$INTERNAL" --auto --primary
  notify-send "Pantalla" "Solo laptop (${INTERNAL})"
  exit 0
fi

INTERNAL_MODE="$(xrandr | awk -v out="$INTERNAL" '
  $1==out {found=1}
  found && $0 ~ /\*/ {print $1; exit}
')"

EXTERNAL_MODE="$(xrandr | awk -v out="$EXTERNAL" '
  $1==out {found=1}
  found && $0 ~ /\+/ {print $1; exit}
')"
if [[ -z "$EXTERNAL_MODE" ]]; then
  EXTERNAL_MODE="$(xrandr | awk -v out="$EXTERNAL" '
    $1==out {found=1}
    found && $1 ~ /^[0-9]+x[0-9]+$/ {print $1; exit}
  ')"
fi

: "${INTERNAL_MODE:=auto}"
: "${EXTERNAL_MODE:=auto}"

xrandr \
  --output "$INTERNAL" --mode "$INTERNAL_MODE" --primary --pos 0x0 --rotate normal \
  --output "$EXTERNAL" --mode "$EXTERNAL_MODE" --right-of "$INTERNAL" --rotate normal

notify-send "Pantalla" "Extendido: ${INTERNAL} (${INTERNAL_MODE}) + ${EXTERNAL} (${EXTERNAL_MODE})"
