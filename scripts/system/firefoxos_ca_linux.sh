#!/usr/bin/env bash
# v1.3.2 - Valida el runtime NSS/B2G exacto antes de tocar un Flame.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly NSS_RELEASE="NSS_3_128_RTM"
readonly CERTDATA_URL="https://hg.mozilla.org/projects/nss/raw-file/${NSS_RELEASE}/lib/ckfw/builtins/certdata.txt"
readonly CERTDATA_SHA256="81b7f2576333a2e360e673f912d7b0b7a765d836c731003e348a46cac5d37198"
readonly NSS_VERSION="3.21"
readonly NSPR_VERSION="4.11"
readonly CA_IMAGE="localhost/rafex/firefoxos-ca:b2g46-flame"
readonly BASELINE_IMAGE="localhost/rafex/firefoxos-ca:nss-3.21"
readonly EXPECTED_B2G_VERSION="46.0a1"
readonly EXPECTED_B2G_BUILD_ID="20151221215202"
readonly EXPECTED_B2G_SOURCE_REPOSITORY="4a4a0bcf45995fdc29caefba2766932dfc25be7d"
readonly STATE_ROOT="${HOME}/.local/share/rafex/firefoxos-ca"
readonly SOURCE_ROOT="${STATE_ROOT}/sources"
readonly RUNTIME_ROOT="${STATE_ROOT}/runtime"
readonly RUNTIME_MANIFEST="${RUNTIME_ROOT}/flame-runtime.env"
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
PODMAN_COMMAND=""
CURL_COMMAND=""
DEVICE_SERIAL=""
PROFILE_PATH=""
REMOTE_DB=""
REMOTE_KEY_DB=""
REMOTE_PKCS11=""
WORK_DIR=""
B2G_STOPPED=0
ROOT_ADB_ACTIVE=0
STAGED_REMOTE_CREATED=0

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_ca_linux.sh --status
  firefoxos_ca_linux.sh --check
  firefoxos_ca_linux.sh --plan
  firefoxos_ca_linux.sh --acquire
  firefoxos_ca_linux.sh --verify-source
  firefoxos_ca_linux.sh --identify-runtime
  firefoxos_ca_linux.sh --preflight
  firefoxos_ca_linux.sh --apply --confirm FLAME-MOZILLA-CA-WIPE
  firefoxos_ca_linux.sh --test
  firefoxos_ca_linux.sh --rollback --confirm FLAME-CA-ROLLBACK

Valida el runtime NSS del build B2G observado y prepara una actualización
reversible del conjunto NSS del perfil Flame. No usa el flash.sh incluido,
no reemplaza libnssckbi.so y se detiene si falta el bundle B2G exacto.
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
      --identify-runtime) choose_action identify-runtime ;;
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
  PODMAN_COMMAND="$(command -v podman 2>/dev/null || true)"
  CURL_COMMAND="$(command -v curl 2>/dev/null || true)"
}

manifest_value() {
  local manifest="$1" key="$2"
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$manifest"
}

image_label() {
  "$PODMAN_COMMAND" image inspect --format "{{ index .Config.Labels \"$2\" }}" "$1" 2>/dev/null || true
}

runtime_manifest_field() {
  [[ -f "$RUNTIME_MANIFEST" ]] || return 1
  manifest_value "$RUNTIME_MANIFEST" "$1"
}

restore_normal_adb() {
  local attempt uid="" unroot_output
  [[ "$ROOT_ADB_ACTIVE" -eq 1 && -n "$ADB_COMMAND" && -n "$DEVICE_SERIAL" ]] || return 0

  if ! unroot_output="$($ADB_COMMAND -s "$DEVICE_SERIAL" unroot 2>&1)"; then
    warn 'adb unroot no fue aceptado por el adbd del Flame'
    [[ -n "$unroot_output" ]] && warn 'se usará un reinicio controlado si la conexión sigue disponible'
  fi
  for ((attempt = 1; attempt <= 15; attempt++)); do
    if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
      uid="$(adb_uid || true)"
      if [[ "$uid" == 2000 ]]; then
        ROOT_ADB_ACTIVE=0
        return 0
      fi
    fi
    sleep 1
  done

  if [[ "$uid" == 0 ]]; then
    if ! "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1; then
      warn 'no se pudo reiniciar el Flame para salir de adb root; desconecta y vuelve a conectar el cable'
      return 1
    fi
    for ((attempt = 1; attempt <= 30; attempt++)); do
      if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
        uid="$(adb_uid || true)"
        if [[ "$uid" == 2000 ]]; then
          ROOT_ADB_ACTIVE=0
          return 0
        fi
      fi
      sleep 2
    done
  fi
  warn 'no se pudo confirmar ADB en modo usuario; no se ejecutará stop adbd; revisa el cable y reconecta el teléfono'
  return 1
}

