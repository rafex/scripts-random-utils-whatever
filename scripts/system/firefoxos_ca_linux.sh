#!/usr/bin/env bash
# v1.0.1 - Prepara e instala raíces Mozilla en el perfil NSS de Firefox OS.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly NSS_RELEASE="NSS_3_128_RTM"
readonly CERTDATA_URL="https://hg.mozilla.org/projects/nss/raw-file/${NSS_RELEASE}/lib/ckfw/builtins/certdata.txt"
readonly CERTDATA_SHA256="81b7f2576333a2e360e673f912d7b0b7a765d836c731003e348a46cac5d37198"
readonly STATE_ROOT="${HOME}/.local/share/rafex/firefoxos-ca"
readonly SOURCE_ROOT="${STATE_ROOT}/sources"
readonly ROLLBACK_ROOT="${STATE_ROOT}/rollback"
readonly SOURCE_FILE="${SOURCE_ROOT}/${NSS_RELEASE}-certdata.txt"
readonly SOURCE_MANIFEST="${SOURCE_ROOT}/${NSS_RELEASE}-server-auth.tsv"
readonly SOURCE_CERTS_ROOT="${SOURCE_ROOT}/${NSS_RELEASE}-certs"
readonly CONFIRM_APPLY="FLAME-MOZILLA-CA-WIPE"
readonly CONFIRM_ROLLBACK="FLAME-CA-ROLLBACK"

ACTION="status"
ACTION_EXPLICIT=0
CONFIRMATION=""

ADB_COMMAND=""
CERTUTIL_COMMAND=""
CURL_COMMAND=""
DEVICE_SERIAL=""
PROFILE_PATH=""
REMOTE_DB=""
WORK_DIR=""
B2G_STOPPED=0
ROOT_ADB_ACTIVE=0

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

restore_normal_adb() {
  local attempt uid=""
  [[ "$ROOT_ADB_ACTIVE" -eq 1 && -n "$ADB_COMMAND" && -n "$DEVICE_SERIAL" ]] || return 0

  "$ADB_COMMAND" -s "$DEVICE_SERIAL" unroot >/dev/null 2>&1 || true
  for ((attempt = 1; attempt <= 10; attempt++)); do
    if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
      uid="$(adb_prop_shell id -u || true)"
      if [[ "$uid" == 2000 ]]; then
        ROOT_ADB_ACTIVE=0
        return 0
      fi
    fi
    sleep 1
  done

  if [[ "$uid" == 0 ]]; then
    # Algunos adbd antiguos cierran la conexión y no aceptan `unroot`; un
    # reinicio controlado es la única forma de devolverlos al modo normal.
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1 || return 1
    for ((attempt = 1; attempt <= 30; attempt++)); do
      if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
        uid="$(adb_prop_shell id -u || true)"
        if [[ "$uid" == 2000 ]]; then
          ROOT_ADB_ACTIVE=0
          return 0
        fi
      fi
      sleep 2
    done
  fi

  return 1
}

cleanup() {
  local cleanup_status=$?
  if [[ "$B2G_STOPPED" -eq 1 && -n "$ADB_COMMAND" && -n "$DEVICE_SERIAL" ]]; then
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell start b2g >/dev/null 2>&1 || true
  fi
  if [[ "$ROOT_ADB_ACTIVE" -eq 1 && -n "$ADB_COMMAND" && -n "$DEVICE_SERIAL" ]]; then
    restore_normal_adb || true
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$cleanup_status"
}

trap cleanup EXIT HUP INT TERM

