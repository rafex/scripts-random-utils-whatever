#!/usr/bin/env bash
# v1.2.0 - Diagnóstico, verificación de base y lectura controlada de Firefox OS por USB.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly FIREFOXOS_USB_IDS=("05c6:9025" "05c6:9026")
readonly EXPORT_ROOT="${HOME}/Documents/firefoxos-exports"
readonly BASE_ARCHIVE_NAME="v18D.zip"
readonly BASE_ARCHIVE_SHA512="2befa6d7c1202f8bc9e5dab75d644387cffa727b362ad0508981eac2a910f7dfbd3938d915d259476750d8a74af7de96c811788d35a1d3311d65e72ce5026076"

ACTION="status"
ACTION_EXPLICIT=0
REMOTE_PATH="/"
REMOTE_EXPLICIT=0
TARGET_PATH=""
BASE_ARCHIVE_PATH=""
BASE_ARCHIVE_EXPLICIT=0

ADB_COMMAND=""
LSUSB_COMMAND=""
LSBLK_COMMAND=""
GIO_COMMAND=""
ADB_DEVICES_OUTPUT=""
ADB_QUERY_STATUS=0
AUTHORIZED_COUNT=0
UNAUTHORIZED_COUNT=0
OFFLINE_COUNT=0
UNKNOWN_COUNT=0
TOTAL_COUNT=0
AUTHORIZED_SERIAL=""

DEVICE_MODEL=""
DEVICE_NAME=""
DEVICE_ANDROID_VERSION=""
DEVICE_BUILD_ID=""
DEVICE_BOOTLOADER=""
DEVICE_B2G_VERSION=""
DEVICE_B2G_BUILD_ID=""
DEVICE_GAIA_VERSION=""
DEVICE_BATTERY_LEVEL=""
DEVICE_BATTERY_STATUS=""
DEVICE_USB_CONFIG=""
DEVICE_DF_OUTPUT=""
DEVICE_USB_ID=""

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_tools_linux.sh --status
  firefoxos_tools_linux.sh --devices
  firefoxos_tools_linux.sh --inventory
  firefoxos_tools_linux.sh --preflight
  firefoxos_tools_linux.sh --verify-base --archive ~/Downloads/v18D.zip
  firefoxos_tools_linux.sh --list --remote <ruta-absoluta>
  firefoxos_tools_linux.sh --pull --remote <ruta-absoluta> \
    --target ~/Documents/firefoxos-exports

