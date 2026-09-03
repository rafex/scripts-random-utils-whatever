#!/usr/bin/env bash
# v1.0.0 - Verificación y flasheo controlado de la base v18D nightly v5 (Firefox OS 2.6).
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly ARCHIVE_NAME="v18D_nightly_v5.zip"
readonly ARCHIVE_SHA512="f92123446f71289dd0ea23b0c602f8a192267fbfcf2f25682cbc072f8bbe3e8b795aea3305ba6ea6cc504d252f1d895b07704b5b65700fcf3760e1386b89c431"
readonly DEFAULT_ARCHIVE="/tmp/${ARCHIVE_NAME}"
readonly ARCHIVE_PREFIX="v18D_nightly_v5/"
readonly WIPE_CONFIRMATION="FLAME-V18D-NIGHTLY-V5-WIPE"
readonly REQUIRED_FILES=(
  "gpt_both0_big.bin"
  "NON-HLOS.bin"
  "rpm.mbn"
  "tz.mbn"
  "sbl1.mbn"
  "sdi.mbn"
  "study.img"
  "emmc_appsboot.mbn"
  "boot.img"
  "system.img"
  "persist.img"
  "recovery.img"
  "cache.img"
  "userdata.img"
  "usbdisk.img"
)
readonly FLASH_PARTITIONS=(
  "partition:gpt_both0_big.bin"
  "modem:NON-HLOS.bin"
  "rpm:rpm.mbn"
  "tz:tz.mbn"
  "sbl1:sbl1.mbn"
  "sdi:sdi.mbn"
  "fsg:study.img"
  "aboot:emmc_appsboot.mbn"
  "boot:boot.img"
  "system:system.img"
  "persist:persist.img"
  "recovery:recovery.img"
  "cache:cache.img"
  "userdata:userdata.img"
  "usbmsc:usbdisk.img"
)

ACTION="status"
ACTION_EXPLICIT=0
ARCHIVE_PATH="$DEFAULT_ARCHIVE"
FASTBOOT_COMMAND=""
FASTBOOT_SERIAL=""
TEMP_DIR=""
IMAGE_ROOT=""

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  firefoxos_flash_nightly_linux.sh --status
  firefoxos_flash_nightly_linux.sh --check [--archive /tmp/v18D_nightly_v5.zip]
  firefoxos_flash_nightly_linux.sh --plan [--archive /tmp/v18D_nightly_v5.zip]
  firefoxos_flash_nightly_linux.sh --fastboot [--archive /tmp/v18D_nightly_v5.zip]
  firefoxos_flash_nightly_linux.sh --apply [--archive /tmp/v18D_nightly_v5.zip]

--check valida la imagen sin contactar el teléfono.
--plan muestra el orden de operaciones sin contactar ni modificar el teléfono.
--fastboot valida un único Flame ya colocado en modo fastboot; no escribe.
--apply exige fastboot validado y la confirmación exacta
FLAME-V18D-NIGHTLY-V5-WIPE antes de borrar y escribir el teléfono.