usage() {
  cat <<'EOF'
Uso:
  firefoxos_ca_linux.sh --status
  firefoxos_ca_linux.sh --check
  firefoxos_ca_linux.sh --plan
  firefoxos_ca_linux.sh --acquire
  firefoxos_ca_linux.sh --verify-source
  firefoxos_ca_linux.sh --preflight
  firefoxos_ca_linux.sh --apply --confirm FLAME-MOZILLA-CA-WIPE
  firefoxos_ca_linux.sh --test
  firefoxos_ca_linux.sh --rollback --confirm FLAME-CA-ROLLBACK

Prepara una copia verificada del almacén raíz Mozilla y la instala en el
cert9.db del perfil Firefox OS de un Flame. No compila B2G ni reemplaza
libnssckbi.so. --apply y --rollback son operaciones explícitas sobre el
teléfono y requieren ADB root temporal.
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
      --status|--check) choose_action status ;;
      --plan|--dry-run) choose_action plan ;;
      --acquire) choose_action acquire ;;
      --verify-source) choose_action verify-source ;;
      --preflight) choose_action preflight ;;
      --apply) choose_action apply ;;
      --test) choose_action test ;;
      --rollback) choose_action rollback ;;
      --confirm)
        (($# >= 2)) || die '--confirm requiere un texto exacto'
        CONFIRMATION="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done

  if [[ "$ACTION" != apply && "$ACTION" != rollback && -n "$CONFIRMATION" ]]; then
    die '--confirm solo se permite con --apply o --rollback'
  fi
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; adb root se controla internamente'
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la dependencia: $command_name"
  done
}

resolve_commands() {
  ADB_COMMAND="$(command -v adb 2>/dev/null || true)"
  CERTUTIL_COMMAND="$(command -v certutil 2>/dev/null || true)"
  CURL_COMMAND="$(command -v curl 2>/dev/null || true)"
}

package_state() {
  if command -v dpkg-query >/dev/null 2>&1 && \
    dpkg-query -W -f='${Status}' libnss3-tools 2>/dev/null | \
    grep -Fqx 'install ok installed'; then
    printf 'instalado\n'
  else
    printf 'ausente\n'
  fi
}

show_status() {
  local state source_state source_hash
  printf '═══ CA Mozilla para Firefox OS ═══\n'
  state="$(package_state)"
  if [[ "$state" == instalado ]]; then
    ok 'libnss3-tools instalado'
  else
    warn 'libnss3-tools no está instalado; ejecuta just install-firefoxos-ca-tools --apply'
  fi
  if [[ -n "$CERTUTIL_COMMAND" ]]; then
    ok "certutil disponible: $CERTUTIL_COMMAND"
  else
    warn 'certutil no está disponible'
  fi
  if [[ -f "$SOURCE_FILE" ]]; then
    source_hash="$(sha256sum -- "$SOURCE_FILE" 2>/dev/null | awk '{print $1}' || true)"
    if [[ "$source_hash" == "$CERTDATA_SHA256" ]]; then
      source_state='verificada'
    else
      source_state='hash incorrecto'
    fi
    printf 'fuente NSS %s: %s\n' "$NSS_RELEASE" "$source_state"
  else
    info "fuente NSS ${NSS_RELEASE}: aún no adquirida"
  fi
  if [[ -f "$SOURCE_MANIFEST" ]]; then
    ok 'manifiesto de raíces serverAuth generado'
  else
    info 'manifiesto de raíces serverAuth: aún no generado'
  fi
  if [[ -n "$ADB_COMMAND" ]]; then
    show_adb_status
  else
    info 'adb no está disponible; el estado del teléfono no se consulta'
  fi
  info 'no se compila B2G, no se reemplaza libnssckbi.so y no se acepta una excepción HTTPS'
}

show_adb_status() {
  local devices_output serial state total=0 authorized=0 unauthorized=0 offline=0 other=0
  if ! devices_output="$($ADB_COMMAND devices 2>/dev/null)"; then
    warn 'adb no pudo consultar los dispositivos'
    return 0
  fi
  while IFS='|' read -r serial state; do
    [[ -n "$serial" ]] || continue
    total=$((total + 1))
    case "$state" in
      device) authorized=$((authorized + 1)) ;;
      unauthorized) unauthorized=$((unauthorized + 1)) ;;
      offline) offline=$((offline + 1)) ;;
      *) other=$((other + 1)) ;;
    esac
  done < <(awk 'NR > 1 && NF >= 2 { print $1 "|" $2 }' <<< "$devices_output")
  printf 'ADB: total=%d autorizado=%d unauthorized=%d offline=%d otros=%d\n' \
    "$total" "$authorized" "$unauthorized" "$offline" "$other"
}

