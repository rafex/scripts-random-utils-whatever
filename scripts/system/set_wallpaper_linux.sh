#!/usr/bin/env bash
# set_wallpaper_linux.sh v1.0.0
# Aplica el fondo administrado del perfil ThinkPad sin crear un proceso persistente.
set -Eeuo pipefail
umask 077

export LC_ALL=C

PROFILE_WALLPAPER="${HOME}/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/rafex-thinkpad-desktop.png"
FALLBACK_DIR="${HOME}/Imágenes/FondosDePantalla"

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

command -v feh >/dev/null 2>&1 || die 'feh no está instalado'

wallpaper="$PROFILE_WALLPAPER"
if [[ ! -s "$wallpaper" ]]; then
  for candidate in "$FALLBACK_DIR/wallpaper.jpg" "$FALLBACK_DIR/wallpaper.png"; do
    if [[ -s "$candidate" ]]; then
      wallpaper="$candidate"
      break
    fi
  done
fi

[[ -s "$wallpaper" ]] || die 'no se encontró un fondo del perfil ThinkPad'
exec feh --no-fehbg --bg-scale -- "$wallpaper"
