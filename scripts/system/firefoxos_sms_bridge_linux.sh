#!/usr/bin/env bash
# v1.0.0 - Administra el puente SMS rootless entre la ThinkPad y Firefox OS.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
APP_ROOT="$REPO_ROOT/examples/firefoxos/sms-bridge"
CONTEXT="$REPO_ROOT/containers/firefoxos-sms-bridge"
STATE_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/rafex/firefoxos-sms"
readonly APP_ROOT CONTEXT STATE_ROOT
readonly IMAGE="localhost/rafex/firefoxos-sms-bridge:1.0.0"
readonly CONTAINER="rafex-firefoxos-sms"
readonly BIND_ADDRESS="192.168.3.91"
readonly ADMIN_BIND="127.0.0.1"
readonly ADMIN_PORT=8786
readonly PHONE_PORT=8787
readonly ADMIN_URL="http://127.0.0.1:8786"
readonly PHONE_ORIGIN="http://192.168.3.91:8787"

ACTION="status"
TO=""
BODY=""
REQUEST_ID=""

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_sms_bridge_linux.sh --check
  firefoxos_sms_bridge_linux.sh --plan
  firefoxos_sms_bridge_linux.sh --serve-podman
  firefoxos_sms_bridge_linux.sh --stop
  firefoxos_sms_bridge_linux.sh --status
  firefoxos_sms_bridge_linux.sh --pair
  firefoxos_sms_bridge_linux.sh --revoke
  firefoxos_sms_bridge_linux.sh --enqueue --to +5255XXXXXXX --body "Mensaje"
  firefoxos_sms_bridge_linux.sh --history
  firefoxos_sms_bridge_linux.sh --purge

Administra una cola local autenticada. El Flame solo presenta SMS en Mensajes;
el envío final siempre se confirma manualmente en el teléfono.
EOF
}

choose_action() {
  [[ "$ACTION" == status ]] || die 'solo se puede seleccionar una acción por ejecución'
  ACTION="$1"
}