verify_source_file() {
  local source_path="$1" actual_hash cert_count
  [[ -f "$source_path" && -r "$source_path" ]] || die "no existe una fuente legible: $source_path"
  [[ ! -L "$source_path" ]] || die 'la fuente no puede ser un enlace simbólico'
  require_commands sha256sum awk grep
  actual_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
  [[ "$actual_hash" == "$CERTDATA_SHA256" ]] || {
    printf 'SHA-256 obtenido: %s\n' "$actual_hash"
    die 'SHA-256 de certdata.txt no coincide con la versión NSS fijada'
  }
  grep -Fq 'CKO_CERTIFICATE' -- "$source_path" || die 'la fuente no contiene objetos de certificado NSS'
  grep -Fq 'CKO_NSS_TRUST' -- "$source_path" || die 'la fuente no contiene objetos de confianza NSS'
  cert_count="$(awk '/^CKA_CLASS CK_OBJECT_CLASS CKO_CERTIFICATE$/ { count++ } END { print count + 0 }' "$source_path")"
  (( cert_count > 0 )) || die 'la fuente no contiene certificados'
  printf '%s\n' "$actual_hash"
  printf '%s\n' "$cert_count"
}

source_summary() {
  local source_path="$1"
  python3 - "$source_path" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
starts = list(re.finditer(r"^CKA_CLASS CK_OBJECT_CLASS (CKO_[A-Z_]+)\n", text, re.M))
certificates = 0
trusted_server = 0
for index, match in enumerate(starts):
    end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
    block = text[match.start():end]
    if match.group(1) == "CKO_CERTIFICATE":
        certificates += 1
    elif match.group(1) == "CKO_NSS_TRUST":
        trusted_server += int(bool(re.search(
            r"^CKA_TRUST_SERVER_AUTH CK_TRUST CKT_NSS_TRUSTED_DELEGATOR$",
            block,
            re.M,
        )))
print(f"certificados={certificates} raíces_serverAuth={trusted_server}")
PY
}

acquire_source() {
  local temporary source_hash
  require_commands curl sha256sum awk mkdir mktemp mv
  mkdir -p -- "$SOURCE_ROOT"
  if [[ -e "$SOURCE_FILE" ]]; then
    verify_source_file "$SOURCE_FILE" >/dev/null
    if [[ ! -f "$SOURCE_MANIFEST" ]]; then
      generate_bundle "$SOURCE_FILE" "$SOURCE_CERTS_ROOT" "$SOURCE_MANIFEST" >/dev/null
    fi
    ok "fuente NSS ${NSS_RELEASE} ya está verificada"
    return 0
  fi
  temporary="$(mktemp "${SOURCE_FILE}.tmp.XXXXXX")"
  info "descargando certdata.txt desde NSS ${NSS_RELEASE}"
  if ! "$CURL_COMMAND" -fsSL --proto '=https' --tlsv1.2 --max-time 120 \
    --retry 2 "$CERTDATA_URL" -o "$temporary"; then
    rm -f -- "$temporary"
    die 'no se pudo descargar certdata.txt desde Mozilla'
  fi
  source_hash="$(sha256sum -- "$temporary" | awk '{print $1}')"
  if [[ "$source_hash" != "$CERTDATA_SHA256" ]]; then
    rm -f -- "$temporary"
    printf 'SHA-256 obtenido: %s\n' "$source_hash"
    die 'la descarga no coincide con el artefacto NSS fijado'
  fi
  verify_source_file "$temporary" >/dev/null
  mv -- "$temporary" "$SOURCE_FILE"
  generate_bundle "$SOURCE_FILE" "$SOURCE_CERTS_ROOT" "$SOURCE_MANIFEST" >/dev/null
  ok "fuente NSS ${NSS_RELEASE} guardada y verificada"
  source_summary "$SOURCE_FILE"
}

