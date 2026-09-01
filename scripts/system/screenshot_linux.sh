#!/usr/bin/env bash
# v1.0.0 - Capturas X11 de pantalla completa, selección o ventana activa.
set -Eeuo pipefail
umask 077
export LC_ALL=C

MODE="full"
COPY=0
FORCE=0
OUTPUT=""
SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Imágenes}/CapturasDePantalla"
TEMP_FILE=""

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  screenshot_linux.sh --full [--copy] [--output archivo.png]
  screenshot_linux.sh --select [--copy] [--output archivo.png]
  screenshot_linux.sh --window [--copy] [--output archivo.png]
  screenshot_linux.sh --status

Las capturas se guardan por defecto en ~/Imágenes/CapturasDePantalla y pueden
copiarse al portapapeles con --copy. No requiere sudo.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --full) MODE="full" ;;
      --select|--area) MODE="select" ;;
      --window|--active-window) MODE="window" ;;
      --copy|--clipboard) COPY=1 ;;
      --force) FORCE=1 ;;
      --output|-o)
        (($# >= 2)) || die '--output requiere un archivo'
        OUTPUT="$2"; shift
        ;;
      --status|--check) MODE="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

absolute_path() {
  case "$1" in
    /*) readlink -m -- "$1" ;;
    *) readlink -m -- "$PWD/$1" ;;
  esac
}

allowed_output() {
  local path="$1"
  case "$path" in
    "$HOME"/*|/tmp/*) return 0 ;;
    *) return 1 ;;
  esac
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "falta $1"; }

show_status() {
  printf '═══ Capturador X11 ═══\n'
  for command_name in maim xclip xprop notify-send; do
    if command -v "$command_name" >/dev/null 2>&1; then ok "$command_name disponible"; else warn "$command_name ausente"; fi
  done
  printf 'directorio=%s\n' "$SCREENSHOT_DIR"
  if [[ -n "${DISPLAY:-}" ]]; then
    ok "DISPLAY=$DISPLAY"
  else
    warn 'DISPLAY ausente; la captura requiere una sesión gráfica X11'
  fi
}

validate_output() {
  local output_path
  if [[ -z "$OUTPUT" ]]; then
    mkdir -p "$SCREENSHOT_DIR"
    OUTPUT="$SCREENSHOT_DIR/screenshot-$(date +%F_%H-%M-%S)-$$.png"
  fi
  output_path="$(absolute_path "$OUTPUT")"
  allowed_output "$output_path" || die 'la salida debe estar bajo HOME o /tmp'
  [[ "$output_path" == *.png ]] || die 'la salida debe terminar en .png'
  [[ ! -L "$output_path" ]] || die 'la salida no puede ser un enlace simbólico'
  [[ ! -e "$output_path" || "$FORCE" -eq 1 ]] || die "la salida ya existe: $output_path (usa --force)"
  OUTPUT="$output_path"
  mkdir -p "$(dirname -- "$OUTPUT")"
}

cleanup() {
  [[ -n "$TEMP_FILE" && -e "$TEMP_FILE" ]] && rm -f -- "$TEMP_FILE"
}

active_window_id() {
  local window_id
  window_id="$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null |
    awk '{print $5}' | tr -d '"' || true)"
  [[ "$window_id" =~ ^0x[0-9a-fA-F]+$ && "$window_id" != 0x0 ]] ||
    die 'no se pudo identificar la ventana activa'
  printf '%s\n' "$window_id"
}

capture() {
  local window_id
  TEMP_FILE="$(mktemp --suffix=.png "$(dirname -- "$OUTPUT")/.screenshot.XXXXXX")"
  case "$MODE" in
    full) maim -- "$TEMP_FILE" ;;
    select) maim -s -- "$TEMP_FILE" ;;
    window)
      window_id="$(active_window_id)"
      maim -i "$window_id" -- "$TEMP_FILE"
      ;;
    *) die "modo de captura inválido: $MODE" ;;
  esac
  [[ -s "$TEMP_FILE" ]] || die 'maim no produjo una imagen'
  if [[ "$COPY" -eq 1 ]]; then
    require_command xclip
    xclip -selection clipboard -t image/png -i < "$TEMP_FILE"
    ok 'imagen copiada al portapapeles'
  fi
  mv -f -- "$TEMP_FILE" "$OUTPUT"
  TEMP_FILE=""
  chmod 600 -- "$OUTPUT"
  ok "captura guardada: $OUTPUT"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --expire-time=2500 'Captura de pantalla' "$(basename -- "$OUTPUT")" >/dev/null 2>&1 || true
  fi
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este capturador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal'
  if [[ "$MODE" == status ]]; then show_status; return 0; fi
  require_command maim
  require_command xprop
  [[ -n "${DISPLAY:-}" ]] || die 'no existe DISPLAY; ejecuta la captura dentro de i3 u Openbox'
  validate_output
  trap cleanup EXIT
  capture
}

main "$@"