parse_args() {
  local action_selected=0
  while (($#)); do
    case "$1" in
      --check) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=check; action_selected=1 ;;
      --plan|--dry-run) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=plan; action_selected=1 ;;
      --serve-podman|--serve) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=serve; action_selected=1 ;;
      --stop|--stop-podman) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=stop; action_selected=1 ;;
      --status) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=status; action_selected=1 ;;
      --pair) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=pair; action_selected=1 ;;
      --revoke) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=revoke; action_selected=1 ;;
      --enqueue) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=enqueue; action_selected=1 ;;
      --history) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=history; action_selected=1 ;;
      --purge) ((action_selected == 0)) || die 'solo se puede seleccionar una acción por ejecución'; ACTION=purge; action_selected=1 ;;
      --to)
        (($# >= 2)) || die '--to requiere un número E.164'
        TO="$2"
        shift
        ;;
      --body)
        (($# >= 2)) || die '--body requiere el texto del SMS'
        BODY="$2"
        shift
        ;;
      --request-id)
        (($# >= 2)) || die '--request-id requiere un identificador'
        REQUEST_ID="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done

  if [[ "$ACTION" != enqueue && ( -n "$TO" || -n "$BODY" || -n "$REQUEST_ID" ) ]]; then
    die '--to, --body y --request-id solo se usan con --enqueue'
  fi
  if [[ "$ACTION" == enqueue ]]; then
    [[ -n "$TO" ]] || die '--enqueue requiere --to'
    [[ -n "$BODY" ]] || die '--enqueue requiere --body'
  fi
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; no requiere sudo'
  command -v python3 >/dev/null 2>&1 || die 'falta python3'
}

require_podman() {
  command -v podman >/dev/null 2>&1 || die 'falta podman; ejecuta install-firefoxos-sms-bridge --apply'
}

validate_sources() {
  local required actual
  for required in \
    "$CONTEXT/Containerfile" \
    "$CONTEXT/server.py" \
    "$APP_ROOT/manifest.webapp" \
    "$APP_ROOT/index.html" \
    "$APP_ROOT/style.css" \
    "$APP_ROOT/app.js"; do
    [[ -f "$required" ]] || die "falta componente del puente: $required"
    [[ ! -L "$required" ]] || die "no se permiten enlaces simbólicos: $required"
  done
  actual="$(find "$APP_ROOT" -type f -printf '%P\n' | LC_ALL=C sort)"
  [[ "$actual" == $'app.js\nindex.html\nmanifest.webapp\nstyle.css' ]] ||
    die 'la aplicación SMS contiene archivos no permitidos'
  python3 - "$APP_ROOT/manifest.webapp" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"manifest.webapp inválido: {exc}", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(data, dict):
    raise SystemExit("manifest.webapp debe ser un objeto JSON")
if data.get("launch_path") != "/index.html":
    raise SystemExit("launch_path debe ser /index.html")
if data.get("default_locale") != "es" or data.get("version") != "1.0.0":
    raise SystemExit("el manifiesto debe conservar es y versión 1.0.0")
if "permissions" in data or "type" in data:
    raise SystemExit("la aplicación no debe declarar permisos ni tipo privilegiado")
PY
}

validate_network() {
  command -v ip >/dev/null 2>&1 || die 'falta ip para validar la dirección LAN'
  ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq -- "$BIND_ADDRESS" ||
    die "la dirección $BIND_ADDRESS no está configurada en la ThinkPad"
}

managed_container() {
  [[ "$(podman inspect --format '{{ index .Config.Labels "io.rafex.component" }}' "$CONTAINER" 2>/dev/null || true)" == firefoxos-sms-bridge ]]
}

container_running() {
  [[ "$(podman inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == true ]]
}

show_status() {
  printf '═══ Puente SMS Firefox OS ═══\n'
  printf 'origen_flame=%s\n' "$PHONE_ORIGIN"
  printf 'consola_local=http://%s:%s\n' "$ADMIN_BIND" "$ADMIN_PORT"
  printf 'estado=%s\n' "$STATE_ROOT"
  if command -v podman >/dev/null 2>&1; then
    if podman image exists "$IMAGE"; then
      ok "imagen disponible: $IMAGE"
    else
      info 'imagen Podman aún no construida'
    fi
    if podman container exists "$CONTAINER"; then
      managed_container || die "existe un contenedor no administrado con el nombre $CONTAINER"
      podman inspect --format 'contenedor={{.Name}} estado={{.State.Status}}' "$CONTAINER"
      if container_running; then
        if response="$(admin_request GET /api/v1/admin/status)"; then
          parse_response "$response" status
        else
          warn 'el contenedor aparece activo, pero la consola local no responde'
        fi
      fi
    else
      printf 'contenedor=ausente\n'
    fi
  else
    warn 'podman no está instalado'
  fi
  info 'no se muestran tokens ni contenido de mensajes'
}

show_plan() {
  validate_sources
  validate_network
  require_podman
  printf '═══ Plan puente SMS Firefox OS ═══\n'
  info "imagen: $IMAGE"
  info "contenedor rootless: $CONTAINER"
  info "consola local: $ADMIN_BIND:$ADMIN_PORT"
  info "aplicación y API LAN: $BIND_ADDRESS:$PHONE_PORT"
  info "estado privado: $STATE_ROOT (0700)"
  info 'retención: 30 días; una sola entrada queued; no se modificará UFW'
  info 'no se usará ADB, no se ejecutará como root y no se enviará SMS directamente'
}

build_image() {
  if podman image exists "$IMAGE"; then
    ok "imagen Podman disponible: $IMAGE"
    return
  fi
  info 'construyendo imagen rootless del puente SMS'
  podman build --pull=missing --tag "$IMAGE" "$CONTEXT"
  ok "imagen construida: $IMAGE"
}

serve_podman() {
  validate_sources
  validate_network
  require_podman
  mkdir -p -- "$STATE_ROOT"
  chmod 0700 -- "$STATE_ROOT"
  if podman container exists "$CONTAINER"; then
    managed_container || die "existe un contenedor no administrado con el nombre $CONTAINER"
    if container_running; then
      ok "puente SMS ya estaba activo: $PHONE_ORIGIN"
      return
    fi
    podman rm "$CONTAINER" >/dev/null
  fi
  build_image
  podman run --detach --rm \
    --name "$CONTAINER" \
    --label 'io.rafex.component=firefoxos-sms-bridge' \
    --label "io.rafex.phone-origin=$PHONE_ORIGIN" \
    --read-only \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=64 \
    --memory=128m \
    --userns=keep-id \
    --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
    --volume "$APP_ROOT:/srv/app:ro" \
    --volume "$STATE_ROOT:/var/lib/rafex:rw" \
    --publish "$ADMIN_BIND:$ADMIN_PORT:8786/tcp" \
    --publish "$BIND_ADDRESS:$PHONE_PORT:8787/tcp" \
    --pull=never \
    "$IMAGE" \
    --state-dir /var/lib/rafex \
    --app-root /srv/app \
    --phone-origin "$PHONE_ORIGIN" \
    --admin-bind 0.0.0.0 \
    --phone-bind 0.0.0.0 \
    --admin-port 8786 \
    --phone-port 8787 >/dev/null
  ok "puente SMS activo: $PHONE_ORIGIN/install.html"
  info 'consola local: http://127.0.0.1:8786/'
  warn 'no se abrió UFW; si hace falta, permite manualmente solo la IP del Flame al puerto 8787'
}

stop_podman() {
  require_podman
  if ! podman container exists "$CONTAINER"; then
    info 'el puente SMS no está activo'
    return
  fi
  managed_container || die "no se detendrá el contenedor no administrado $CONTAINER"
  if container_running; then
    podman stop --time 5 "$CONTAINER" >/dev/null
    ok 'puente SMS detenido'
  else
    podman rm "$CONTAINER" >/dev/null
    ok 'contenedor administrado detenido retirado'
  fi
}

admin_request() {
  local method="$1" path="$2"
  python3 - "$ADMIN_URL$path" "$method" <<'PY'
import sys
import urllib.error
import urllib.request

url, method = sys.argv[1:]
payload = sys.stdin.buffer.read() if method != "GET" else b""
request = urllib.request.Request(url, data=payload if method != "GET" else None, method=method)
if payload:
    request.add_header("Content-Type", "application/json")
try:
    with urllib.request.urlopen(request, timeout=5) as response:
        print(response.status)
        print(response.read().decode("utf-8"), end="")
except urllib.error.HTTPError as exc:
    print(exc.code)
    print(exc.read().decode("utf-8"), end="")
except (OSError, urllib.error.URLError):
    print("0")
PY
}

parse_response() {
  local response="$1" context="$2" status body
  status="${response%%$'\n'*}"
  body="${response#*$'\n'}"
  [[ "$status" =~ ^[0-9]+$ ]] || die 'respuesta inválida de la consola local'
  case "$context" in
    pair)
      if [[ "$status" == 200 ]]; then
        python3 - "$body" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
print(f"Código temporal: {data['code']}")
print(f"Caduca en: {data['expires_in']} segundos")
PY
      else
        die 'no se pudo generar el código de vinculación'
      fi
      ;;
    enqueue)
      case "$status" in
        201) ok 'mensaje agregado a la cola; el Flame deberá presentarlo en Mensajes' ;;
        200) ok 'solicitud duplicada; se conserva el mensaje existente' ;;
        400|409) die "no se agregó el mensaje: $(python3 - "$body" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("error", "petición rechazada"))
except (ValueError, TypeError):
    print("petición rechazada")
PY
)" ;;
        *) die 'la consola local no pudo agregar el mensaje' ;;
      esac
      ;;
    status)
      if [[ "$status" == 200 ]]; then
        python3 - "$body" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