generate_bundle() {
  local source_path="$1" output_dir="$2" manifest_path="$3"
  mkdir -p -- "$output_dir"
  python3 - "$source_path" "$output_dir" "$manifest_path" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
manifest = Path(sys.argv[3])
text = source.read_text(encoding="utf-8")
starts = list(re.finditer(r"^CKA_CLASS CK_OBJECT_CLASS (CKO_[A-Z_]+)\n", text, re.M))
certificates = {}
trust = {}

def octal_block(block: str, name: str) -> bytes:
    match = re.search(rf"^{re.escape(name)} MULTILINE_OCTAL\n(.*?)^END$", block, re.M | re.S)
    if not match:
        raise ValueError(f"falta {name}")
    return bytes(int(item, 8) for item in re.findall(r"\\([0-7]{3})", match.group(1)))

def label_of(block: str) -> str:
    match = re.search(r'^CKA_LABEL UTF8 "(.*)"$', block, re.M)
    return match.group(1).replace('\\"', '"') if match else "sin nombre"

for index, match in enumerate(starts):
    end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
    block = text[match.start():end]
    kind = match.group(1)
    if kind == "CKO_CERTIFICATE":
        der = octal_block(block, "CKA_VALUE")
        certificates[hashlib.sha1(der).digest()] = (label_of(block), der)
    elif kind == "CKO_NSS_TRUST":
        sha1 = octal_block(block, "CKA_CERT_SHA1_HASH")
        server_auth = bool(re.search(
            r"^CKA_TRUST_SERVER_AUTH CK_TRUST CKT_NSS_TRUSTED_DELEGATOR$",
            block,
            re.M,
        ))
        trust[sha1] = (label_of(block), server_auth)

selected = []
for sha1, (label, server_auth) in trust.items():
    if server_auth and sha1 in certificates:
        cert_label, der = certificates[sha1]
        selected.append((cert_label or label, der))
selected.sort(key=lambda item: item[0].casefold())
if not selected:
    raise SystemExit("la fuente no produjo raíces serverAuth")

rows = []
for number, (label, der) in enumerate(selected, start=1):
    filename = f"cert-{number:03d}.der"
    (output / filename).write_bytes(der)
    digest = hashlib.sha256(der).hexdigest()
    safe_label = re.sub(r"[^A-Za-z0-9 ._()-]+", "_", label).strip() or "sin-nombre"
    safe_label = safe_label[:100]
    nickname = f"Rafex Mozilla {number:03d} {safe_label}"
    rows.append(f"{digest}\t{filename}\t{nickname}\t{safe_label}\n")

manifest.write_text("".join(rows), encoding="utf-8")
print(f"raíces_serverAuth={len(rows)}")
PY
}

query_adb_device() {
  local devices_output serial state total=0 authorized=0
  [[ -n "$ADB_COMMAND" ]] || die 'adb no está instalado; ejecuta just install-android-tools --apply'
  devices_output="$($ADB_COMMAND devices 2>/dev/null)" || die 'adb no pudo consultar los dispositivos'
  while IFS='|' read -r serial state; do
    [[ -n "$serial" ]] || continue
    total=$((total + 1))
    case "$state" in
      device)
        authorized=$((authorized + 1))
        DEVICE_SERIAL="$serial"
        ;;
    esac
  done < <(awk 'NR > 1 && NF >= 2 { print $1 "|" $2 }' <<< "$devices_output")
  [[ "$total" -eq 1 && "$authorized" -eq 1 ]] ||
    die 'se requiere exactamente un Flame autorizado en estado device; no se muestran seriales'
}

adb_prop() {
  local property="$1"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell getprop "$property" 2>/dev/null | tr -d '\r' | sed -n '1p'
}

find_remote_profile() {
  local listing profile count=0
  # shellcheck disable=SC2016
  listing="$(
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell sh -c \
      'for p in /data/b2g/mozilla/*.default*; do [ -d "$p" ] && printf "%s\n" "$p"; done' \
      2>/dev/null
  )" || die 'no se pudo consultar el perfil de Firefox OS'
  while IFS= read -r profile; do
    profile="${profile//$'\r'/}"
    [[ -n "$profile" ]] || continue
    [[ "$profile" =~ ^/data/b2g/mozilla/[A-Za-z0-9._-]+$ ]] ||
      die 'el nombre del perfil remoto contiene caracteres no permitidos'
    PROFILE_PATH="$profile"
    count=$((count + 1))
  done <<< "$listing"
  [[ "$count" -eq 1 ]] || die 'se requiere exactamente un perfil Firefox OS .default'
  REMOTE_DB="${PROFILE_PATH}/cert9.db"
}

