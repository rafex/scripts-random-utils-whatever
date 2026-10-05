#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# notify_brightness_linux.sh v1.2.1
# Ajusta el backlight con brightnessctl y extiende el rango con xrandr.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STEP="${BRIGHTNESS_STEP:-5}"
if [[ ! "$STEP" =~ ^[0-9]+$ ]]; then
  echo "BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi
STEP=$((10#$STEP))
if (( STEP < 1 )); then
  echo "BRIGHTNESS_STEP debe ser un entero positivo." >&2
  exit 1
fi

XRANDR_STEP="${XRANDR_BRIGHTNESS_STEP:-0.05}"
XRANDR_BASE="${XRANDR_BRIGHTNESS_BASE:-1.1}"
XRANDR_MAX=2.0
XRANDR_OUTPUT="${XRANDR_BRIGHTNESS_OUTPUT:-}"
XRANDR_STATUS=''
XRANDR_ERROR=''
if [[ ! "$XRANDR_STEP" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v step="$XRANDR_STEP" 'BEGIN { exit !(step > 0 && step <= 1) }'; then
  echo "XRANDR_BRIGHTNESS_STEP debe ser un número mayor que 0 y máximo 1.0." >&2
  exit 1
fi
if [[ ! "$XRANDR_BASE" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v base="$XRANDR_BASE" 'BEGIN { exit !(base >= 0.1 && base < 2.0) }'; then
  echo "XRANDR_BRIGHTNESS_BASE debe estar entre 0.1 y menos de 2.0." >&2
  exit 1
fi

usage() {
  echo "Uso: $0 [up|down]"
  exit 1
}

fail() {
  local message="$1"
  echo "$message" >&2
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Brillo" "$message" || true
  fi
  exit 1
}

read_xrandr_state() {
  local query verbose
  if ! command -v xrandr >/dev/null 2>&1; then
    XRANDR_ERROR='no se encontró el comando xrandr'
    return 1
  fi
  if ! query="$(xrandr --query 2>&1)"; then
    XRANDR_ERROR="xrandr no pudo consultar DISPLAY=${DISPLAY:-no definido}: ${query:-sin detalle}; XAUTHORITY=${XAUTHORITY:-no definida}"
    return 1
  fi
  if [[ -z "$XRANDR_OUTPUT" ]]; then
    XRANDR_OUTPUT="$(awk '$1 ~ /^(eDP|LVDS|DSI)-/ && $2 == "connected" { print $1; exit }' <<< "$query")"
  fi
  if [[ -z "$XRANDR_OUTPUT" ]]; then
    XRANDR_ERROR="no se detectó una salida interna conectada en DISPLAY=${DISPLAY:-no definido}"
    return 1
  fi
  if ! verbose="$(xrandr --verbose 2>&1)"; then
    XRANDR_ERROR="xrandr no pudo leer la salida ${XRANDR_OUTPUT}: ${verbose:-sin detalle}; DISPLAY=${DISPLAY:-no definido}"
    return 1
  fi
  XRANDR_CURRENT="$(awk -v output="$XRANDR_OUTPUT" '
    $1 == output { found=1; next }
    found && $2 == "connected" { found=0 }
    found && $1 == "Brightness:" { print $2; exit }
  ' <<< "$verbose")"
  if [[ ! "$XRANDR_CURRENT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    XRANDR_ERROR="xrandr no reportó la propiedad Brightness para ${XRANDR_OUTPUT}; comprueba XRANDR_BRIGHTNESS_OUTPUT y la salida de xrandr --verbose"
    return 1
  fi
}

adjust_xrandr() {
  local direction="$1" target
  read_xrandr_state || fail "No se pudo leer el brillo xrandr: ${XRANDR_ERROR}"
  target="$(awk -v current="$XRANDR_CURRENT" -v step="$XRANDR_STEP" \
    -v base="$XRANDR_BASE" -v maximum="$XRANDR_MAX" -v direction="$direction" '
    BEGIN {
      if (direction == "up") {
        target_value = (current >= maximum ? current : current + step)
        if (target_value > maximum) target_value = maximum
      } else {
        target_value = current - step
        if (target_value < base) target_value = base
      }
      printf "%.2f", target_value
    }
  ')"
  xrandr --output "$XRANDR_OUTPUT" --brightness "$target" ||
    fail "No se pudo aplicar el brillo xrandr ${target} a ${XRANDR_OUTPUT}."
  XRANDR_STATUS="xrandr ${target}×"
}

case "${1:-}" in
  up|down) ACTION="$1" ;;
  *) usage ;;
esac

BRIGHTNESS="$(brightnessctl get)"
MAX="$(brightnessctl max)"
if [[ ! "$BRIGHTNESS" =~ ^[0-9]+$ || ! "$MAX" =~ ^[0-9]+$ || "$MAX" -eq 0 ]]; then
  echo "brightnessctl devolvió niveles inválidos: actual=$BRIGHTNESS máximo=$MAX" >&2
  exit 1
fi

PERCENT=$(((BRIGHTNESS * 100 + MAX / 2) / MAX))
(( PERCENT <= 100 )) || PERCENT=100

if [[ "$ACTION" == up ]]; then
  if (( PERCENT >= 100 )); then
    adjust_xrandr up
  elif (( PERCENT <= 20 )); then
    ACTION_STEP=2
    brightnessctl set "+${ACTION_STEP}%" >/dev/null
  else
    ACTION_STEP="$STEP"
    brightnessctl set "+${ACTION_STEP}%" >/dev/null
  fi
else
  if read_xrandr_state && awk -v current="$XRANDR_CURRENT" -v base="$XRANDR_BASE" 'BEGIN { exit !(current > base + 0.0001) }'; then
    adjust_xrandr down
  else
    if (( PERCENT <= 20 )); then
      ACTION_STEP=1
      brightnessctl set "${ACTION_STEP}%-" >/dev/null
    elif (( PERCENT - STEP < 20 )); then
      brightnessctl set 20% >/dev/null
    else
      ACTION_STEP="$STEP"
      brightnessctl set "${ACTION_STEP}%-" >/dev/null
    fi
  fi
fi

if [[ -z "$XRANDR_STATUS" ]]; then
  BRIGHTNESS="$(brightnessctl get)"
  PERCENT=$(((BRIGHTNESS * 100 + MAX / 2) / MAX))
  (( PERCENT <= 100 )) || PERCENT=100
else
  PERCENT=100
fi
BAR=''
for ((index = 0; index < PERCENT / 5; index++)); do
  BAR+='█'
done

if command -v notify-send >/dev/null 2>&1; then
  DETAILS="${BAR} ${PERCENT}%"
  [[ -z "$XRANDR_STATUS" ]] || DETAILS+=" · ${XRANDR_STATUS}"
  notify-send -t 800 "💡 Brillo" "$DETAILS"
fi
