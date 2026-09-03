#!/usr/bin/env bash
# v1.0.0 - Valida y empaqueta la aplicación Firefox OS Hola Mundo.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_ROOT
APP_ROOT="$REPO_ROOT/examples/firefoxos/hello-world"
readonly APP_ROOT
MANIFEST="$APP_ROOT/manifest.webapp"
readonly MANIFEST
DEFAULT_OUTPUT="${TMPDIR:-/tmp}/rafex-firefoxos-hello-world-1.0.0.zip"
readonly DEFAULT_OUTPUT
readonly EXPECTED_FILES=(
  "app.js"
  "index.html"
  "manifest.webapp"
  "style.css"
)

ACTION="status"
ACTION_EXPLICIT=0
OUTPUT=""
FORCE=0

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_hello_world_linux.sh --check
  firefoxos_hello_world_linux.sh --status
  firefoxos_hello_world_linux.sh --package [--output <archivo.zip>] [--force]

Valida y empaqueta la aplicación Firefox OS Hola Mundo. No ejecuta ADB,
fastboot ni WebIDE, y nunca instala la aplicación en el teléfono.
EOF
}

choose_action() {
  [[ "$ACTION_EXPLICIT" -eq 0 ]] || die 'solo se puede seleccionar una acción por ejecución'
  ACTION="$1"
  ACTION_EXPLICIT=1
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) choose_action check ;;
      --status) choose_action status ;;
      --package) choose_action package ;;
      --output|-o)
        (($# >= 2)) || die '--output requiere una ruta'
        OUTPUT="$2"
        shift
        ;;
      --force) FORCE=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done

  if [[ "$ACTION" != package && -n "$OUTPUT" ]]; then
    die '--output solo se puede usar con --package'
  fi
  if [[ "$ACTION" != package && "$FORCE" -eq 1 ]]; then
    die '--force solo se puede usar con --package'
  fi
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  command -v python3 >/dev/null 2>&1 || die 'falta python3'
}

validate_files() {
  local expected actual symlink

  [[ -d "$APP_ROOT" ]] || die "no existe la aplicación: $APP_ROOT"
  [[ -f "$MANIFEST" ]] || die 'falta manifest.webapp'

  symlink="$(find "$APP_ROOT" -type l -print -quit)"
  [[ -z "$symlink" ]] || die "la aplicación no puede contener enlaces simbólicos: $symlink"

  for expected in "${EXPECTED_FILES[@]}"; do
    [[ -f "$APP_ROOT/$expected" ]] || die "falta archivo requerido: $expected"
  done

  actual="$(find "$APP_ROOT" -type f -printf '%P\n' | LC_ALL=C sort)"
  expected="$(printf '%s\n' "${EXPECTED_FILES[@]}" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || {
    printf 'Archivos encontrados:\n%s\n' "$actual" >&2
    die 'la aplicación contiene archivos no permitidos o le faltan archivos'
  }

  while IFS= read -r expected; do
    [[ -z "$expected" ]] && continue
    [[ "$expected" != .* && "$expected" != */.* && "$expected" != /* && "$expected" != *..* ]] \
      || die "ruta interna no permitida: $expected"
  done <<< "$actual"
}

validate_manifest() {
  python3 - "$MANIFEST" "$APP_ROOT/index.html" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
launch_path = Path(sys.argv[2])

try:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"✗ ERROR: manifest.webapp no es JSON válido: {exc}", file=sys.stderr)
    raise SystemExit(1)

required = {"name", "description", "launch_path", "default_locale", "version", "developer"}
missing = sorted(required - data.keys()) if isinstance(data, dict) else sorted(required)
if not isinstance(data, dict) or missing:
    print(f"✗ ERROR: faltan campos del manifiesto: {', '.join(missing)}", file=sys.stderr)
    raise SystemExit(1)

if data["launch_path"] != "/index.html":
    print("✗ ERROR: launch_path debe ser /index.html", file=sys.stderr)
    raise SystemExit(1)
if not launch_path.is_file():
    print("✗ ERROR: launch_path no apunta a un archivo existente", file=sys.stderr)
    raise SystemExit(1)
if data["default_locale"] != "es" or data["version"] != "1.0.0":
    print("✗ ERROR: el manifiesto debe conservar idioma es y versión 1.0.0", file=sys.stderr)
    raise SystemExit(1)
if "permissions" in data or "type" in data:
    print("✗ ERROR: la aplicación inicial no admite permisos ni tipo privilegiado", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(data["developer"], dict) or not data["developer"].get("name"):
    print("✗ ERROR: el manifiesto requiere developer.name", file=sys.stderr)
    raise SystemExit(1)
PY
}

validate_application() {
  validate_files
  validate_manifest
}

show_status() {
  validate_application
  printf 'aplicación=%s\n' "$APP_ROOT"
  printf 'nombre=Rafex Hola Mundo\n'
  printf 'versión=1.0.0\n'
  printf 'formato=webapp empaquetada local no privilegiada\n'
  printf 'archivos=%d\n' "${#EXPECTED_FILES[@]}"
  printf 'instalación automática=desactivada\n'
  ok 'estructura y manifiesto válidos'
}

validate_output() {
  local output_abs parent

  output_abs="$(realpath -m -- "${OUTPUT:-$DEFAULT_OUTPUT}")"
  case "$output_abs" in
    "$HOME"/*|/tmp/*) ;;
    *) die 'por seguridad la salida debe estar bajo HOME o /tmp' ;;
  esac
  case "$output_abs" in
    /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*)
      die 'la salida apunta a una ruta del sistema no permitida' ;;
  esac
  [[ "$output_abs" == *.zip ]] || die 'la salida debe terminar en .zip'
  [[ -d "$output_abs" ]] && die 'la salida apunta a un directorio'
  if [[ -e "$output_abs" && "$FORCE" -ne 1 ]]; then
    die "el archivo ya existe; usa --force para reemplazarlo: $output_abs"
  fi
  parent="$(dirname -- "$output_abs")"
  mkdir -p -- "$parent"
  printf '%s\n' "$output_abs"
}

package_application() {
  local output_abs temp

  validate_application
  output_abs="$(validate_output)"
  temp="$(mktemp "$(dirname -- "$output_abs")/.rafex-firefoxos-hello-world.XXXXXX")"
  trap 'rm -f -- "$temp"' EXIT

  python3 - "$APP_ROOT" "$temp" "${EXPECTED_FILES[@]}" <<'PY'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
files = sys.argv[3:]

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for relative in sorted(files):
        data = (root / relative).read_bytes()
        info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        archive.writestr(info, data)
PY

  mv -f -- "$temp" "$output_abs"
  trap - EXIT
  ok "paquete generado: $output_abs"
}

parse_args "$@"
require_linux

case "$ACTION" in
  check)
    validate_application
    ok 'aplicación Firefox OS válida; no se creó ningún archivo'
    ;;
  status)
    show_status
    ;;
  package)
    package_application
    ;;
esac