validate_remote_database() {
  local metadata mode uid gid
  metadata="$("$ADB_COMMAND" -s "$DEVICE_SERIAL" shell ls -ln "$REMOTE_DB" 2>/dev/null | tr -d '\r')" ||
    die 'no se pudo leer la metadata de cert9.db'
  mode="$(awk 'NR == 1 { print $1 }' <<< "$metadata")"
  uid="$(awk 'NR == 1 { print $3 }' <<< "$metadata")"
  gid="$(awk 'NR == 1 { print $4 }' <<< "$metadata")"
  [[ "$mode" == -rw------- && "$uid" == 0 && "$gid" == 0 ]] ||
    die 'cert9.db no tiene la metadata root:root 600 esperada; no se sobrescribirá'
}

require_flame_device() {
  local model device debuggable
  query_adb_device
  model="$(adb_prop ro.product.model)"
  device="$(adb_prop ro.product.device)"
  debuggable="$(adb_prop ro.debuggable)"
  [[ "$device" == flame ]] || die "el dispositivo ADB no es Flame: ${device:-N/D}"
  [[ "$model" == flame || "$model" == *Flame* ]] || die "el modelo no parece Flame: ${model:-N/D}"
  [[ "$debuggable" == 1 ]] || die 'el firmware no anuncia ro.debuggable=1; no se intentará adb root'
}

preflight_device() {
  local b2g_library
  require_flame_device
  if "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test -r /system/b2g/libnssckbi.so >/dev/null 2>&1; then
    b2g_library=0
  else
    b2g_library=1
  fi
  [[ "$b2g_library" == 0 ]] || die 'no se encuentra libnssckbi.so en el sistema B2G'
  printf '═══ Preflight CA Firefox OS ═══\n'
  ok 'un único Flame autorizado en ADB'
  ok 'modelo y dispositivo identificados como Flame'
  ok 'firmware root-capable detectado mediante ro.debuggable=1'
  ok 'libnssckbi.so presente; cert9.db se localizará con adb root durante --apply'
  printf 'NSS fuente fijada: %s\n' "$NSS_RELEASE"
  printf 'raíces Mozilla previstas: '
  if [[ -f "$SOURCE_FILE" ]]; then
    verify_source_file "$SOURCE_FILE" >/dev/null
    source_summary "$SOURCE_FILE"
  else
    die 'falta adquirir y verificar la fuente; ejecuta just firefoxos-ca --acquire'
  fi
  info 'preflight no reinicia, no detiene B2G y no escribe en el teléfono'
}

create_work_dir() {
  require_commands mktemp mkdir cp chmod stat sha256sum awk grep tr sed date
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafex-firefoxos-ca.XXXXXX")" ||
    die 'no se pudo crear el directorio temporal privado'
  chmod 700 -- "$WORK_DIR"
}

start_root_adb() {
  local root_output root_uid="" attempt
  root_output="$($ADB_COMMAND -s "$DEVICE_SERIAL" root 2>&1)" || {
    printf '%s\n' "$root_output" >&2
    die 'adb root no está disponible para este firmware'
  }
  ROOT_ADB_ACTIVE=1
  # `adb root` reinicia adbd. En el Flame la conexión puede tardar varios
  # segundos en reaparecer; no se debe interpretar esa ventana como un fallo.
  for ((attempt = 1; attempt <= 10; attempt++)); do
    if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
      root_uid="$(adb_prop_shell id -u || true)"
      if [[ "$root_uid" == 0 ]]; then
        ok 'adb root habilitado temporalmente para la operación explícita'
        return 0
      fi
    fi
    sleep 1
  done
  die 'adb root no confirmó uid 0 después de esperar la reconexión'
}

adb_prop_shell() {
  local command_text="$*"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell "$command_text" 2>/dev/null | tr -d '\r' | sed -n '1p'
}

stop_b2g() {
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell stop b2g >/dev/null 2>&1 || die 'no se pudo detener B2G de forma controlada'
  B2G_STOPPED=1
  sleep 2
  ok 'B2G detenido antes de abrir cert9.db'
}

