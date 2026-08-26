#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_extend_auto_linux.sh
# Extiende el escritorio al monitor externo (a la derecha).
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
  xrandr --output "$INTERNAL" --auto --primary
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
