#!/usr/bin/env bash
# v1.0.1 - Verificación y flasheo controlado de la base v18D para Mozilla Flame.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly BASE_ARCHIVE_NAME="v18D.zip"
readonly BASE_ARCHIVE_SHA512="2befa6d7c1202f8bc9e5dab75d644387cffa727b362ad0508981eac2a910f7dfbd3938d915d259476750d8a74af7de96c811788d35a1d3311d65e72ce5026076"
readonly DEFAULT_ARCHIVE="/tmp/v18D.zip"
readonly WIPE_CONFIRMATION="FLAME-V18D-WIPE"
readonly REQUIRED_FILES=(
  "gpt_both0.bin"
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
readonly FLAME_MARKER_FILES=(
  "gpt_both0.bin"
  "NON-HLOS.bin"
  "emmc_appsboot.mbn"
  "rawprogram0.xml"
  "patch0.xml"
)
readonly FLASH_PARTITIONS=(
  "partition:gpt_both0.bin"
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
FASTBOOT_SERIAL=""
TEMP_DIR=""

ADB_COMMAND=""
FASTBOOT_COMMAND=""

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
  firefoxos_flash_base_linux.sh --status
  firefoxos_flash_base_linux.sh --check [--archive /tmp/v18D.zip]
  firefoxos_flash_base_linux.sh --plan [--archive /tmp/v18D.zip]
  firefoxos_flash_base_linux.sh --fastboot
  firefoxos_flash_base_linux.sh --apply [--archive /tmp/v18D.zip]

--check valida el entorno y la imagen sin tocar el teléfono.
--plan muestra el orden de operaciones sin tocar el teléfono.
--fastboot valida un Flame ya colocado en modo fastboot; no escribe particiones.
--apply exige un terminal interactivo y la confirmación exacta
FLAME-V18D-WIPE antes de borrar y escribir el teléfono.

El wrapper nunca ejecuta el flash.sh incluido en el ZIP, no usa sudo, no
reinicia automáticamente desde ADB y no inicia adb logcat al terminar.
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
  ADB_COMMAND="$(command -v adb 2>/dev/null || true)"
  FASTBOOT_COMMAND="$(command -v fastboot 2>/dev/null || true)"
}

require_command() {
  local command_name="$1" command_path
  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  [[ -n "$command_path" ]] || die "$command_name no está instalado o no está en PATH"
}

archive_entries() {
  unzip -Z1 -- "$ARCHIVE_PATH" 2>/dev/null
}

has_archive_entry() {
  local entries="$1" wanted="$2"
  awk -v wanted="$wanted" '$0 == wanted { found = 1 } END { exit(found ? 0 : 1) }' <<< "$entries"
}

verify_archive_paths() {
  local entries="$1"
  ! awk '
    $0 ~ /^\// || $0 == ".." || $0 ~ /(^|\/)\.\.\// { found = 1 }
    END { exit(found ? 0 : 1) }
  ' <<< "$entries"
}

validate_archive() {
  local archive_real actual_sha entries flash_script file_name

  [[ -f "$ARCHIVE_PATH" ]] || die "no existe el archivo regular: $ARCHIVE_PATH"
  [[ -r "$ARCHIVE_PATH" ]] || die "no se puede leer el archivo: $ARCHIVE_PATH"
  [[ "$(basename -- "$ARCHIVE_PATH")" == "$BASE_ARCHIVE_NAME" ]] ||
    die "el archivo debe llamarse exactamente $BASE_ARCHIVE_NAME"
  archive_real="$(readlink -f -- "$ARCHIVE_PATH" 2>/dev/null)" ||
    die 'no se pudo resolver la ruta del ZIP'
  [[ -f "$archive_real" && -r "$archive_real" ]] || die 'la ruta resuelta no es legible'
  ARCHIVE_PATH="$archive_real"

  require_command sha512sum
  require_command unzip
  info 'calculando SHA512 de la base; no se ejecutará contenido del ZIP'
  actual_sha="$(sha512sum -- "$ARCHIVE_PATH" | awk '{print $1}')" ||
    die 'no se pudo calcular SHA512'
  [[ "$actual_sha" == "$BASE_ARCHIVE_SHA512" ]] || {
    printf 'SHA512 obtenido: %s\n' "$actual_sha" >&2
    die 'SHA512 no coincide con el candidato histórico v18D'
  }
  ok 'SHA512 coincide con el candidato histórico v18D'

  unzip -tqq -- "$ARCHIVE_PATH" >/dev/null || die 'la integridad del ZIP no pudo comprobarse'
  ok 'estructura ZIP íntegra'
  entries="$(archive_entries)" || die 'no se pudo listar el contenido del ZIP'
  [[ -n "$entries" ]] || die 'el ZIP no contiene entradas'
  verify_archive_paths "$entries" || die 'el ZIP contiene rutas absolutas o traversal ..'

  has_archive_entry "$entries" flash.sh || die 'falta flash.sh'
  ok 'flash.sh presente; será inspeccionado, no ejecutado'
  flash_script="$(unzip -p -- "$ARCHIVE_PATH" flash.sh 2>/dev/null)" ||
    die 'no se pudo leer flash.sh'
  grep -Eiq '(^|[^[:alnum:]_])fastboot([^[:alnum:]_]|$)' <<< "$flash_script" ||
    die 'flash.sh no referencia fastboot'
  for file_name in "${REQUIRED_FILES[@]}"; do
    has_archive_entry "$entries" "$file_name" || die "falta el archivo requerido: $file_name"
  done
  for file_name in "${FLAME_MARKER_FILES[@]}"; do
    has_archive_entry "$entries" "$file_name" || die "falta el marcador estructural de Flame: $file_name"
  done
  ok 'particiones y marcadores estructurales de Flame presentes'

  if grep -Fq 'adb kill-server' <<< "$flash_script"; then
    warn 'el flash.sh histórico contiene adb kill-server; el wrapper no lo ejecutará'
  fi
  if grep -Fq 'adb logcat' <<< "$flash_script"; then
    warn 'el flash.sh histórico termina en adb logcat; el wrapper no lo ejecutará'
  fi
}

adb_device_count() {
  [[ -n "$ADB_COMMAND" ]] || return 0
  "$ADB_COMMAND" devices 2>/dev/null |
    awk 'NR > 1 && NF >= 2 { count++ } END { print count + 0 }'
}

fastboot_serials() {
  "$FASTBOOT_COMMAND" devices 2>/dev/null |
    awk 'NF >= 1 { print $1 }'
}

require_fastboot_flame() {
  local serials product_output product version_output
  [[ -n "$FASTBOOT_COMMAND" ]] || die 'fastboot no está instalado'
  serials="$(fastboot_serials)"
  [[ -n "$serials" ]] || die 'no hay un dispositivo en fastboot; no se escribirá nada'
  [[ "$(wc -l <<< "$serials" | awk '{print $1}')" -eq 1 ]] ||
    die 'se requiere exactamente un dispositivo en fastboot'
  FASTBOOT_SERIAL="$(sed -n '1p' <<< "$serials")"
  [[ "$FASTBOOT_SERIAL" =~ ^[[:alnum:]_.:-]+$ ]] || die 'serial fastboot no válido'

  product_output="$("$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" getvar product 2>&1)" ||
    die 'no se pudo consultar el producto fastboot'
  product="$(awk -F: 'tolower($1) ~ /product/ { value = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print tolower(value); exit }' <<< "$product_output")"
  case "$product" in
    flame|flame-kk)
      ok 'un único dispositivo fastboot identificado como Flame'
      ;;
    msm8610)
      version_output="$("$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" getvar version 2>&1)" ||
        die 'no se pudo consultar la versión del protocolo fastboot'
      if ! grep -Eiq 'version:[[:space:]]*0\.5([[:space:]]|$)' <<< "$version_output"; then
        printf '%s\n' "$product_output" "$version_output" |
          sed -E 's/([Ss]erial[^:]*:|[Ss]n:)[^[:space:]]+/\1[oculto]/g' >&2
        die 'MSM8610 no coincide con el protocolo fastboot histórico esperado; se detiene por seguridad'
      fi
      warn 'el bootloader expone MSM8610 en lugar del nombre Flame; coincide con el fastboot histórico 0.5 del Flame'
      ok 'un único dispositivo fastboot compatible con Flame (MSM8610/fastboot 0.5)'
      ;;
    *)
      printf '%s\n' "$product_output" | sed -E 's/([Ss]erial[^:]*:|[Ss]n:)[^[:space:]]+/\1[oculto]/g' >&2
      die 'el dispositivo fastboot no se identificó como Flame; se detiene por seguridad'
      ;;
  esac
}