prepare_database() {
  local original_db="$WORK_DIR/original-cert9.db" db_dir="$WORK_DIR/db" rollback_dir
  mkdir -p -- "$ROLLBACK_ROOT"
  rollback_dir="$(mktemp -d "${ROLLBACK_ROOT}/$(date +%Y%m%d-%H%M%S).XXXXXX")"
  mkdir -p -- "$rollback_dir" "$db_dir"
  chmod 700 -- "$rollback_dir" "$db_dir"
  info 'extrayendo cert9.db y creando rollback mínimo'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull "$REMOTE_DB" "$original_db" >/dev/null ||
    die 'no se pudo extraer cert9.db'
  [[ -s "$original_db" ]] || die 'la copia extraída de cert9.db está vacía'
  cp -p -- "$original_db" "${rollback_dir}/cert9.db"
  chmod 600 -- "${rollback_dir}/cert9.db"
  cp -p -- "$original_db" "${db_dir}/cert9.db"
  chmod 600 -- "${db_dir}/cert9.db"
  printf '%s\n' "$rollback_dir" > "${WORK_DIR}/rollback-path"
  printf '%s\n' "$(sha256sum -- "$original_db" | awk '{print $1}')" > "${WORK_DIR}/original-sha256"
  ok 'rollback mínimo guardado fuera del repositorio'
  "$CERTUTIL_COMMAND" -L -d "sql:${db_dir}" >/dev/null 2>&1 ||
    die 'certutil no puede leer la copia de cert9.db; no se modificará el teléfono'
}

import_bundle() {
  local db_dir="$WORK_DIR/db" cert_dir="$WORK_DIR/certs" manifest="$WORK_DIR/manifest.tsv"
  local digest filename nickname label cert_path current_digest count=0
  generate_bundle "$SOURCE_FILE" "$cert_dir" "$manifest" >/dev/null
  while IFS=$'\t' read -r digest filename nickname label; do
    [[ -n "$digest" && -n "$filename" && -n "$nickname" ]] || die 'manifiesto de certificados inválido'
    cert_path="${cert_dir}/${filename}"
    : "$label"
    [[ -f "$cert_path" ]] || die "falta certificado generado: $filename"
    current_digest="$(sha256sum -- "$cert_path" | awk '{print $1}')"
    [[ "$current_digest" == "$digest" ]] || die "hash inválido en certificado: $filename"
    if "$CERTUTIL_COMMAND" -L -d "sql:${db_dir}" -n "$nickname" >/dev/null 2>&1; then
      "$CERTUTIL_COMMAND" -D -d "sql:${db_dir}" -n "$nickname" >/dev/null 2>&1 ||
        die "no se pudo reemplazar el certificado administrado: $nickname"
    fi
    "$CERTUTIL_COMMAND" -A -d "sql:${db_dir}" -n "$nickname" -t 'C,,' -i "$cert_path" >/dev/null 2>&1 ||
      die "no se pudo importar el certificado: $nickname"
    count=$((count + 1))
  done < "$manifest"
  (( count > 0 )) || die 'no se importaron raíces Mozilla'
  "$CERTUTIL_COMMAND" -L -d "sql:${db_dir}" >/dev/null 2>&1 ||
    die 'la base NSS modificada no supera la lectura final con certutil'
  printf '%s\n' "$count" > "${WORK_DIR}/imported-count"
  ok "raíces Mozilla importadas en la copia: $count"
}

push_database() {
  local db_dir="$WORK_DIR/db" staged_remote="${REMOTE_DB}.new" expected_hash actual_hash
  expected_hash="$(sha256sum -- "${db_dir}/cert9.db" | awk '{print $1}')"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test '!' -e "$staged_remote" >/dev/null 2>&1 ||
    die 'ya existe cert9.db.new en el teléfono; no se sobrescribirá'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" push "${db_dir}/cert9.db" "$staged_remote" >/dev/null ||
    die 'no se pudo subir cert9.db.new'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chown 0:0 "$staged_remote" >/dev/null 2>&1 ||
    die 'no se pudo asignar root:root a cert9.db.new'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chmod 600 "$staged_remote" >/dev/null 2>&1 ||
    die 'no se pudieron restaurar los permisos 600 de cert9.db.new'
  actual_hash="$("$ADB_COMMAND" -s "$DEVICE_SERIAL" shell sha256sum "$staged_remote" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  [[ "$actual_hash" == "$expected_hash" ]] || die 'el hash remoto de cert9.db.new no coincide'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell mv "$staged_remote" "$REMOTE_DB" >/dev/null 2>&1 ||
    die 'no se pudo sustituir cert9.db de forma atómica'
  B2G_STOPPED=0
  ok 'cert9.db sustituido de forma atómica'
}

