#!/usr/bin/env bash
# v1.0.0 - Diagnóstico y lectura controlada de Firefox OS por USB.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly FIREFOXOS_USB_IDS=("05c6:9025" "05c6:9026")
readonly EXPORT_ROOT="${HOME}/Documents/firefoxos-exports"

ACTION="status"
ACTION_EXPLICIT=0
REMOTE_PATH="/"
REMOTE_EXPLICIT=0
TARGET_PATH=""

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

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  firefoxos_tools_linux.sh --status
  firefoxos_tools_linux.sh --devices
  firefoxos_tools_linux.sh --list --remote <ruta-absoluta>
  firefoxos_tools_linux.sh --pull --remote <ruta-absoluta> \
    --target ~/Documents/firefoxos-exports

Diagnóstico y lectura controlada de Firefox OS por USB. No ofrece shell remoto,
adb push, borrado, reinicio, desbloqueo, flasheo ni ADB por red.
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
    list) list_remote ;;
    pull) pull_remote ;;
    *) die "acción interna no soportada: $ACTION" ;;
  esac
}

main "$@"