show_status() {
  local adb_count=0 fastboot_count=0
  printf '═══ Flasheo controlado de base Firefox OS v18D ═══\n'
  if [[ -n "$ADB_COMMAND" ]]; then
    ok "adb disponible: $ADB_COMMAND"
    adb_count="$(adb_device_count)"
    printf 'ADB: dispositivos detectados=%s\n' "$adb_count"
  else
    warn 'adb ausente'
  fi
  if [[ -n "$FASTBOOT_COMMAND" ]]; then
    ok "fastboot disponible: $FASTBOOT_COMMAND"
    fastboot_count="$(fastboot_serials | awk 'NF { count++ } END { print count + 0 }')"
    printf 'fastboot: dispositivos detectados=%s\n' "$fastboot_count"
  else
    warn 'fastboot ausente'
  fi
  if [[ -f "$ARCHIVE_PATH" ]]; then
    info "imagen disponible para validar: $ARCHIVE_PATH"
  else
    warn "imagen no encontrada en $ARCHIVE_PATH"
  fi
  info 'no se muestran seriales y no se usa sudo'
}

show_plan() {
  validate_archive
  printf '\nPlan (sin ejecutar operaciones sobre el teléfono):\n'
  printf '  1. Confirmar un único Flame en fastboot.\n'
  local flash_spec partition image
  for flash_spec in "${FLASH_PARTITIONS[@]}"; do
    partition="${flash_spec%%:*}"
    image="${flash_spec#*:}"
    printf '  fastboot flash %s %s\n' "$partition" "$image"
  done
  printf '  fastboot erase modemst1\n'
  printf '  fastboot erase modemst2\n'
  printf '  fastboot reboot\n'
  warn 'el plan no reinicia, no borra y no escribe particiones'
}

