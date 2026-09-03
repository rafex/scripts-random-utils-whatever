#!/usr/bin/env bash
# v1.1.0 - Valida, empaqueta y publica localmente la aplicación Firefox OS Hola Mundo.
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
readonly PUBLISHER_CONTEXT="$REPO_ROOT/containers/firefoxos-publisher"
readonly PUBLISHER_IMAGE="localhost/rafex/firefoxos-publisher:1.0.0"
readonly PUBLISHER_NAME="rafex-firefoxos-hello"
readonly DEFAULT_BIND="192.168.3.91"
readonly DEFAULT_PORT=8765
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
BIND_ADDRESS="$DEFAULT_BIND"
PUBLISHER_PORT="$DEFAULT_PORT"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_hello_world_linux.sh --check
  firefoxos_hello_world_linux.sh --status
  firefoxos_hello_world_linux.sh --plan [--bind <ip>] [--port <puerto>]
  firefoxos_hello_world_linux.sh --package [--output <archivo.zip>] [--force]
  firefoxos_hello_world_linux.sh --serve-podman [--bind <ip>] [--port <puerto>]
  firefoxos_hello_world_linux.sh --publisher-status
  firefoxos_hello_world_linux.sh --stop-podman

Valida y empaqueta la aplicación Firefox OS Hola Mundo. Puede servirla
temporalmente mediante un contenedor Podman rootless para instalarla como
aplicación hospedada desde el navegador del Flame. No ejecuta ADB, fastboot ni
WebIDE, y nunca instala la aplicación directamente en el teléfono.
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
      --plan) choose_action plan ;;
      --package) choose_action package ;;
      --serve-podman) choose_action serve_podman ;;
      --publisher-status) choose_action publisher_status ;;
      --stop-podman) choose_action stop_podman ;;
      --output|-o)
        (($# >= 2)) || die '--output requiere una ruta'
        OUTPUT="$2"
        shift
        ;;
      --force) FORCE=1 ;;
      --bind)
        (($# >= 2)) || die '--bind requiere una dirección IPv4'
        BIND_ADDRESS="$2"
        shift
        ;;
      --port)
        (($# >= 2)) || die '--port requiere un número'
        PUBLISHER_PORT="$2"
        shift
        ;;
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
  case "$ACTION" in
    plan|serve_podman) ;;
    *)
      [[ "$BIND_ADDRESS" == "$DEFAULT_BIND" ]] || die '--bind solo se puede usar con --plan o --serve-podman'
      [[ "$PUBLISHER_PORT" == "$DEFAULT_PORT" ]] || die '--port solo se puede usar con --plan o --serve-podman'
      ;;
  esac
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

validate_publisher_context() {
  local required

  [[ -d "$PUBLISHER_CONTEXT" ]] || die "falta el contexto Podman: $PUBLISHER_CONTEXT"
  for required in Containerfile server.py; do
    [[ -f "$PUBLISHER_CONTEXT/$required" ]] || die "falta archivo del publicador: $required"
  done
  [[ ! -L "$PUBLISHER_CONTEXT/Containerfile" && ! -L "$PUBLISHER_CONTEXT/server.py" ]] \
    || die 'el contexto Podman no puede contener enlaces simbólicos'
}

validate_publisher_network() {
  python3 - "$BIND_ADDRESS" "$PUBLISHER_PORT" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError as exc:
    print(f"✗ ERROR: --bind no es una IPv4 válida: {exc}", file=sys.stderr)
    raise SystemExit(1)

if address.version != 4 or address.is_loopback or address.is_unspecified:
    print("✗ ERROR: --bind debe ser una IPv4 local no loopback", file=sys.stderr)
    raise SystemExit(1)

try:
    port = int(sys.argv[2])
except ValueError:
    print("✗ ERROR: --port debe ser un número", file=sys.stderr)
    raise SystemExit(1)

if not 1024 <= port <= 65535:
    print("✗ ERROR: --port debe estar entre 1024 y 65535", file=sys.stderr)
    raise SystemExit(1)
PY

  command -v ip >/dev/null 2>&1 || die 'falta ip para validar la dirección local'
  if ! ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq -- "$BIND_ADDRESS"; then
    die "la dirección $BIND_ADDRESS no está configurada en la ThinkPad"
  fi
}

require_podman() {
  command -v podman >/dev/null 2>&1 || die 'falta podman; el publicador no instala Podman automáticamente'
}

publisher_origin() {
  printf 'http://%s:%s\n' "$BIND_ADDRESS" "$PUBLISHER_PORT"
}

publisher_is_managed() {
  local label

  label="$(podman inspect --format '{{ index .Config.Labels "io.rafex.publisher" }}' "$PUBLISHER_NAME" 2>/dev/null || true)"
  [[ "$label" == 'firefoxos-hello-world' ]]
}

show_publisher_status() {
  require_podman
  printf 'imagen=%s\n' "$PUBLISHER_IMAGE"
  if podman image exists "$PUBLISHER_IMAGE"; then
    ok 'imagen Podman disponible'
  else
    warn 'imagen Podman aún no construida'
  fi

  if podman container exists "$PUBLISHER_NAME"; then
    if publisher_is_managed; then
      podman inspect --format 'contenedor={{.Name}} estado={{.State.Status}}' "$PUBLISHER_NAME"
      if [[ "$(podman inspect --format '{{.State.Running}}' "$PUBLISHER_NAME")" == true ]]; then
        printf 'url=%s\n' "$(publisher_origin)"
      fi
    else
      die "ya existe un contenedor no administrado con el nombre $PUBLISHER_NAME"
    fi
  else
    printf 'contenedor=ausente\n'
  fi
}

show_publisher_plan() {
  validate_application
  validate_publisher_context
  validate_publisher_network
  require_podman
  printf 'imagen=%s\n' "$PUBLISHER_IMAGE"
  printf 'contenedor=%s\n' "$PUBLISHER_NAME"
  printf 'origen_publico=%s\n' "$(publisher_origin)"
  printf 'contenido=/srv/app (montaje de solo lectura)\n'
  printf '→ No se construiría ni iniciaría nada con --plan.\n'
  printf '→ El servidor escucharía únicamente en %s:%s.\n' "$BIND_ADDRESS" "$PUBLISHER_PORT"
  printf '→ UFW no se modificaría y no se usaría --network=host.\n'
}

build_publisher_image() {
  if podman image exists "$PUBLISHER_IMAGE"; then
    ok "imagen Podman disponible: $PUBLISHER_IMAGE"
    return
  fi

  info 'construyendo imagen del publicador con la base oficial de Python'
  podman build --pull=missing --tag "$PUBLISHER_IMAGE" "$PUBLISHER_CONTEXT"
  ok "imagen construida: $PUBLISHER_IMAGE"
}

serve_with_podman() {
  validate_application
  validate_publisher_context
  validate_publisher_network
  require_podman

  if podman container exists "$PUBLISHER_NAME"; then
    publisher_is_managed || die "ya existe un contenedor no administrado con el nombre $PUBLISHER_NAME"
    if [[ "$(podman inspect --format '{{.State.Running}}' "$PUBLISHER_NAME")" == true ]]; then
      ok "publicador ya estaba activo: $(publisher_origin)"
      return
    fi
    info 'retirando el contenedor administrado detenido; no contiene datos persistentes'
    podman rm "$PUBLISHER_NAME" >/dev/null
  fi

  build_publisher_image
  podman run --detach --rm \
    --name "$PUBLISHER_NAME" \
    --label 'io.rafex.publisher=firefoxos-hello-world' \
    --label "io.rafex.publisher.origin=$(publisher_origin)" \
    --read-only \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=64 \
    --memory=128m \
    --user 65532:65532 \
    --volume "$APP_ROOT:/srv/app:ro" \
    --publish "$BIND_ADDRESS:$PUBLISHER_PORT:8080/tcp" \
    --env "PUBLIC_ORIGIN=$(publisher_origin)" \
    --pull=never \
    "$PUBLISHER_IMAGE" >/dev/null

  ok "publicador activo: $(publisher_origin)/install.html"
  warn 'el servidor es temporal y visible en la red local; detenlo con --stop-podman'
  warn 'no se abrió ninguna regla de UFW; si el teléfono no conecta, el firewall puede estar bloqueándolo'
}

stop_publisher() {
  require_podman
  if ! podman container exists "$PUBLISHER_NAME"; then
    info 'el publicador no está activo'
    return
  fi
  publisher_is_managed || die "no se detendrá el contenedor no administrado $PUBLISHER_NAME"
  if [[ "$(podman inspect --format '{{.State.Running}}' "$PUBLISHER_NAME")" == true ]]; then
    podman stop --time 5 "$PUBLISHER_NAME" >/dev/null
    ok 'publicador detenido'
  else
    podman rm "$PUBLISHER_NAME" >/dev/null
    ok 'contenedor administrado detenido retirado'
  fi
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
  plan)
    show_publisher_plan
    ;;
  package)
    package_application
    ;;
  serve_podman)
    serve_with_podman
    ;;
  publisher_status)
    show_publisher_status
    ;;
  stop_podman)
    stop_publisher
    ;;
esac
