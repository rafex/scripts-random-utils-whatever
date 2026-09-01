#!/usr/bin/env bash
# v1.0.0 - Helper Polkit restringido al LED del teclado ThinkPad.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

readonly DEVICE='/sys/class/leds/tpacpi::kbd_backlight'

die() {
  printf 'rafex-kbd-backlight: %s\n' "$*" >&2
  exit 1
}

[[ "$EUID" -eq 0 ]] || die 'este helper debe ejecutarse mediante Polkit'
[[ "$#" -eq 1 ]] || die 'uso: rafex-kbd-backlight up|down'
case "$1" in
  up|down) ;;
  *) die 'operación no permitida; solo se acepta up o down' ;;
esac

[[ -f "$DEVICE/brightness" && -f "$DEVICE/max_brightness" ]] ||
  die 'no existe el LED tpacpi::kbd_backlight'

current="$(<"$DEVICE/brightness")"
max="$(<"$DEVICE/max_brightness")"
[[ "$current" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && "$max" -gt 0 ]] ||
  die 'el dispositivo devolvió niveles inválidos'

if [[ "$1" == up ]]; then
  new=$((current + 1))
else
  new=$((current - 1))
fi
if (( new > max )); then new=$max; fi
if (( new < 0 )); then new=0; fi

printf '%s\n' "$new" > "$DEVICE/brightness"