extract_archive() {
  TEMP_DIR="$(mktemp -d /tmp/rafex-flame-v18D.XXXXXX)" || die 'no se pudo crear directorio temporal privado'
  chmod 700 -- "$TEMP_DIR"
  unzip -q -- "$ARCHIVE_PATH" -d "$TEMP_DIR" || die 'no se pudo extraer la imagen verificada'
  local file_name
  for file_name in "${REQUIRED_FILES[@]}"; do
    [[ -s "$TEMP_DIR/$file_name" ]] || die "archivo extraído vacío o ausente: $file_name"
  done
  ok "imagen extraída en directorio temporal privado"
}

confirm_wipe() {
  local answer
  [[ -t 0 && -t 2 ]] || die '--apply exige un terminal interactivo para confirmar el borrado'
  printf '\nPELIGRO: se sobrescribirán particiones y se borrarán los datos del Flame.\n' >&2
  printf 'Escribe exactamente %s para continuar: ' "$WIPE_CONFIRMATION" >&2
  IFS= read -r answer || die 'no se recibió confirmación'
  [[ "$answer" == "$WIPE_CONFIRMATION" ]] || die 'confirmación incorrecta; no se tocó el teléfono'
}

run_flash() {
  local flash_spec partition image
  for flash_spec in "${FLASH_PARTITIONS[@]}"; do
    partition="${flash_spec%%:*}"
    image="${flash_spec#*:}"
    info "flasheando $partition"
    "$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" flash "$partition" "$TEMP_DIR/$image"
    ok "partición $partition escrita"
  done
  info 'borrando modemst1'
  "$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" erase modemst1
  info 'borrando modemst2'
  "$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" erase modemst2
  info 'reiniciando el Flame'
  "$FASTBOOT_COMMAND" -s "$FASTBOOT_SERIAL" reboot
  ok 'flasheo finalizado; el teléfono fue reiniciado'
}

run_check() {
  require_command sha512sum
  require_command unzip
  validate_archive
  ok 'entorno e imagen listos para una prueba posterior de fastboot'
}

run_fastboot_check() {
  require_fastboot_flame
  ok 'fastboot accesible sin sudo; no se escribieron particiones'
  info 'para regresar sin modificar el teléfono: fastboot reboot'
}

run_apply() {
  validate_archive
  require_fastboot_flame
  extract_archive
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