cleanup() {
  local cleanup_status=$?
  if [[ "$STAGED_REMOTE_CREATED" -eq 1 && "$ROOT_ADB_ACTIVE" -eq 1 && -n "$ADB_COMMAND" && -n "$DEVICE_SERIAL" && -n "$REMOTE_DB" ]]; then
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell rm -f "${REMOTE_DB}.new" >/dev/null 2>&1 ||
      warn 'no se pudo retirar el temporal cert9.db.new; no se volverá a intentar automáticamente'
    STAGED_REMOTE_CREATED=0
  fi
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

package_state() {
  if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' podman 2>/dev/null | grep -Fqx 'install ok installed'; then
    printf 'instalado\n'
  else
    printf 'ausente\n'
  fi
}

legacy_runtime_probe() {
  "$PODMAN_COMMAND" run --rm --network=none --cap-drop=all --security-opt=no-new-privileges \
    --read-only --userns=keep-id --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev --entrypoint /bin/sh "$CA_IMAGE" -c \
    'mkdir /tmp/probe && /opt/legacy-nss/bin/certutil -N -d sql:/tmp/probe --empty-password && /opt/legacy-nss/bin/certutil -L -d sql:/tmp/probe >/dev/null'
}

require_exact_runtime() {
  local runtime_status target b2g_version build_id repository lib_hash image_lib_hash patches_hash source_tree_hash image_nss image_nspr
  [[ -n "$PODMAN_COMMAND" ]] || die 'NO-GO: falta Podman'
  [[ -f "$RUNTIME_MANIFEST" ]] || die 'NO-GO: ejecuta --identify-runtime con el Flame conectado'
  [[ "$(runtime_manifest_field B2G_VERSION)" == "$EXPECTED_B2G_VERSION" ]] || die 'NO-GO: el build B2G observado no coincide con 46.0a1'
  [[ "$(runtime_manifest_field B2G_BUILD_ID)" == "$EXPECTED_B2G_BUILD_ID" ]] || die 'NO-GO: el Build ID del Flame no coincide'
  [[ "$(runtime_manifest_field B2G_SOURCE_REPOSITORY)" == "$EXPECTED_B2G_SOURCE_REPOSITORY" ]] || die 'NO-GO: SourceRepository no coincide'
  lib_hash="$(runtime_manifest_field B2G_LIBNSS3_SHA256)"
  [[ "$lib_hash" =~ ^[[:xdigit:]]{64}$ ]] || die 'NO-GO: no se pudo obtener el hash de libnss3.so'
  "$PODMAN_COMMAND" image exists "$CA_IMAGE" >/dev/null 2>&1 || die "NO-GO: falta $CA_IMAGE; construye el bundle exacto con install-firefoxos-ca-tools"
  runtime_status="$(image_label "$CA_IMAGE" org.rafex.firefoxos.runtime-status)"
  target="$(image_label "$CA_IMAGE" org.rafex.firefoxos.target)"
  b2g_version="$(image_label "$CA_IMAGE" org.rafex.firefoxos.b2g-version)"
  build_id="$(image_label "$CA_IMAGE" org.rafex.firefoxos.build-id)"
  repository="$(image_label "$CA_IMAGE" org.rafex.firefoxos.source-repository)"
  image_lib_hash="$(image_label "$CA_IMAGE" org.rafex.firefoxos.libnss3-sha256)"
  patches_hash="$(image_label "$CA_IMAGE" org.rafex.firefoxos.nss-patches-sha256)"
  source_tree_hash="$(image_label "$CA_IMAGE" org.rafex.firefoxos.b2g-source-tree-sha256)"
  image_nss="$(image_label "$CA_IMAGE" org.rafex.firefoxos.nss)"
  image_nspr="$(image_label "$CA_IMAGE" org.rafex.firefoxos.nspr)"
  [[ "$patches_hash" == embedded-in-source && "$source_tree_hash" =~ ^[[:xdigit:]]{64}$ ]] || die 'NO-GO: la imagen no conserva el estado de parches integrado y el hash verificable del árbol B2G'
  [[ "$runtime_status" == matched && "$target" == flame && "$b2g_version" == "$EXPECTED_B2G_VERSION" && "$build_id" == "$EXPECTED_B2G_BUILD_ID" && "$repository" == "$EXPECTED_B2G_SOURCE_REPOSITORY" && "$image_lib_hash" == "$lib_hash" && "$image_nss" == "$NSS_VERSION" && "$image_nspr" == "$NSPR_VERSION" ]] ||
    die 'NO-GO: la imagen no corresponde al runtime B2G/Flame identificado; no se usará una NSS genérica'
  legacy_runtime_probe || die "NO-GO: $CA_IMAGE no puede ejecutar certutil"
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
  printf 'ADB: total=%d autorizado=%d unauthorized=%d offline=%d otros=%d\n' "$total" "$authorized" "$unauthorized" "$offline" "$other"
}

show_status() {
  local state image_status
  printf '═══ Runtime NSS del Mozilla Flame ═══\n'
  state="$(package_state)"
  if [[ "$state" == instalado ]]; then ok 'podman instalado'; else warn 'podman no está instalado'; fi
  if [[ -n "$PODMAN_COMMAND" ]]; then
    ok "Podman disponible: $PODMAN_COMMAND"
    if "$PODMAN_COMMAND" image exists "$BASELINE_IMAGE" >/dev/null 2>&1; then ok "baseline NSS presente: $BASELINE_IMAGE (diagnóstico solamente)"; else info "baseline NSS ausente: $BASELINE_IMAGE"; fi
    if "$PODMAN_COMMAND" image exists "$CA_IMAGE" >/dev/null 2>&1; then
      image_status="$(image_label "$CA_IMAGE" org.rafex.firefoxos.runtime-status)"
      if [[ "$image_status" == matched ]]; then ok "runtime B2G etiquetado matched: $CA_IMAGE"; else warn "runtime $CA_IMAGE no está autorizado"; fi
    else warn "runtime exacto ausente: $CA_IMAGE"; fi
  else warn 'Podman no está disponible'; fi
  if [[ -f "$RUNTIME_MANIFEST" ]]; then
    ok 'runtime del Flame identificado localmente'
    printf 'B2G: %s | Build ID: %s | NSS_GetVersion: %s\n' "$(runtime_manifest_field B2G_VERSION)" "$(runtime_manifest_field B2G_BUILD_ID)" "$(runtime_manifest_field NSS_GET_VERSION)"
    printf 'libnss3.so SHA-256: %s | arquitectura: %s\n' "$(runtime_manifest_field B2G_LIBNSS3_SHA256)" "$(runtime_manifest_field B2G_LIBNSS3_ARCH)"
  else info 'runtime del Flame aún no identificado; usa --identify-runtime'; fi
  if [[ -f "$SOURCE_FILE" ]]; then ok "certdata ${NSS_RELEASE} adquirida"; else info "certdata ${NSS_RELEASE} aún no adquirida"; fi
  if [[ -n "$ADB_COMMAND" ]]; then show_adb_status; else info 'adb no está disponible'; fi
  info 'el baseline y cualquier runtime se ejecutan rootless, sin red y sin capacidades'
  info 'la aplicación CA queda bloqueada hasta demostrar el árbol B2G exacto'
}

verify_source_file() {
  local source_path="$1" actual_hash cert_count
  [[ -f "$source_path" && -r "$source_path" && ! -L "$source_path" ]] || die "no existe una fuente legible: $source_path"
  actual_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
  [[ "$actual_hash" == "$CERTDATA_SHA256" ]] || { printf 'SHA-256 obtenido: %s\n' "$actual_hash"; die 'SHA-256 de certdata.txt no coincide'; }
  grep -Fq 'CKO_CERTIFICATE' -- "$source_path" || die 'la fuente no contiene certificados NSS'
  grep -Fq 'CKO_NSS_TRUST' -- "$source_path" || die 'la fuente no contiene bloques de confianza NSS'
  cert_count="$(awk '/^CKA_CLASS CK_OBJECT_CLASS CKO_CERTIFICATE$/ { count++ } END { print count + 0 }' "$source_path")"
  (( cert_count > 0 )) || die 'la fuente no contiene certificados'
  printf '%s\n' "$actual_hash"
}

source_summary() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
starts = list(re.finditer(r"^CKA_CLASS CK_OBJECT_CLASS (CKO_[A-Z_]+)\n", text, re.M))
certificates = 0
trusted_server = 0
for index, match in enumerate(starts):
    end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
    block = text[match.start():end]
    if match.group(1) == "CKO_CERTIFICATE":
        certificates += 1
    elif match.group(1) == "CKO_NSS_TRUST":
        trusted_server += int(bool(re.search(r"^CKA_TRUST_SERVER_AUTH CK_TRUST CKT_NSS_TRUSTED_DELEGATOR$", block, re.M)))
print(f"certificados={certificates} raíces_serverAuth={trusted_server}")
PY
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
        server_auth = bool(re.search(r"^CKA_TRUST_SERVER_AUTH CK_TRUST CKT_NSS_TRUSTED_DELEGATOR$", block, re.M))
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

acquire_source() {
  local temporary source_hash
  require_commands sha256sum awk grep mkdir mktemp mv
  mkdir -p -- "$SOURCE_ROOT"
  if [[ -e "$SOURCE_FILE" ]]; then
    verify_source_file "$SOURCE_FILE" >/dev/null
    [[ -f "$SOURCE_MANIFEST" ]] || generate_bundle "$SOURCE_FILE" "$SOURCE_CERTS_ROOT" "$SOURCE_MANIFEST" >/dev/null
    ok "fuente NSS ${NSS_RELEASE} ya está verificada"
    return 0
  fi
  [[ -n "$CURL_COMMAND" ]] || die 'falta curl para --acquire'
  temporary="$(mktemp "${SOURCE_FILE}.tmp.XXXXXX")"
  info "descargando certdata.txt desde NSS ${NSS_RELEASE}"
  if ! "$CURL_COMMAND" -fsSL --proto '=https' --tlsv1.2 --max-time 120 --retry 2 "$CERTDATA_URL" -o "$temporary"; then
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

query_adb_device() {
  local devices_output serial state total=0 authorized=0
  [[ -n "$ADB_COMMAND" ]] || die 'adb no está instalado'
  devices_output="$($ADB_COMMAND devices 2>/dev/null)" || die 'adb no pudo consultar los dispositivos'
  while IFS='|' read -r serial state; do
    [[ -n "$serial" ]] || continue
    total=$((total + 1))
    if [[ "$state" == device ]]; then authorized=$((authorized + 1)); DEVICE_SERIAL="$serial"; fi
  done < <(awk 'NR > 1 && NF >= 2 { print $1 "|" $2 }' <<< "$devices_output")
  [[ "$total" -eq 1 && "$authorized" -eq 1 ]] || die 'se requiere exactamente un Flame autorizado en estado device; no se muestran seriales'
}

adb_prop() { "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell getprop "$1" 2>/dev/null | tr -d '\r' | sed -n '1p'; }

adb_fixed_file() { "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell cat "$1" 2>/dev/null | tr -d '\r'; }

adb_file_value() {
  local path="$1" key="$2"
  adb_fixed_file "$path" | awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }'
}

require_flame_device() {
  local model device debuggable
  query_adb_device
  model="$(adb_prop ro.product.model)"
  device="$(adb_prop ro.product.device)"
  debuggable="$(adb_prop ro.debuggable)"
  [[ "$device" == flame ]] || die "el dispositivo ADB no es Flame: ${device:-N/D}"
  [[ "$model" == flame || "$model" == *Flame* ]] || die "el modelo no parece Flame: ${model:-N/D}"
  [[ "$debuggable" == 1 ]] || die 'el firmware no anuncia ro.debuggable=1'
}

adb_uid() {
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell id 2>/dev/null | tr -d '\r' | sed -n 's/^uid=\([0-9][0-9]*\).*/\1/p'
}

create_work_dir() {
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafex-firefoxos-ca.XXXXXX")"
  chmod 700 -- "$WORK_DIR"
}

identify_runtime() {
  local build_id version repository source_stamp gaia gonk lib_hash lib_size lib_arch nss_version nss_string lib_temp
  require_commands adb awk grep tr sed sha256sum mkdir mv mktemp file strings rm
  require_flame_device
  version="$(adb_file_value /system/b2g/application.ini Version)"
  build_id="$(adb_file_value /system/b2g/application.ini BuildID)"
  repository="$(adb_file_value /system/b2g/application.ini SourceRepository)"
  source_stamp="$(adb_file_value /system/b2g/application.ini SourceStamp)"
  gaia="$(adb_fixed_file /system/b2g/gaia/profile/webapps/system.gaiamobile.org/manifest.webapp | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p' || true)"
  gonk="$(adb_prop ro.build.version.incremental)"
  lib_size="$("$ADB_COMMAND" -s "$DEVICE_SERIAL" shell ls -ln /system/b2g/libnss3.so 2>/dev/null | tr -d '\r' | awk 'NR == 1 { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { print $(i - 1); exit } }')"
  lib_temp="$(mktemp "${TMPDIR:-/tmp}/rafex-libnss3.XXXXXX")"
  if ! "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull /system/b2g/libnss3.so "$lib_temp" >/dev/null; then
    rm -f -- "$lib_temp"
    die 'no se pudo extraer temporalmente libnss3.so para identificar su arquitectura'
  fi
  lib_hash="$(sha256sum -- "$lib_temp" | awk '{print $1}')"
  if ! lib_arch="$(file -b -- "$lib_temp" | sed 's/[[:space:]]\+/ /g')"; then
    rm -f -- "$lib_temp"
    die 'no se pudo identificar la arquitectura de libnss3.so'
  fi
  nss_string="$(strings -- "$lib_temp" | grep -E '^NSS [0-9]+\.[0-9]+\.[0-9]+$' | sed -n '1p' || true)"
  rm -f -- "$lib_temp"
  if [[ -n "$nss_string" ]]; then
    nss_version="unresolved (cadena '${nss_string}'; NSS_GetVersion no se ejecutó sobre la biblioteca ARM)"
  else
    nss_version='unresolved (NSS_GetVersion no se ejecutó: libnss3.so es ARM y la ThinkPad usa el runtime host)'
  fi
  [[ -n "$version" && -n "$build_id" && -n "$repository" && -n "$lib_hash" ]] || die 'no se pudo leer el manifiesto B2G o libnss3.so'
  mkdir -p -- "$RUNTIME_ROOT"
  chmod 700 -- "$RUNTIME_ROOT"
  local temporary
  temporary="$(mktemp "${RUNTIME_MANIFEST}.tmp.XXXXXX")"
  {
    printf 'RUNTIME_NAME=b2g46-flame\n'
    printf 'B2G_VERSION=%s\n' "$version"
    printf 'B2G_BUILD_ID=%s\n' "$build_id"
    printf 'B2G_SOURCE_REPOSITORY=%s\n' "$repository"
    printf 'B2G_SOURCE_STAMP=%s\n' "${source_stamp:-unresolved}"
    printf 'GAIA_VERSION=%s\n' "${gaia:-unresolved}"
    printf 'GONK_VERSION=%s\n' "${gonk:-unresolved}"
    printf 'ANDROID_BASE=%s\n' "$(adb_prop ro.build.version.release)"
    printf 'B2G_LIBNSS3_SHA256=%s\n' "$lib_hash"
    printf 'B2G_LIBNSS3_SIZE=%s\n' "${lib_size:-unresolved}"
    printf 'B2G_LIBNSS3_ARCH=%s\n' "$lib_arch"
    printf 'NSS_GET_VERSION=%s\n' "$nss_version"
  } > "$temporary"
  chmod 600 -- "$temporary"
  mv -- "$temporary" "$RUNTIME_MANIFEST"
  printf '═══ Runtime B2G/Flame identificado ═══\n'
  printf 'B2G: %s | Build ID: %s\n' "$version" "$build_id"
  printf 'SourceRepository: %s\n' "$repository"
  printf 'Gaia: %s | Gonk: %s | Android: %s\n' "${gaia:-N/D}" "${gonk:-N/D}" "$(adb_prop ro.build.version.release)"
  printf 'libnss3.so: SHA-256 %s | tamaño %s | %s\n' "$lib_hash" "${lib_size:-N/D}" "$lib_arch"
  printf 'NSS_GetVersion: %s\n' "$nss_version"
  ok 'identificación guardada sin seriales ni copia persistente de la biblioteca'
}

find_remote_profile() {
  local listing profile count=0
  listing="$($ADB_COMMAND -s "$DEVICE_SERIAL" shell ls -d /data/b2g/mozilla/*.default* 2>/dev/null)" || die 'no se pudo consultar el perfil Firefox OS'
  while IFS= read -r profile; do
    profile="${profile//$'\r'/}"
    [[ -n "$profile" ]] || continue
    [[ "$profile" =~ ^/data/b2g/mozilla/[A-Za-z0-9._-]+$ ]] || die 'el nombre del perfil remoto contiene caracteres no permitidos'
    PROFILE_PATH="$profile"
    count=$((count + 1))
  done <<< "$listing"
  [[ "$count" -eq 1 ]] || die 'se requiere exactamente un perfil Firefox OS .default'
  REMOTE_DB="${PROFILE_PATH}/cert9.db"
  REMOTE_KEY_DB="${PROFILE_PATH}/key4.db"
  REMOTE_PKCS11="${PROFILE_PATH}/pkcs11.txt"
}

validate_remote_metadata() {
  local remote_path metadata mode uid gid
  for remote_path in "$REMOTE_DB" "$REMOTE_KEY_DB" "$REMOTE_PKCS11"; do
    metadata="$($ADB_COMMAND -s "$DEVICE_SERIAL" shell ls -ln "$remote_path" 2>/dev/null | tr -d '\r')" || die "no se pudo leer metadata NSS: $remote_path"
    mode="$(awk 'NR == 1 { print $1 }' <<< "$metadata")"
    uid="$(awk 'NR == 1 { print $2 }' <<< "$metadata")"
    gid="$(awk 'NR == 1 { print $3 }' <<< "$metadata")"
    [[ "$mode" == -rw------- && "$uid" == 0 && "$gid" == 0 ]] || die "metadata inesperada en $remote_path; no se sobrescribirá"
  done
}

preflight_device() {
  local b2g_library uid
  identify_runtime >/dev/null
  require_exact_runtime
  require_flame_device
  uid="$(adb_uid)"
  [[ "$uid" == 2000 ]] || die 'NO-GO: ADB no está en uid 2000; no se iniciará root desde --preflight'
  if "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test -r /system/b2g/libnss3.so >/dev/null 2>&1; then b2g_library=0; else b2g_library=1; fi
  [[ "$b2g_library" == 0 ]] || die 'no se encuentra libnss3.so en B2G'
  printf '═══ Preflight CA Firefox OS ═══\n'
  ok 'un Flame autorizado, en ADB normal y con runtime B2G matched'
  ok 'libnss3.so presente y su hash coincide con la imagen Podman'
  printf 'NSS esperado: %s | NSPR: %s\n' "$NSS_VERSION" "$NSPR_VERSION"
  [[ -f "$SOURCE_FILE" ]] || die 'falta adquirir y verificar certdata; ejecuta --acquire'
  verify_source_file "$SOURCE_FILE" >/dev/null
  source_summary "$SOURCE_FILE"
  info 'preflight no reinicia, no detiene B2G y no escribe en el teléfono'
}

start_root_adb() {
  local root_output root_uid='' attempt
  root_output="$($ADB_COMMAND -s "$DEVICE_SERIAL" root 2>&1)" || { printf '%s\n' "$root_output" >&2; die 'adb root no está disponible para este firmware'; }
  ROOT_ADB_ACTIVE=1
  for ((attempt = 1; attempt <= 15; attempt++)); do
    if "$ADB_COMMAND" -s "$DEVICE_SERIAL" get-state >/dev/null 2>&1; then
      root_uid="$(adb_uid || true)"
      [[ "$root_uid" == 0 ]] && { ok 'adb root habilitado temporalmente'; return 0; }
    fi
    sleep 1
  done
  die 'adb root no confirmó uid 0 después de esperar la reconexión'
}

stop_b2g() {
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell stop b2g >/dev/null 2>&1 || die 'no se pudo detener B2G de forma controlada'
  B2G_STOPPED=1
  sleep 2
  ok 'B2G detenido antes de abrir el conjunto NSS'
}

prepare_database() {
  local rollback_dir db_dir remote_name local_name
  mkdir -p -- "$ROLLBACK_ROOT"
  chmod 700 -- "$ROLLBACK_ROOT"
  rollback_dir="$(mktemp -d "${ROLLBACK_ROOT}/$(date +%Y%m%d-%H%M%S).XXXXXX")"
  db_dir="${WORK_DIR}/db"
  mkdir -p -- "$rollback_dir" "$db_dir"
  chmod 700 -- "$rollback_dir" "$db_dir"
  info 'extrayendo cert9.db, key4.db y pkcs11.txt; creando rollback mínimo'
  for remote_name in cert9.db key4.db pkcs11.txt; do
    local_name="${remote_name}"
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull "${PROFILE_PATH}/${remote_name}" "${WORK_DIR}/${local_name}" >/dev/null || die "no se pudo extraer ${remote_name}"
    [[ -s "${WORK_DIR}/${local_name}" ]] || die "la copia extraída de ${remote_name} está vacía"
    cp -p -- "${WORK_DIR}/${local_name}" "${rollback_dir}/${local_name}"
    cp -p -- "${WORK_DIR}/${local_name}" "${db_dir}/${local_name}"
    chmod 600 -- "${rollback_dir}/${local_name}" "${db_dir}/${local_name}"
  done
  printf '%s\n' "$rollback_dir" > "${WORK_DIR}/rollback-path"
  sha256sum -- "${WORK_DIR}/cert9.db" "${WORK_DIR}/key4.db" "${WORK_DIR}/pkcs11.txt" > "${WORK_DIR}/original-sha256.tsv"
  ok 'rollback mínimo del conjunto NSS guardado localmente'
  legacy_certutil "$db_dir" -L -d sql:/work >/dev/null 2>&1 || die "NO-GO: $CA_IMAGE no puede leer el conjunto NSS completo del Flame"
}

legacy_certutil() {
  local mount_dir="$1"
  shift
  [[ -d "$mount_dir" && "$mount_dir" = /* ]] || die 'directorio NSS temporal inválido'
  "$PODMAN_COMMAND" run --rm --network=none --cap-drop=all --security-opt=no-new-privileges \
    --read-only --userns=keep-id --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev --volume "${mount_dir}:/work:rw" "$CA_IMAGE" "$@"
}

import_bundle() {
  local db_dir="${WORK_DIR}/db" cert_dir="${WORK_DIR}/db/certs" manifest="${WORK_DIR}/manifest.tsv"
  local digest filename nickname label cert_path current_digest count=0
  generate_bundle "$SOURCE_FILE" "$cert_dir" "$manifest" >/dev/null
  while IFS=$'\t' read -r digest filename nickname label; do
    [[ -n "$digest" && -n "$filename" && -n "$nickname" ]] || die 'manifiesto de certificados inválido'
    : "$label"
    cert_path="${cert_dir}/${filename}"
    [[ -f "$cert_path" ]] || die "falta certificado generado: $filename"
    current_digest="$(sha256sum -- "$cert_path" | awk '{print $1}')"
    [[ "$current_digest" == "$digest" ]] || die "hash inválido en certificado: $filename"
    if legacy_certutil "$db_dir" -L -d sql:/work -n "$nickname" >/dev/null 2>&1; then
      legacy_certutil "$db_dir" -D -d sql:/work -n "$nickname" >/dev/null 2>&1 || die "no se pudo reemplazar $nickname"
    fi
    legacy_certutil "$db_dir" -A -d sql:/work -n "$nickname" -t 'C,,' -i "/work/certs/${filename}" >/dev/null 2>&1 || die "no se pudo importar $nickname"
    count=$((count + 1))
  done < "$manifest"
  (( count > 0 )) || die 'no se importaron raíces Mozilla'
  legacy_certutil "$db_dir" -L -d sql:/work >/dev/null 2>&1 || die 'la base NSS modificada no supera la lectura final'
  printf '%s\n' "$count" > "${WORK_DIR}/imported-count"
  ok "raíces Mozilla importadas en la copia: $count"
}

verify_remote_stage_hash() {
  local staged_remote="$1" expected_hash="$2" downloaded_path="$3" actual_hash
  rm -f -- "$downloaded_path"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull "$staged_remote" "$downloaded_path" >/dev/null ||
    die 'no se pudo descargar el temporal para verificarlo localmente'
  [[ -s "$downloaded_path" ]] || die 'el temporal descargado está vacío'
  actual_hash="$(sha256sum -- "$downloaded_path" | awk '{print $1}')"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    warn "hash local esperado: $expected_hash"
    warn "hash local extraído: $actual_hash"
    die 'el hash local de cert9.db.new no coincide'
  fi
  ok 'cert9.db.new verificado mediante descarga y hash local'
}

clear_stale_remote_stage() {
  local staged_remote="${REMOTE_DB}.new"
  if "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test -e "$staged_remote" >/dev/null 2>&1; then
    warn 'se encontró un cert9.db.new temporal de una ejecución anterior; se eliminará antes de continuar'
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell rm -f "$staged_remote" >/dev/null 2>&1 ||
      die 'no se pudo eliminar el cert9.db.new temporal anterior'
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test '!' -e "$staged_remote" >/dev/null 2>&1 ||
      die 'el cert9.db.new temporal anterior sigue presente'
    ok 'temporal cert9.db.new anterior eliminado; cert9.db original no fue tocado'
  fi
}

push_database() {
  local db_dir="${WORK_DIR}/db" staged_remote="${REMOTE_DB}.new" expected_hash
  expected_hash="$(sha256sum -- "${db_dir}/cert9.db" | awk '{print $1}')"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test '!' -e "$staged_remote" >/dev/null 2>&1 || die 'ya existe cert9.db.new; no se sobrescribirá'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" push "${db_dir}/cert9.db" "$staged_remote" >/dev/null || die 'no se pudo subir cert9.db.new'
  STAGED_REMOTE_CREATED=1
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chown 0:0 "$staged_remote" >/dev/null 2>&1 || die 'no se pudo asignar root:root'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chmod 600 "$staged_remote" >/dev/null 2>&1 || die 'no se pudieron restaurar permisos 600'
  verify_remote_stage_hash "$staged_remote" "$expected_hash" "${WORK_DIR}/cert9.db.remote"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell mv "$staged_remote" "$REMOTE_DB" >/dev/null 2>&1 || die 'no se pudo sustituir cert9.db de forma atómica'
  STAGED_REMOTE_CREATED=0
  ok 'cert9.db sustituido; key4.db y pkcs11.txt fueron validados y no se modificaron'
}

wait_for_normal_adb() {
  local attempt uid
  for ((attempt = 1; attempt <= 30; attempt++)); do
    if "$ADB_COMMAND" wait-for-device >/dev/null 2>&1; then
      uid="$(adb_uid || true)"
      if [[ "$uid" == 2000 ]]; then ROOT_ADB_ACTIVE=0; ok 'ADB volvió al modo normal'; return 0; fi
    fi
    sleep 2
  done
  warn 'no se pudo confirmar ADB normal en 60 segundos'
  return 1
}

apply_change() {
  local imported rollback_dir
  [[ "$CONFIRMATION" == "$CONFIRM_APPLY" ]] || die "confirmación incorrecta; escribe exactamente $CONFIRM_APPLY"
  require_commands adb podman python3 sha256sum awk grep tr sed date seq sleep find sort stat
  [[ -f "$SOURCE_FILE" ]] || die 'falta certdata; ejecuta --acquire'
  verify_source_file "$SOURCE_FILE" >/dev/null
  preflight_device >/dev/null
  create_work_dir
  start_root_adb
  find_remote_profile
  validate_remote_metadata
  stop_b2g
  clear_stale_remote_stage
  prepare_database
  import_bundle
  imported="$(cat "${WORK_DIR}/imported-count")"
  rollback_dir="$(cat "${WORK_DIR}/rollback-path")"
  printf '═══ Aplicación CA Mozilla en Flame ═══\n'
  printf 'raíces importadas: %s\n' "$imported"
  info 'escribiendo únicamente cert9.db; el rollback conserva el conjunto completo NSS'
  push_database
  info 'reiniciando el teléfono para recargar NSS'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1 || die 'no se pudo reiniciar el teléfono'
  wait_for_normal_adb || return 1
  ok 'cambio aplicado; prueba HTTPS sin aceptar excepciones permanentes'
  info "rollback disponible en ${rollback_dir}"
}

latest_rollback() {
  [[ -d "$ROLLBACK_ROOT" ]] || die 'no existe un rollback local'
  find "$ROLLBACK_ROOT" -mindepth 2 -maxdepth 2 -type f -name cert9.db -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
}

rollback_change() {
  local backup_path staged_remote expected_hash
  [[ "$CONFIRMATION" == "$CONFIRM_ROLLBACK" ]] || die "confirmación incorrecta; escribe exactamente $CONFIRM_ROLLBACK"
  require_commands adb sha256sum awk grep tr sed date seq sleep find sort stat
  require_flame_device
  backup_path="$(latest_rollback)"
  [[ -f "$backup_path" && -r "$backup_path" ]] || die 'el rollback más reciente no es legible'
  [[ "$(stat -c '%u' -- "$backup_path")" == "$(id -u)" ]] || die 'el rollback no pertenece al usuario actual'
  expected_hash="$(sha256sum -- "$backup_path" | awk '{print $1}')"
  start_root_adb
  find_remote_profile
  validate_remote_metadata
  stop_b2g
  clear_stale_remote_stage
  staged_remote="${REMOTE_DB}.new"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell test '!' -e "$staged_remote" >/dev/null 2>&1 || die 'ya existe cert9.db.new; no se sobrescribirá'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" push "$backup_path" "$staged_remote" >/dev/null || die 'no se pudo subir el rollback'
  STAGED_REMOTE_CREATED=1
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chown 0:0 "$staged_remote" >/dev/null 2>&1 || die 'no se pudo asignar root:root al rollback'
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell chmod 600 "$staged_remote" >/dev/null 2>&1 || die 'no se pudieron restaurar permisos del rollback'
  verify_remote_stage_hash "$staged_remote" "$expected_hash" "${WORK_DIR}/cert9.db.rollback.remote"
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" shell mv "$staged_remote" "$REMOTE_DB" >/dev/null 2>&1 || die 'no se pudo restaurar cert9.db'
  STAGED_REMOTE_CREATED=0
  "$ADB_COMMAND" -s "$DEVICE_SERIAL" reboot >/dev/null 2>&1 || die 'no se pudo reiniciar tras el rollback'
  wait_for_normal_adb || return 1
  ok 'cert9.db restaurado desde el rollback mínimo'
}

test_change() {
  local db_dir cert_list cert_count managed_count
  require_commands adb podman mktemp mkdir chmod sha256sum awk grep tr sed sleep
  identify_runtime >/dev/null
  require_exact_runtime
  require_flame_device
  create_work_dir
  start_root_adb
  find_remote_profile
  validate_remote_metadata
  stop_b2g
  db_dir="${WORK_DIR}/db"
  mkdir -p -- "$db_dir"
  chmod 700 -- "$db_dir"
  for remote_name in cert9.db key4.db pkcs11.txt; do
    "$ADB_COMMAND" -s "$DEVICE_SERIAL" pull "${PROFILE_PATH}/${remote_name}" "${db_dir}/${remote_name}" >/dev/null || die "no se pudo extraer ${remote_name} para la prueba"
    chmod 600 -- "${db_dir}/${remote_name}"
  done
  cert_list="$(legacy_certutil "$db_dir" -L -d sql:/work 2>/dev/null)" || die 'el runtime exacto no pudo leer el conjunto NSS'
  cert_count="$(wc -l <<< "$cert_list" | awk '{print $1}')"
  managed_count="$(grep -Fc 'Rafex Mozilla ' <<< "$cert_list" || true)"
  printf '═══ Prueba de conjunto NSS Firefox OS ═══\n'
  printf 'entradas legibles: %s | raíces Rafex: %s\n' "$cert_count" "$managed_count"
  restore_normal_adb || die 'no se pudo devolver ADB al modo normal'
  ok 'cert9.db, key4.db y pkcs11.txt fueron leídos sin modificar el teléfono'
}

show_plan() {
  printf '═══ Plan CA Mozilla para Firefox OS ═══\n'
  printf 'runtime requerido: %s | NSS: %s | NSPR: %s\n' "$CA_IMAGE" "$NSS_VERSION" "$NSPR_VERSION"
  info 'identificar Build ID, Gaia, Gonk, SourceRepository y hash de libnss3.so'
  info 'rechazar imágenes NSS genéricas; exigir un bundle B2G del commit matched'
  info 'leer el conjunto cert9.db, key4.db y pkcs11.txt con certutil dentro de Podman rootless'
  info 'guardar rollback mínimo del conjunto; modificar únicamente cert9.db si la prueba final pasa'
  info 'usar adb root temporal, detener B2G y devolver ADB a uid 2000 con unroot o reinicio controlado'
  info 'no usar stop adbd como limpieza, no tocar /system, libnssckbi.so, particiones ni red'
  info "confirmación requerida: $CONFIRM_APPLY"
}

main() {
  parse_args "$@"
  require_linux_user
  resolve_commands
  case "$ACTION" in
    status) require_commands sha256sum awk grep; show_status ;;
    plan) show_plan ;;
    acquire) acquire_source ;;
    verify-source)
      require_commands python3 sha256sum awk grep
      [[ -f "$SOURCE_FILE" ]] || die 'fuente no adquirida; ejecuta --acquire'
      printf '═══ Verificación de fuente CA Mozilla ═══\n'
      verify_source_file "$SOURCE_FILE" >/dev/null
      ok "SHA-256 coincide: $NSS_RELEASE"
      source_summary "$SOURCE_FILE"
      ;;
    identify-runtime) identify_runtime ;;
    preflight) require_commands adb podman python3 sha256sum awk grep tr sed; preflight_device ;;
    apply) apply_change ;;
    test) test_change ;;
    rollback) rollback_change ;;
    *) die "acción interna no soportada: $ACTION" ;;
  esac
}

main "$@"