Diagnóstico, verificación local de una base y lectura controlada de Firefox OS
por USB. No ofrece shell remoto, adb push, borrado, reinicio, desbloqueo,
flasheo ni ADB por red.
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
      --devices) choose_action devices ;;
      --inventory) choose_action inventory ;;
      --preflight) choose_action preflight ;;
      --verify-base) choose_action verify-base ;;
      --list) choose_action list ;;
      --pull) choose_action pull ;;
      --remote)
        (($# >= 2)) || die '--remote requiere una ruta absoluta'
        REMOTE_PATH="$2"
        REMOTE_EXPLICIT=1
        shift
        ;;
      --target)
        (($# >= 2)) || die '--target requiere un directorio de salida'
        TARGET_PATH="$2"
        shift
        ;;
      --archive)
        (($# >= 2)) || die '--archive requiere la ruta del archivo ZIP local'
        BASE_ARCHIVE_PATH="$2"
        BASE_ARCHIVE_EXPLICIT=1
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done

  if [[ "$ACTION" != list && "$ACTION" != pull && "$REMOTE_EXPLICIT" -eq 1 ]]; then
    die '--remote solo se puede usar con --list o --pull'
  fi
  if [[ "$ACTION" != pull && -n "$TARGET_PATH" ]]; then
    die '--target solo se puede usar con --pull'
  fi
  if [[ "$ACTION" != verify-base && "$BASE_ARCHIVE_EXPLICIT" -eq 1 ]]; then
    die '--archive solo se puede usar con --verify-base'
  fi
  if [[ "$ACTION" == verify-base ]]; then
    [[ "$BASE_ARCHIVE_EXPLICIT" -eq 1 ]] || die '--verify-base requiere --archive <archivo>'
  fi
  if [[ "$ACTION" == pull ]]; then
    [[ "$REMOTE_EXPLICIT" -eq 1 ]] || die '--pull requiere --remote <ruta-absoluta>'
    [[ -n "$TARGET_PATH" ]] || die '--pull requiere --target <directorio>'
  fi
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; no requiere sudo'
}

resolve_commands() {
  ADB_COMMAND="$(command -v adb 2>/dev/null || true)"
  LSUSB_COMMAND="$(command -v lsusb 2>/dev/null || true)"
  LSBLK_COMMAND="$(command -v lsblk 2>/dev/null || true)"
  GIO_COMMAND="$(command -v gio 2>/dev/null || true)"
}

usb_present() {
  detect_usb_id >/dev/null
}

detect_usb_id() {
  local usb_id
  [[ -n "$LSUSB_COMMAND" ]] || return 1
  for usb_id in "${FIREFOXOS_USB_IDS[@]}"; do
    if "$LSUSB_COMMAND" -d "$usb_id" 2>/dev/null | grep -Fq "$usb_id"; then
      printf '%s\n' "$usb_id"
      return 0
    fi
  done
  return 1
}

has_adb_interface() {
  local detected_id
  detected_id="$(detect_usb_id)" || return 1
  "$LSUSB_COMMAND" -v -d "$detected_id" 2>/dev/null |
    awk '
      /bInterfaceClass/ { interface_class = $2 }
      /bInterfaceSubClass/ { interface_subclass = $2 }
      /bInterfaceProtocol/ {
        interface_protocol = $2
        if ((interface_class == "255" || interface_class == "0xff") &&
            (interface_subclass == "66" || interface_subclass == "0x42") &&
            (interface_protocol == "1" || interface_protocol == "0x01")) {
          found = 1
        }
      }
      END { exit(found ? 0 : 1) }
    '
}

query_adb_devices() {
  ADB_DEVICES_OUTPUT=""
  ADB_QUERY_STATUS=0
  if ADB_DEVICES_OUTPUT="$("$ADB_COMMAND" devices 2>/dev/null)"; then
    :
  else
    ADB_QUERY_STATUS=$?
  fi
}

get_device_counts() {
  local serial state

  AUTHORIZED_COUNT=0
  UNAUTHORIZED_COUNT=0
  OFFLINE_COUNT=0
  UNKNOWN_COUNT=0
  TOTAL_COUNT=0
  AUTHORIZED_SERIAL=""

  while IFS='|' read -r serial state; do
    [[ -n "$serial" && -n "$state" ]] || continue
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    case "$state" in
      device)
        AUTHORIZED_COUNT=$((AUTHORIZED_COUNT + 1))
        AUTHORIZED_SERIAL="$serial"
        ;;
      unauthorized) UNAUTHORIZED_COUNT=$((UNAUTHORIZED_COUNT + 1)) ;;
      offline) OFFLINE_COUNT=$((OFFLINE_COUNT + 1)) ;;
      *) UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
    esac
  done < <(printf '%s\n' "$ADB_DEVICES_OUTPUT" | awk 'NR > 1 && NF >= 2 { print $1 "|" $2 }')
}

print_adb_counts() {
  if [[ "$ADB_QUERY_STATUS" -ne 0 ]]; then
    warn 'no se pudo consultar adb devices'
    return
  fi

  get_device_counts
  printf 'ADB: device=%d unauthorized=%d offline=%d otros=%d\n' \
    "$AUTHORIZED_COUNT" "$UNAUTHORIZED_COUNT" "$OFFLINE_COUNT" "$UNKNOWN_COUNT"
  (( UNAUTHORIZED_COUNT == 0 )) || warn 'el teléfono requiere aceptar la autorización USB en su pantalla'
  (( OFFLINE_COUNT == 0 )) || warn 'ADB reporta un dispositivo offline; desconecta y vuelve a conectar el cable'
  (( UNKNOWN_COUNT == 0 )) || warn 'ADB reportó un estado no reconocido; no se realizarán lecturas'
}