wait_for_normal_adb() {
  local attempt uid
  for ((attempt = 1; attempt <= 30; attempt++)); do
    if "$ADB_COMMAND" wait-for-device >/dev/null 2>&1; then
      uid="$(adb_prop_shell id -u || true)"
      if [[ "$uid" == 2000 ]]; then
        ROOT_ADB_ACTIVE=0
        ok 'ADB volvió al modo normal después del reinicio'
        return 0
      fi
    fi
    sleep 2
  done
  warn 'no se pudo confirmar en 60 segundos que ADB volvió al modo normal'
  return 1
}

apply_change() {
  local imported rollback_dir
  [[ "$CONFIRMATION" == "$CONFIRM_APPLY" ]] ||
    die "confirmación incorrecta; escribe exactamente $CONFIRM_APPLY"
  require_commands adb python3 certutil sha256sum awk grep tr sed date seq sleep
  [[ -f "$SOURCE_FILE" ]] || die 'falta la fuente; ejecuta --acquire antes de --apply'
  verify_source_file "$SOURCE_FILE" >/dev/null
  require_flame_device
  preflight_device >/dev/null
  create_work_dir
  start_root_adb
  find_remote_profile
  validate_remote_database
  stop_b2g
  prepare_database
  import_bundle
  imported="$(cat "${WORK_DIR}/imported-count")"
  rollback_dir="$(cat "${WORK_DIR}/rollback-path")"
  printf '═══ Aplicación CA Mozilla en Flame ═══\n'
  printf 'raíces importadas: %s\n' "$imported"
  printf 'rollback mínimo: guardado localmente\n'
  info 'escribiendo únicamente cert9.db; no se tocan /system ni particiones'
  push_database
  info 'reiniciando el teléfono para recargar NSS'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1 || die 'no se pudo reiniciar el teléfono'
  wait_for_normal_adb || return 1
  ok 'cambio aplicado; prueba HTTPS sin aceptar excepciones permanentes'
  info "si la navegación no mejora, usa --rollback; copia disponible en ${rollback_dir}"
}

latest_rollback() {
  [[ -d "$ROLLBACK_ROOT" ]] || die 'no existe un rollback local de cert9.db'
  find "$ROLLBACK_ROOT" -mindepth 2 -maxdepth 2 -type f -name cert9.db \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
}

rollback_change() {
  local backup_path db_hash staged_remote metadata
  [[ "$CONFIRMATION" == "$CONFIRM_ROLLBACK" ]] ||
    die "confirmación incorrecta; escribe exactamente $CONFIRM_ROLLBACK"
  require_commands adb sha256sum awk grep tr sed date seq sleep find sort stat
  require_flame_device
  backup_path="$(latest_rollback)"
  [[ -f "$backup_path" && -r "$backup_path" ]] || die 'el rollback más reciente no es legible'
  [[ "$(stat -c '%u' -- "$backup_path")" == "$(id -u)" ]] || die 'el rollback no pertenece al usuario actual'
  db_hash="$(sha256sum -- "$backup_path" | awk '{print $1}')"
  [[ -n "$db_hash" ]] || die 'no se pudo calcular el hash del rollback'
  start_root_adb
  find_remote_profile
  validate_remote_database
  stop_b2g
  staged_remote="${REMOTE_DB}.new"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test '!' -e "$staged_remote" >/dev/null 2>&1 ||
    die 'ya existe cert9.db.new en el teléfono; no se sobrescribirá'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" push "$backup_path" "$staged_remote" >/dev/null ||
    die 'no se pudo subir el rollback de cert9.db'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chown 0:0 "$staged_remote" >/dev/null 2>&1 || die 'no se pudo asignar root:root al rollback'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chmod 600 "$staged_remote" >/dev/null 2>&1 || die 'no se pudieron restaurar los permisos del rollback'
  metadata="$("$ADB_COMMAND" -s "$DEVICE_SERIAL" shell sha256sum "$staged_remote" 2>/dev/null | tr -d '\r')"
  [[ "$(awk '{print $1}' <<< "$metadata")" == "$db_hash" ]] || die 'el hash remoto del rollback no coincide'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell mv "$staged_remote" "$REMOTE_DB" >/dev/null 2>&1 || die 'no se pudo restaurar cert9.db'
  B2G_STOPPED=0
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1 || die 'no se pudo reiniciar tras el rollback'
  wait_for_normal_adb || return 1
  ok 'cert9.db restaurado; no se modificó ninguna otra parte del teléfono'
}