print(f"token_configurado={int(bool(data.get('token_configured')))}")
print(f"pairing_pendiente={int(bool(data.get('pairing_pending')))}")
print(f"mensajes={data.get('messages', {})}")
PY
      else
        warn 'la consola local del puente no responde'
      fi
      ;;
    history)
      [[ "$status" == 200 ]] || die 'no se pudo leer el historial local'
      python3 - "$body" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
for message in data.get("messages", []):
    print(f"{message.get('created_at')} {message.get('status')} {message.get('recipient')}: {message.get('body')}")
PY
      ;;
    revoke) [[ "$status" == 200 ]] || die 'no se pudo revocar la vinculación'; ok 'token revocado' ;;
    purge)
      [[ "$status" == 200 ]] || die 'no se pudo purgar el historial'
      python3 - "$body" <<'PY'
import json
import sys
print(f"entradas retiradas: {json.loads(sys.argv[1]).get('removed', 0)}")
PY
      ;;
    *) die 'contexto de respuesta desconocido' ;;
  esac
}

ensure_running() {
  require_podman
  podman container exists "$CONTAINER" || die 'el puente no está activo; ejecuta --serve-podman'
  managed_container || die "el contenedor $CONTAINER no está administrado por Rafex"
  container_running || die 'el contenedor del puente no está ejecutándose'
}

pair() {
  ensure_running
  response="$(printf '%s' '{}' | admin_request POST /api/v1/admin/pair)"
  parse_response "$response" pair
}

revoke() {
  ensure_running
  response="$(printf '%s' '{}' | admin_request POST /api/v1/admin/revoke)"
  parse_response "$response" revoke
}

enqueue() {
  local request_id payload response
  ensure_running
  request_id="$REQUEST_ID"
  if [[ -z "$request_id" ]]; then
    request_id="cli-$(date +%s)-$(python3 -c 'import secrets; print(secrets.token_hex(6))')"
  fi
  payload="$(python3 - "$TO" "$BODY" "$request_id" <<'PY'
import json
import sys
print(json.dumps({"recipient": sys.argv[1], "body": sys.argv[2], "request_id": sys.argv[3]}, ensure_ascii=False))
PY
)"
  response="$(printf '%s' "$payload" | admin_request POST /api/v1/admin/messages)"
  parse_response "$response" enqueue
}

history() {
  ensure_running
  response="$(admin_request GET /api/v1/admin/history)"
  parse_response "$response" history
}

purge() {
  ensure_running
  response="$(printf '%s' '{}' | admin_request POST /api/v1/admin/purge)"
  parse_response "$response" purge
}

parse_args "$@"
require_linux_user
case "$ACTION" in
  check)
    validate_sources
    validate_network
    require_podman
    ok 'puente SMS válido; --check no inició servicios ni creó credenciales'
    ;;
  plan) show_plan ;;
  serve) serve_podman ;;
  stop) stop_podman ;;
  status) show_status ;;
  pair) pair ;;
  revoke) revoke ;;
  enqueue) enqueue ;;
  history) history ;;
  purge) purge ;;
esac