show_storage() {
  [[ -n "$LSBLK_COMMAND" ]] || {
    warn 'lsblk no está disponible para revisar almacenamiento USB'
    return
  }

  local found=0
  while IFS='|' read -r transport size removable device_type mount_state; do
    [[ "$transport" == usb ]] || continue
    found=1
    printf 'almacenamiento USB: tamaño=%s extraíble=%s tipo=%s estado=%s\n' \
      "$size" "$removable" "$device_type" "$mount_state"
  done < <(
    "$LSBLK_COMMAND" -nr -o TRAN,SIZE,RM,TYPE,MOUNTPOINTS 2>/dev/null |
      awk 'NF >= 4 && $1 == "usb" {
        state = (NF >= 5 ? "montado" : "sin-montar")
        print $1 "|" $2 "|" $3 "|" $4 "|" state
      }'
  )
  (( found == 1 )) || info 'no se detecta almacenamiento USB con tamaño utilizable'
}

validate_remote_path() {
  [[ "$REMOTE_PATH" == /* ]] || die '--remote debe ser una ruta absoluta'
  [[ "$REMOTE_PATH" != *$'\n'* && "$REMOTE_PATH" != *$'\r'* ]] || die '--remote no puede contener saltos de línea'
  [[ "$REMOTE_PATH" != *..* ]] || die '--remote no puede contener segmentos ..'
  [[ "$REMOTE_PATH" =~ ^/[A-Za-z0-9_./:@+-]*$ ]] || die '--remote contiene caracteres no permitidos'
}

canonical_export_target() {
  local export_root target_canonical current_uid
  export_root="$(readlink -m -- "$EXPORT_ROOT")"

  [[ "$TARGET_PATH" != *$'\n'* && "$TARGET_PATH" != *$'\r'* ]] || die '--target no puede contener saltos de línea'
  [[ ! -L "$TARGET_PATH" ]] || die '--target no puede ser un enlace simbólico'
  target_canonical="$(readlink -m -- "$TARGET_PATH")"

  case "$target_canonical" in
    "$export_root"|"$export_root"/*) ;;
    *) die "--target debe estar dentro de $EXPORT_ROOT" ;;
  esac

  if [[ -e "$TARGET_PATH" && ! -d "$TARGET_PATH" ]]; then
    die '--target existe pero no es un directorio'
  fi
  mkdir -p -- "$target_canonical"
  [[ ! -L "$target_canonical" ]] || die '--target no puede ser un enlace simbólico'
  current_uid="$(id -u)"
  [[ "$(stat -c '%u' -- "$target_canonical")" == "$current_uid" ]] ||
    die '--target no pertenece al usuario actual'
  printf '%s\n' "$target_canonical"
}

show_status() {
  local detected_id usb_detected=0 adb_interface=0
  printf '═══ Firefox OS por USB ═══\n'
  printf 'USB esperado: %s (perfil ADB) / %s (perfil alterno)\n' \
    "${FIREFOXOS_USB_IDS[0]}" "${FIREFOXOS_USB_IDS[1]}"

  if [[ -n "$ADB_COMMAND" ]]; then
    if "$ADB_COMMAND" version 2>/dev/null | awk 'NR == 1 { print "ADB: " $0; found = 1 } END { exit(found ? 0 : 1) }'; then
      :
    else
      warn 'adb está instalado, pero no se pudo consultar su versión'
    fi
  else
    warn 'adb no está instalado; ejecuta just install-android-tools --apply'
  fi

  if [[ -z "$LSUSB_COMMAND" ]]; then
    warn 'lsusb no está disponible; no se puede identificar el teléfono USB'
  elif detected_id="$(detect_usb_id)"; then
    usb_detected=1
    ok "USB Firefox OS detectado: $detected_id"
    if has_adb_interface; then
      adb_interface=1
      ok 'el perfil USB expone una interfaz compatible con ADB'
    else
      warn 'el perfil USB actual no expone ADB; actívalo desde Developer → Debugging via USB → ADB and DevTools'
    fi
  else
    warn 'USB Firefox OS no detectado'
  fi

  if [[ -n "$ADB_COMMAND" && "$usb_detected" -eq 1 && "$adb_interface" -eq 1 ]]; then
    query_adb_devices
    print_adb_counts
  elif [[ -n "$ADB_COMMAND" ]]; then
    info 'no se consulta el estado ADB de otros teléfonos porque Firefox OS no expone un perfil ADB compatible'
  fi

  show_storage
  if [[ -n "$GIO_COMMAND" ]]; then
    ok 'gio disponible para GVfs/MTP si el teléfono ofrece almacenamiento real'
  else
    warn 'gio no está disponible; no se podrá explorar un perfil MTP mediante GVfs'
  fi

  if [[ -f "${HOME}/.android/adb_usb.ini" ]]; then
    info "${HOME}/.android/adb_usb.ini existe; el helper no lo modifica automáticamente"
  fi
  info 'no se activa ADB por red, no se añaden reglas udev y no se modifica USBGuard'
  info "extracciones permitidas únicamente bajo $EXPORT_ROOT"
}

show_devices() {
  printf '═══ Dispositivos Firefox OS ═══\n'
  if [[ -z "$LSUSB_COMMAND" ]] || ! usb_present; then
    warn 'sin USB Firefox OS detectado'
    return 0
  fi

  if ! has_adb_interface; then
    warn 'USB detectado, pero el perfil actual no expone ADB'
    info 'cambia el teléfono a Developer → Debugging via USB → ADB and DevTools y reconecta el cable'
    return 0
  fi

  if [[ -z "$ADB_COMMAND" ]]; then
    warn 'la interfaz ADB está presente, pero adb no está instalado'
    return 0
  fi

  query_adb_devices
  print_adb_counts
  (( AUTHORIZED_COUNT + UNAUTHORIZED_COUNT + OFFLINE_COUNT + UNKNOWN_COUNT > 0 )) ||
    warn 'la interfaz ADB está presente, pero adb no muestra el teléfono'
}

adb_getprop() {
  local property="$1"
  "$ADB_COMMAND" -s "$AUTHORIZED_SERIAL" shell getprop "$property" 2>/dev/null |
    tr -d '\r' | sed -n '1p'
}

adb_read_fixed_file() {
  local remote_file="$1"
  "$ADB_COMMAND" -s "$AUTHORIZED_SERIAL" shell cat "$remote_file" 2>/dev/null |
    tr -d '\r'
}

ini_value() {
  local content="$1" key="$2"
  awk -F= -v wanted_key="$key" '
    $1 == wanted_key {
      value = $0
      sub(/^[^=]*=/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' <<< "$content"
}

collect_device_inventory() {
  local application_ini platform_ini gaia_ini

  require_readable_device
  DEVICE_USB_ID="$(detect_usb_id || true)"

  DEVICE_MODEL="$(adb_getprop ro.product.model || true)"
  DEVICE_NAME="$(adb_getprop ro.product.device || true)"
  DEVICE_ANDROID_VERSION="$(adb_getprop ro.build.version.release || true)"
  DEVICE_BUILD_ID="$(adb_getprop ro.build.id || true)"
  DEVICE_BOOTLOADER="$(adb_getprop ro.bootloader || true)"
  DEVICE_BATTERY_LEVEL="$(adb_getprop status.battery.level || true)"
  DEVICE_BATTERY_STATUS="$(adb_getprop status.battery.status || true)"
  DEVICE_USB_CONFIG="$(adb_getprop sys.usb.config || true)"

  application_ini="$(adb_read_fixed_file /system/b2g/application.ini || true)"
  platform_ini="$(adb_read_fixed_file /system/b2g/platform.ini || true)"
  gaia_ini="$(adb_read_fixed_file /system/b2g/gaia/application.ini || true)"

  DEVICE_B2G_VERSION="$(ini_value "$application_ini" Version)"
  DEVICE_B2G_BUILD_ID="$(ini_value "$application_ini" BuildID)"
  [[ -n "$DEVICE_B2G_BUILD_ID" ]] ||
    DEVICE_B2G_BUILD_ID="$(ini_value "$platform_ini" BuildID)"
  DEVICE_GAIA_VERSION="$(ini_value "$gaia_ini" Version)"

  DEVICE_DF_OUTPUT="$("$ADB_COMMAND" -s "$AUTHORIZED_SERIAL" shell df /data /system /sdcard 2>/dev/null |
    tr -d '\r' || true)"
}

display_value() {
  local label="$1" value="$2"
  if [[ -n "$value" ]]; then
    printf '%s: %s\n' "$label" "$value"
  else
    printf '%s: N/D\n' "$label"
  fi
}

show_device_storage() {
  local found=0

  if [[ -n "$DEVICE_DF_OUTPUT" ]]; then
    while IFS='|' read -r mount total used available; do
      [[ -n "$mount" ]] || continue
      found=1
      printf '  %s: total=%s KB usado=%s KB libre=%s KB\n' \
        "$mount" "$total" "$used" "$available"
    done < <(
      awk '
        NR > 1 && ($NF == "/data" || $NF == "/system" || $NF == "/sdcard" ||
          $NF ~ /sdcard/) {
          printf "%s|%s|%s|%s\n", $NF, $2, $3, $4
        }
      ' <<< "$DEVICE_DF_OUTPUT"
    )
  fi

  (( found == 1 )) || printf '  almacenamiento: N/D\n'
}

historical_base_version() {
  local bootloader_suffix="${DEVICE_BOOTLOADER: -4}"
  if [[ "$bootloader_suffix" =~ ^([0-9A-Fa-f]{3})0$ ]]; then
    printf 'v%s\n' "${BASH_REMATCH[1]}"
  fi
}

base_meets_v180() {
  local base_version="$1" base_number

  base_number="${base_version#v}"
  if [[ "$base_number" =~ ^[0-9]+$ ]]; then
    [[ "$base_number" -ge 180 ]]
    return
  fi

  # The historical v18D suffix is hexadecimal-style and is newer than v180.
  [[ "$base_number" =~ ^18[0-9A-Fa-f]$ ]]
}

show_inventory() {
  local base_version

  collect_device_inventory
  printf '═══ Inventario Firefox OS (solo lectura) ═══\n'
  display_value 'Modelo' "$DEVICE_MODEL"
  display_value 'Dispositivo' "$DEVICE_NAME"
  display_value 'Android base' "$DEVICE_ANDROID_VERSION"
  display_value 'Build Android' "$DEVICE_BUILD_ID"
  display_value 'Bootloader' "$DEVICE_BOOTLOADER"
  base_version="$(historical_base_version || true)"
  display_value 'Base histórica estimada' "$base_version"
  display_value 'B2G/Gecko' "$DEVICE_B2G_VERSION"
  display_value 'Build B2G' "$DEVICE_B2G_BUILD_ID"
  display_value 'Gaia' "$DEVICE_GAIA_VERSION"
  display_value 'Batería reportada por getprop' "$DEVICE_BATTERY_LEVEL"
  display_value 'Estado de batería reportado por getprop' "$DEVICE_BATTERY_STATUS"
  display_value 'Configuración USB reportada' "$DEVICE_USB_CONFIG"
  display_value 'Perfil USB detectado en el host' "$DEVICE_USB_ID"
  printf 'ADB: un dispositivo Firefox OS autorizado en estado device\n'
  printf 'Almacenamiento del teléfono:\n'
  show_device_storage
  info 'no se muestran seriales, IMEI, IMSI, credenciales ni archivos privados'
  info 'inventario realizado sin reiniciar ni modificar el teléfono'
}

show_preflight() {
  local base_version

  collect_device_inventory
  printf '═══ Preflight Firefox OS (no destructivo) ═══\n'
  ok 'ADB autorizado y perfil Firefox OS detectado'
  display_value 'Modelo' "$DEVICE_MODEL"
  display_value 'B2G/Gecko actual' "$DEVICE_B2G_VERSION"
  display_value 'Base histórica estimada' "$(historical_base_version || true)"

  base_version="$(historical_base_version || true)"
  if [[ -n "$base_version" ]] && ! base_meets_v180 "$base_version"; then
    warn "la base histórica $base_version es anterior a v180; la ruta legacy de actualización exige una base v180 o superior"
  elif [[ -n "$base_version" ]]; then
    ok "la base histórica $base_version cumple el umbral legacy v180+; todavía no se ha verificado una imagen compatible"
  else
    warn 'no se pudo determinar la base histórica; no se asumirá compatibilidad'
  fi

  if [[ "$DEVICE_B2G_VERSION" == 28.* ]]; then
    warn 'el B2G/Gecko actual es 28.x; Firefox OS 2.5 usa una plataforma histórica distinta y no se actualizará por OTA'
  else
    info 'la versión B2G/Gecko no coincide con el patrón conocido; se requiere verificación manual de compatibilidad'
  fi

  if [[ -n "$DEVICE_BATTERY_LEVEL" ]]; then
    display_value 'Batería del teléfono' "$DEVICE_BATTERY_LEVEL"
  else
    warn 'batería del teléfono: N/D mediante las propiedades fijas permitidas; no se ejecuta dumpsys ni se reinicia para consultarla'
  fi
  display_value 'Perfil USB' "$DEVICE_USB_ID"
  display_value 'Configuración USB' "$DEVICE_USB_CONFIG"
  ok 'el ADB está autorizado; no se habilitará ADB por red'
  warn 'la recuperación no se verifica en línea: hacerlo requeriría reiniciar o entrar en bootloader'
  warn 'no hay imagen compatible verificada en esta evaluación; no se descargan imágenes ni se ejecutan comandos de flasheo'
  warn 'cualquier ruta Firefox OS 2.5 o JanOS requiere exportación respaldada, checksum, recuperación confirmada y autorización independiente para borrar datos'
  info 'JanOS para Flame queda como candidato comunitario documentado, no como sistema instalado ni validado en este teléfono'
  info 'la evaluación terminó sin escribir en el teléfono, el host, ADB, udev o USBGuard'
}

archive_entries() {
  local archive="$1"
  unzip -Z1 -- "$archive" 2>/dev/null
}

find_archive_entry() {
  local entries="$1" filename="$2"
  awk -F/ -v wanted="$filename" '$NF == wanted { print; exit }' <<< "$entries"
}

verify_archive_paths() {
  local entries="$1"

  ! awk '
    $0 ~ /^\// || $0 == ".." || $0 ~ /(^|\/)\.\.\// { found = 1 }
    END { exit(found ? 0 : 1) }
  ' <<< "$entries"
}

verify_base_archive() {
  local archive_path archive_real actual_sha entries flash_sh_entry flash_bat_entry
  local flash_script image_count system_image_count has_flame=0

  archive_path="$BASE_ARCHIVE_PATH"
  [[ "$archive_path" != *$'\n'* && "$archive_path" != *$'\r'* ]] ||
    die '--archive no puede contener saltos de línea'
  [[ -f "$archive_path" ]] || die "no existe un archivo regular: $archive_path"
  [[ -r "$archive_path" ]] || die "no se puede leer el archivo: $archive_path"
  [[ "$(basename -- "$archive_path")" == "$BASE_ARCHIVE_NAME" ]] ||
    die "el archivo debe llamarse exactamente $BASE_ARCHIVE_NAME"

  archive_real="$(readlink -f -- "$archive_path" 2>/dev/null)" ||
    die 'no se pudo resolver la ruta del archivo ZIP'
  [[ -f "$archive_real" && -r "$archive_real" ]] ||
    die 'la ruta resuelta no es un archivo legible'
  command -v sha512sum >/dev/null 2>&1 || die 'sha512sum no está disponible'
  command -v unzip >/dev/null 2>&1 || die 'unzip no está disponible'

  printf '═══ Verificación local de base Firefox OS ═══\n'
  printf 'Archivo: %s\n' "$archive_real"
  printf 'Candidato: %s\n' "$BASE_ARCHIVE_NAME"
  info 'calculando SHA512; no se ejecutará ningún contenido del archivo'
  actual_sha="$(sha512sum -- "$archive_real" | awk '{print $1}')" ||
    die 'no se pudo calcular SHA512'
  if [[ "$actual_sha" != "$BASE_ARCHIVE_SHA512" ]]; then
    printf 'SHA512 obtenido: %s\n' "$actual_sha"
    die 'SHA512 no coincide con el candidato histórico v18D; no se considera utilizable'
  fi
  ok 'SHA512 coincide con el candidato histórico v18D'

  unzip -tqq -- "$archive_real" >/dev/null ||
    die 'la estructura ZIP está dañada o no puede probarse'
  ok 'estructura ZIP legible y prueba de integridad completada'

  entries="$(archive_entries "$archive_real")" || die 'no se pudo listar el contenido del ZIP'
  [[ -n "$entries" ]] || die 'el ZIP no contiene entradas'
  verify_archive_paths "$entries" ||
    die 'el ZIP contiene rutas absolutas o segmentos ..; se rechaza'
  ok 'las rutas internas del ZIP no contienen traversal'

  flash_sh_entry="$(find_archive_entry "$entries" flash.sh)"
  flash_bat_entry="$(find_archive_entry "$entries" flash.bat)"
  [[ -n "$flash_sh_entry" ]] ||
    die 'falta flash.sh; no se considera una base Linux compatible'
  ok "flash.sh encontrado: $flash_sh_entry"
  if [[ -n "$flash_bat_entry" ]]; then
    ok "flash.bat encontrado: $flash_bat_entry"
  else
    warn 'flash.bat no está presente; el candidato sigue siendo evaluable para Linux'
  fi

  flash_script="$(unzip -p -- "$archive_real" "$flash_sh_entry" 2>/dev/null)" ||
    die 'no se pudo leer flash.sh sin ejecutarlo'
  grep -Eiq '(^|[^[:alnum:]_])fastboot([^[:alnum:]_]|$)' <<< "$flash_script" ||
    die 'flash.sh no contiene una invocación reconocible de fastboot'
  ok 'flash.sh referencia fastboot y solo fue inspeccionado como texto'
  if grep -Eiq 'flame|flame-kk|t2mobile' <<< "$flash_script"; then
    has_flame=1
  fi

  image_count="$(awk 'tolower($0) ~ /(^|\/)(boot|system|userdata|recovery|cache).*\.img$/ { count++ } END { print count + 0 }' <<< "$entries")"
  system_image_count="$(awk 'tolower($0) ~ /(^|\/)system[^\/]*\.img$/ { count++ } END { print count + 0 }' <<< "$entries")"
  if [[ "$image_count" -gt 0 ]]; then
    ok "imágenes de partición reconocibles: $image_count"
  else
    die 'no se encontraron imágenes de partición esperadas'
  fi
  [[ "$system_image_count" -gt 0 ]] || die 'falta una imagen system*.img'
  ok 'imagen system*.img encontrada'

  if [[ "$has_flame" -eq 1 ]]; then
    ok 'flash.sh contiene una referencia a Flame'
  else
    die 'flash.sh no contiene una referencia reconocible a Flame'
  fi

  printf 'Resultado: CANDIDATO VERIFICADO PARA PREPARACIÓN MANUAL\n'
  warn 'esto no autoriza reiniciar, entrar en fastboot ni ejecutar un flasheo'
  info 'la verificación no escribió en el teléfono ni descargó archivos'
}

require_readable_device() {
  [[ -n "$ADB_COMMAND" ]] || die 'adb no está instalado; ejecuta just install-android-tools --apply'
  [[ -n "$LSUSB_COMMAND" ]] || die 'lsusb no está disponible'
  usb_present || die 'no se detecta un USB Firefox OS compatible'
  has_adb_interface || die 'el perfil USB no expone ADB; selecciona ADB and DevTools en el teléfono y reconecta'

  query_adb_devices
  [[ "$ADB_QUERY_STATUS" -eq 0 ]] || die 'no se pudo consultar adb devices'
  get_device_counts
  [[ "$TOTAL_COUNT" -eq 1 && "$AUTHORIZED_COUNT" -eq 1 ]] ||
    die 'se requiere exactamente un teléfono Firefox OS autorizado en estado device'
}

list_remote() {
  validate_remote_path
  require_readable_device
  info "listando la ruta remota solicitada: $REMOTE_PATH"
  "$ADB_COMMAND" -s "$AUTHORIZED_SERIAL" shell ls -la "$REMOTE_PATH"
}

pull_remote() {
  local target_canonical
  validate_remote_path
  require_readable_device
  target_canonical="$(canonical_export_target)"
  info "extrayendo datos a $target_canonical"
  "$ADB_COMMAND" -s "$AUTHORIZED_SERIAL" pull "$REMOTE_PATH" "$target_canonical"
}

main() {
  parse_args "$@"
  require_linux_user
  resolve_commands

  case "$ACTION" in
    status) show_status ;;
    devices) show_devices ;;
    inventory) show_inventory ;;
    preflight) show_preflight ;;
    verify-base) verify_base_archive ;;
    list) list_remote ;;
    pull) pull_remote ;;
    *) die "acción interna no soportada: $ACTION" ;;
  esac
}

main "$@"