test_change() {
  local db_dir db_copy cert_count managed_count cert_list
  require_commands adb certutil mktemp mkdir chmod sha256sum awk grep tr sed sleep
  require_flame_device
  start_root_adb
  find_remote_profile
  db_dir="$(mktemp -d "${TMPDIR:-/tmp}/rafex-firefoxos-ca-test.XXXXXX")"
  WORK_DIR="$db_dir"
  chmod 700 -- "$db_dir"
  db_copy="${db_dir}/cert9.db"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull "$REMOTE_DB" "$db_copy" >/dev/null || die 'no se pudo extraer cert9.db para la prueba'
  chmod 600 -- "$db_copy"
  cert_list="$("$CERTUTIL_COMMAND" -L -d "sql:$db_dir" 2>/dev/null)" ||
    die 'certutil no pudo leer la copia de cert9.db'
  cert_count="$(wc -l <<< "$cert_list" | awk '{print $1}')"
  managed_count="$(grep -Fc 'Rafex Mozilla ' <<< "$cert_list" || true)"
  printf '═══ Prueba de CA Firefox OS ═══\n'
  printf 'entradas NSS legibles: %s\n' "$cert_count"
  printf 'raíces administradas detectadas: %s\n' "$managed_count"
  (( managed_count > 0 )) || die 'no se detectan raíces Rafex en cert9.db'
  restore_normal_adb || die 'no se pudo devolver ADB al modo normal'
  ok 'cert9.db legible y contiene raíces administradas'
  info 'la prueba HTTPS del navegador debe hacerse manualmente sin aceptar excepciones'
}

show_plan() {
  printf '═══ Plan CA Mozilla para Firefox OS ═══\n'
  printf 'fuente fija: %s\n' "$NSS_RELEASE"
  printf 'SHA-256: %s\n' "$CERTDATA_SHA256"
  info 'descargar certdata.txt desde Mozilla y verificar su hash'
  info 'seleccionar únicamente raíces serverAuth confiables de Mozilla'
  info 'extraer cert9.db, guardar rollback mínimo e importar con certutil'
  info 'detener B2G, subir cert9.db.new, validar hash, sustituir y reiniciar'
  info 'usar adb root temporal; volver a ADB normal tras reiniciar'
  info 'no compilar B2G, no reemplazar libnssckbi.so, no tocar particiones ni red'
  info "confirmación requerida: $CONFIRM_APPLY"
}

main() {
  parse_args "$@"
  require_linux_user
  resolve_commands
  case "$ACTION" in
    status)
      require_commands sha256sum awk grep
      show_status
      ;;
    plan)
      show_plan
      ;;
    acquire)
      [[ -n "$CURL_COMMAND" ]] || die 'falta curl para --acquire'
      acquire_source
      ;;
    verify-source)
      require_commands python3 sha256sum awk grep
      [[ -f "$SOURCE_FILE" ]] || die 'fuente no adquirida; ejecuta --acquire'
      printf '═══ Verificación de fuente CA Mozilla ═══\n'
      verify_source_file "$SOURCE_FILE" >/dev/null
      ok "SHA-256 coincide: $NSS_RELEASE"
      source_summary "$SOURCE_FILE"
      ;;
    preflight)
      require_commands adb python3 sha256sum awk grep tr sed
      preflight_device
      ;;
    apply) apply_change ;;
    test) test_change ;;
    rollback) rollback_change ;;
    *) die "acción interna no soportada: $ACTION" ;;
  esac
}

main "$@"
