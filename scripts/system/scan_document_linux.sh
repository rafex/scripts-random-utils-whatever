#!/usr/bin/env bash
# v1.0.0 - Escanea documentos desde SANE sin privilegios administrativos.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

OUTPUT=""
DEVICE=""
RESOLUTION=300
MODE="Color"
FORCE=0
LIST_ONLY=0

usage() {
  cat <<'EOF'
Uso: scan_document_linux.sh --output <archivo.png> [opciones]
     scan_document_linux.sh --list

Escanea preferentemente el Epson XP-241 mediante SANE. No usa sudo.
EOF
}

die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  exit 1
}

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }

validate_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este comando requiere Linux'
  command -v scanimage >/dev/null 2>&1 \
    || die 'falta scanimage; ejecuta just install-printers --apply'
  command -v realpath >/dev/null 2>&1 || die 'falta realpath'
}

list_scanners() {
  scanimage -L 2>/dev/null || true
}

select_device() {
  local line selected
  if [[ -n "$DEVICE" ]]; then
    printf '%s\n' "$DEVICE"
    return 0
  fi
  line="$(list_scanners | grep -Ei 'epson|airscan|escl' | head -n1 || true)"
  [[ -n "$line" ]] || die 'no se detecta un escáner Epson; conecta la XP-241 y ejecuta scanimage -L'
  selected="${line#device \`}"
  selected="${selected%%\`*}"
  if [[ "$selected" == "$line" ]]; then
    selected="${line#device \'}"
    selected="${selected%%\'*}"
  fi
  [[ -n "$selected" && "$selected" != "$line" ]] \
    || die 'no se pudo interpretar el dispositivo SANE; usa --device con la URI mostrada por scanimage -L'
  printf '%s\n' "$selected"
}

validate_output() {
  local output_abs parent
  [[ -n "$OUTPUT" ]] || die 'debes indicar --output archivo.png'
  [[ "$OUTPUT" == *.png ]] || die 'la salida debe terminar en .png'
  output_abs="$(realpath -m -- "$OUTPUT")"
  case "$output_abs" in
    "$HOME"/*|/tmp/*) ;;
    *) die 'por seguridad la salida debe estar bajo HOME o /tmp' ;;
  esac
  case "$output_abs" in
    /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*)
      die 'la salida apunta a una ruta del sistema no permitida' ;;
  esac
  [[ -d "$output_abs" ]] && die 'la salida apunta a un directorio'
  parent="$(dirname -- "$output_abs")"
  mkdir -p -- "$parent"
  if [[ -e "$output_abs" && "$FORCE" != 1 ]]; then
    die "el archivo ya existe; usa --force para reemplazarlo: $output_abs"
  fi
  printf '%s\n' "$output_abs"
}

scan_document() {
  local output_abs parent temp device
  output_abs="$(validate_output)"
  parent="$(dirname -- "$output_abs")"
  temp="$(mktemp "$parent/.rafex-scan.XXXXXX.png")"
  device="$(select_device)"
  info "escaneando con SANE: $device"
  if ! scanimage --device-name "$device" --format=png \
    --resolution "$RESOLUTION" --mode "$MODE" > "$temp"; then
    rm -f -- "$temp"
    die 'SANE no pudo completar el escaneo'
  fi
  mv -f -- "$temp" "$output_abs"
  ok "escaneo guardado: $output_abs"
}

while (($#)); do
  case "$1" in
    --output|-o)
      (($# >= 2)) || die 'falta el valor de --output'
      OUTPUT="$2"; shift ;;
    --device|-d)
      (($# >= 2)) || die 'falta el valor de --device'
      DEVICE="$2"; shift ;;
    --resolution|-r)
      (($# >= 2)) || die 'falta el valor de --resolution'
      RESOLUTION="$2"; shift
      [[ "$RESOLUTION" =~ ^[1-9][0-9]*$ ]] || die 'la resolución debe ser un entero positivo'
      ;;
    --mode|-m)
      (($# >= 2)) || die 'falta el valor de --mode'
      MODE="$2"; shift
      [[ "$MODE" =~ ^(Color|Gray|Lineart)$ ]] || die '--mode debe ser Color, Gray o Lineart'
      ;;
    --force) FORCE=1 ;;
    --list) LIST_ONLY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
  shift
done

validate_linux
if (( LIST_ONLY )); then
  list_scanners
else
  scan_document
fi