El wrapper no ejecuta el flash.sh incluido, no usa sudo, no reinicia desde ADB
y conserva modemst1/modemst2 para reducir el riesgo de perder calibración del módem.
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
      --status) choose_action status ;;
      --check) choose_action check ;;
      --plan) choose_action plan ;;
      --fastboot) choose_action fastboot ;;
      --apply) choose_action apply ;;
      --archive)
        (($# >= 2)) || die '--archive requiere la ruta del ZIP'
        ARCHIVE_PATH="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este wrapper solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; no requiere sudo'
}

resolve_commands() {
  FASTBOOT_COMMAND="$(command -v fastboot 2>/dev/null || true)"
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name no está instalado o no está en PATH"
}

archive_entries() {
  unzip -Z1 -- "$ARCHIVE_PATH" 2>/dev/null
}

archive_path_for() {
  printf '%s%s\n' "$ARCHIVE_PREFIX" "$1"
}

has_archive_entry() {
  local entries="$1" wanted="$2"
  awk -v wanted="$(archive_path_for "$wanted")" '$0 == wanted { found = 1 } END { exit(found ? 0 : 1) }' <<< "$entries"
}

verify_archive_paths() {
  local entries="$1"
  ! awk -v prefix="$ARCHIVE_PREFIX" '
    $0 !~ ("^" prefix) || $0 ~ /^\// || $0 ~ /(^|\/)\.\.\// || $0 ~ /(^|\/)\.\.$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' <<< "$entries"
}

validate_archive() {
  local archive_real actual_sha entries flash_script file_name

  require_command sha512sum
  require_command unzip
  require_command readlink
  [[ -f "$ARCHIVE_PATH" ]] || die "no existe el archivo regular: $ARCHIVE_PATH"
  [[ -r "$ARCHIVE_PATH" ]] || die "no se puede leer el archivo: $ARCHIVE_PATH"
  [[ "$(basename -- "$ARCHIVE_PATH")" == "$ARCHIVE_NAME" ]] ||
    die "el archivo debe llamarse exactamente $ARCHIVE_NAME"
  archive_real="$(readlink -f -- "$ARCHIVE_PATH")" || die 'no se pudo resolver la ruta del ZIP'
  [[ -f "$archive_real" && -r "$archive_real" ]] || die 'la ruta resuelta no es legible'
  ARCHIVE_PATH="$archive_real"

  info 'calculando SHA512 de la imagen; no se ejecutará contenido del ZIP'
  actual_sha="$(sha512sum -- "$ARCHIVE_PATH" | awk '{print $1}')" || die 'no se pudo calcular SHA512'
  [[ "$actual_sha" == "$ARCHIVE_SHA512" ]] || {
    printf 'SHA512 obtenido: %s\n' "$actual_sha" >&2
    die 'SHA512 no coincide con el candidato histórico v18D nightly v5'
  }
  ok 'SHA512 coincide con la base histórica Firefox OS 2.6'

  unzip -tqq -- "$ARCHIVE_PATH" >/dev/null || die 'la integridad del ZIP no pudo comprobarse'
  ok 'estructura ZIP íntegra'
  entries="$(archive_entries)" || die 'no se pudo listar el contenido del ZIP'
  [[ -n "$entries" ]] || die 'el ZIP no contiene entradas'
  verify_archive_paths "$entries" || die 'el ZIP contiene rutas fuera de su prefijo o traversal ..'

  has_archive_entry "$entries" flash.sh || die 'falta flash.sh dentro del prefijo v18D_nightly_v5/'
  flash_script="$(unzip -p -- "$ARCHIVE_PATH" "$(archive_path_for flash.sh)" 2>/dev/null)" ||
    die 'no se pudo leer flash.sh'
  grep -Eiq '(^|[^[:alnum:]_])fastboot([^[:alnum:]_]|$)' <<< "$flash_script" ||
    die 'flash.sh no referencia fastboot'
  for file_name in "${REQUIRED_FILES[@]}"; do
    has_archive_entry "$entries" "$file_name" || die "falta el archivo requerido: $file_name"
  done
  ok 'particiones específicas de v18D nightly v5 presentes'

  if grep -Fq 'adb kill-server' <<< "$flash_script"; then
    warn 'el flash.sh histórico contiene adb kill-server; el wrapper no lo ejecutará'
  fi
  if grep -Fq 'adb reboot bootloader' <<< "$flash_script"; then
    warn 'el flash.sh histórico reinicia desde ADB; el wrapper exige fastboot previamente validado'
  fi
  if grep -Fq 'fastboot erase modemst' <<< "$flash_script"; then
    warn 'el flash.sh histórico borra modemst; el wrapper conservará modemst1/modemst2'
  fi
}

fastboot_serials() {
  "$FASTBOOT_COMMAND" devices 2>/dev/null | awk 'NF >= 1 { print $1 }'
}

scrub_fastboot_output() {
  sed -E 's/([Ss]erial[^:]*:|[Ss]n:)[^[:space:]]+/\1[oculto]/g'
}

fastboot_getvar() {
  local variable="$1" output status
  if output="$("$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" getvar "$variable" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  else
    status=$?
    printf '%s\n' "$output" | scrub_fastboot_output >&2
    return "$status"
  fi
}

require_fastboot_flame() {
  local serials product_output product version_output
  local serial_count

  [[ -n "$FASTBOOT_COMMAND" ]] || die 'fastboot no está instalado'
  serials="$(fastboot_serials)"
  serial_count="$(awk 'NF { count++ } END { print count + 0 }' <<< "$serials")"
  [[ "$serial_count" -eq 1 ]] || die 'se requiere exactamente un dispositivo en fastboot'
  FASTBOOT_SERIAL="$(sed -n '1p' <<< "$serials")"
  [[ "$FASTBOOT_SERIAL" =~ ^[[:alnum:]_.:-]+$ ]] || die 'serial fastboot no válido'

  product_output="$(fastboot_getvar product)" || die 'no se pudo consultar product en fastboot'
  product="$(awk -F: 'tolower($1) ~ /product/ { value = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print tolower(value); exit }' <<< "$product_output")"
  case "$product" in
    flame|flame-kk|msm8610)
      version_output="$(fastboot_getvar version)" || die 'no se pudo consultar version en fastboot'
      grep -Eiq 'version:[[:space:]]*0\.5([[:space:]]|$)' <<< "$version_output" ||
        die 'el dispositivo no coincide con el protocolo fastboot histórico 0.5'
      if [[ "$product" == msm8610 ]]; then
        warn 'el bootloader expone MSM8610; coincide con el fastboot histórico del Flame'
      fi
      ok "dispositivo compatible con Flame ($product/fastboot 0.5)"
      ;;
    *)
      printf '%s\n' "$product_output" | scrub_fastboot_output >&2
      die 'el dispositivo fastboot no se identificó como Flame'
      ;;
  esac
}

