#!/usr/bin/env bash
# lock_screen_linux.sh v1.2.0
# Bloqueo con i3lock-color en modo sólido, imagen ajustada o desenfoque.
set -Eeuo pipefail
umask 077
export LC_ALL=C

MODE=image
PROFILE_IMAGE="$HOME/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/rafex-thinkpad-login.png"

usage() { printf 'Uso: lock_screen_linux.sh --mode solid|image|blur | --status\n'; }
while (($#)); do
  case "$1" in
    --mode) (($# >= 2)) || { printf '✗ ERROR: --mode requiere un valor\n' >&2; exit 2; }; MODE="$2"; shift;;
    --status) MODE=status;;
    --help|-h) usage; exit 0;;
    *) printf '✗ ERROR: opción desconocida: %s\n' "$1" >&2; exit 2;;
  esac
  shift
done

LOCKER="${I3LOCK_COLOR_BIN:-$HOME/.local/bin/i3lock-color}"
if [[ "$MODE" == status ]]; then
  printf '═══ Bloqueo Rafex ═══\n'
  [[ -x "$LOCKER" ]] && printf '✓ i3lock-color disponible: %s\n' "$LOCKER" || printf '⚠ i3lock-color ausente; i3lock oficial sigue disponible\n'
  command -v i3lock >/dev/null 2>&1 && printf '✓ i3lock oficial: %s\n' "$(command -v i3lock)" || printf '⚠ i3lock oficial ausente\n'
  exit 0
fi

[[ -x "$LOCKER" ]] || { printf '✗ ERROR: instala i3lock-color con just install-i3lock-color --apply\n' >&2; exit 1; }
[[ -n "${DISPLAY:-}" ]] || { printf '✗ ERROR: DISPLAY ausente; ejecuta el bloqueo desde X11\n' >&2; exit 1; }

display_geometry() {
  local geometry
  command -v xdpyinfo >/dev/null 2>&1 \
    || { printf '✗ ERROR: image requiere xdpyinfo (paquete x11-utils)\n' >&2; exit 1; }
  geometry="$(xdpyinfo 2>/dev/null | awk '$1 == "dimensions:" {print $2; exit}')"
  [[ "$geometry" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] \
    || { printf '✗ ERROR: no se pudo detectar el tamaño de la pantalla X11\n' >&2; exit 1; }
  printf '%s\n' "$geometry"
}

temporary_directory() {
  local runtime="${XDG_RUNTIME_DIR:-/tmp}"
  [[ -d "$runtime" && -w "$runtime" ]] \
    || { printf '✗ ERROR: no se puede usar el directorio temporal\n' >&2; exit 1; }
  mktemp -d "$runtime/rafex-lock.XXXXXX"
}

case "$MODE" in
  solid) exec "$LOCKER" --nofork --color 2e3440;;
  image)
    [[ -s "$PROFILE_IMAGE" ]] || { printf '✗ ERROR: falta la imagen del perfil: %s\n' "$PROFILE_IMAGE" >&2; exit 1; }
    command -v convert >/dev/null 2>&1 \
      || { printf '✗ ERROR: image requiere ImageMagick (convert)\n' >&2; exit 1; }
    temp_dir="$(temporary_directory)"
    trap 'rm -rf -- "$temp_dir"' EXIT HUP INT TERM
    geometry="$(display_geometry)"
    # Cubre toda la pantalla conservando la proporción; solo recorta los
    # bordes sobrantes, como un fondo de pantalla en modo cover.
    convert "$PROFILE_IMAGE" -auto-orient -resize "${geometry}^" \
      -gravity center -extent "$geometry" -strip "$temp_dir/image.png"
    exec "$LOCKER" --nofork --image "$temp_dir/image.png";;
  blur)
    command -v maim >/dev/null 2>&1 || { printf '✗ ERROR: blur requiere maim\n' >&2; exit 1; }
    command -v convert >/dev/null 2>&1 || { printf '✗ ERROR: blur requiere ImageMagick (convert)\n' >&2; exit 1; }
    temp_dir="$(temporary_directory)"
    trap 'rm -rf -- "$temp_dir"' EXIT HUP INT TERM
    maim -u -- "$temp_dir/screen.png"
    convert "$temp_dir/screen.png" -blur 0x6 "$temp_dir/blur.png"
    exec "$LOCKER" --nofork --image "$temp_dir/blur.png";;
  *) printf '✗ ERROR: modo inválido: %s\n' "$MODE" >&2; exit 2;;
esac