extract_archive() {
  local file_name
  require_command mktemp
  TEMP_DIR="$(mktemp -d /tmp/rafex-flame-v18D-nightly-v5.XXXXXX)" ||
    die 'no se pudo crear directorio temporal privado'
  chmod 700 -- "$TEMP_DIR"
  unzip -q -- "$ARCHIVE_PATH" -d "$TEMP_DIR" || die 'no se pudo extraer la imagen verificada'
  IMAGE_ROOT="$TEMP_DIR/v18D_nightly_v5"
  [[ -d "$IMAGE_ROOT" ]] || die 'falta el directorio raíz esperado de la imagen'
  for file_name in "${REQUIRED_FILES[@]}"; do
    [[ -s "$IMAGE_ROOT/$file_name" ]] || die "archivo extraído vacío o ausente: $file_name"
  done
  ok 'imagen extraída en directorio temporal privado'
}

parse_size() {
  local raw="$1" value
  raw="${raw//[[:space:]]/}"
  if [[ "$raw" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    value=$((raw))
  elif [[ "$raw" =~ ^[0-9]+$ ]]; then
    value="$raw"
  else
    return 1
  fi
  printf '%s\n' "$value"
}

check_download_limit() {
  local output raw_limit max_size file_name file_size
  output="$(fastboot_getvar max-download-size)" || die 'no se pudo consultar max-download-size en fastboot'
  raw_limit="$(awk -F: 'tolower($1) ~ /max-download-size/ { value = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value; exit }' <<< "$output")"
  [[ -n "$raw_limit" ]] || die 'fastboot no devolvió max-download-size'
  max_size="$(parse_size "$raw_limit")" || die 'max-download-size no es un número válido'
  [[ "$max_size" -gt 0 ]] || die 'max-download-size es cero'

  for file_name in "${REQUIRED_FILES[@]}"; do
    file_size="$(stat -c '%s' -- "$IMAGE_ROOT/$file_name")" || die "no se pudo medir $file_name"
    if ((file_size > max_size)); then
      die "$file_name excede max-download-size ($file_size > $max_size)"
    fi
  done
  ok "todas las imágenes caben en max-download-size ($max_size bytes)"
}

confirm_wipe() {
  local answer
  [[ -t 0 && -t 2 ]] || die '--apply exige un terminal interactivo para confirmar el borrado'
  printf '\nPELIGRO: se sobrescribirá la tabla GPT y se borrarán los datos del Flame.\n' >&2
  printf 'modemst1 y modemst2 se conservarán.\n' >&2
  printf 'Escribe exactamente %s para continuar: ' "$WIPE_CONFIRMATION" >&2
  IFS= read -r answer || die 'no se recibió confirmación'
  [[ "$answer" == "$WIPE_CONFIRMATION" ]] || die 'confirmación incorrecta; no se tocó el teléfono'
}

run_fastboot() {
  local output status
  if output="$("$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" "$@" 2>&1)"; then
    printf '%s\n' "$output" | scrub_fastboot_output
    return 0
  else
    status=$?
    printf '%s\n' "$output" | scrub_fastboot_output >&2
    return "$status"
  fi
}

run_flash() {
  local flash_spec partition image
  for flash_spec in "${FLASH_PARTITIONS[@]}"; do
    partition="${flash_spec%%:*}"
    image="${flash_spec#*:}"
    info "flasheando $partition"
    run_fastboot flash "$partition" "$IMAGE_ROOT/$image" || die "fastboot falló al escribir $partition"
    ok "partición $partition escrita"
  done
  info 'reiniciando el Flame'
  run_fastboot reboot || die 'fastboot no pudo reiniciar el teléfono'
  ok 'flasheo v18D nightly v5 finalizado; el teléfono fue reiniciado'
}

show_status() {
  printf '═══ Firefox OS 2.6: v18D nightly v5 ═══\n'
  if [[ -n "$FASTBOOT_COMMAND" ]]; then
    ok "fastboot disponible: $FASTBOOT_COMMAND"
    printf 'fastboot: dispositivos detectados=%s\n' "$(fastboot_serials | awk 'NF { count++ } END { print count + 0 }')"
  else
    warn 'fastboot ausente'
  fi
  if [[ -f "$ARCHIVE_PATH" ]]; then
    info "imagen disponible para validar: $ARCHIVE_PATH"
  else
    warn "imagen no encontrada en $ARCHIVE_PATH"
  fi
  info 'no se muestran seriales, no se usa sudo y modemst1/modemst2 se conservan'
}

show_plan() {
  validate_archive
  printf '\nPlan (sin contactar ni modificar el teléfono):\n'
  printf '  1. Colocar manualmente el Flame en fastboot.\n'
  printf '  2. Validar un único Flame, product/protocolo y max-download-size.\n'
  local flash_spec partition image
  for flash_spec in "${FLASH_PARTITIONS[@]}"; do
    partition="${flash_spec%%:*}"
    image="${flash_spec#*:}"
    printf '  fastboot flash %s %s\n' "$partition" "$image"
  done
  printf '  3. Conservar modemst1 y modemst2.\n'
  printf '  fastboot reboot\n'
  warn 'el plan no entra en fastboot, no borra y no escribe particiones'
}

run_check() {
  validate_archive
  ok 'entorno e imagen listos para validar fastboot posteriormente'
}

run_fastboot_check() {
  validate_archive
  extract_archive
  require_fastboot_flame
  check_download_limit
  ok 'fastboot accesible sin sudo; no se escribieron particiones'
  info 'para regresar sin modificar el teléfono: fastboot reboot'
}

run_apply() {
  validate_archive
  extract_archive
  require_fastboot_flame
  check_download_limit
  confirm_wipe
  run_flash
  info 'tras el primer arranque, vuelve a activar Developer Menu y ADB si el borrado los desactivó'
  info 'verifica con just firefoxos-tools --inventory y --preflight'
}

main() {
  parse_args "$@"
  require_linux_user
  resolve_commands

  case "$ACTION" in
    status) show_status ;;
    check) run_check ;;
    plan) show_plan ;;
    fastboot) run_fastboot_check ;;
    apply) run_apply ;;
    *) die "acción interna no soportada: $ACTION" ;;
  esac
}

main "$@"
