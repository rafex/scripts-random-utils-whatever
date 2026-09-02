#!/usr/bin/env bash
# v1.0.0 - Acciones cerradas para ADB, APKs de laboratorio y scrcpy.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="status"
ACTION_EXPLICIT=0
APK_PATH=""
REPLACE=0
ADB_COMMAND=""
SCRCPY_COMMAND=""
AUTHORIZED_COUNT=0
TOTAL_COUNT=0
UNAUTHORIZED_COUNT=0
OFFLINE_COUNT=0
UNKNOWN_COUNT=0

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  android_tools_linux.sh --status
  android_tools_linux.sh --devices
  android_tools_linux.sh --install-apk --path <archivo.apk> [--replace]
  android_tools_linux.sh --scrcpy

Acciones limitadas para usar ADB como usuario normal. No ofrece shell remoto,
adb root, remount, borrado, desbloqueo de bootloader ni flasheo.
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
      --devices) choose_action devices ;;
      --install-apk) choose_action install-apk ;;
      --scrcpy) choose_action scrcpy ;;
      --path)
        (($# >= 2)) || die '--path requiere un archivo APK'
        APK_PATH="$2"
        shift
        ;;
      --replace) REPLACE=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  if [[ "$ACTION" != install-apk && -n "$APK_PATH" ]]; then
    die '--path solo se puede usar con --install-apk'
  fi
  if [[ "$ACTION" != install-apk && "$REPLACE" -eq 1 ]]; then
    die '--replace solo se puede usar con --install-apk'
  fi
  if [[ "$ACTION" == install-apk && -z "$APK_PATH" ]]; then
    die '--install-apk requiere --path <archivo.apk>'
  fi
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; ADB y scrcpy no requieren sudo'
}

resolve_commands() {
  ADB_COMMAND="$(command -v adb 2>/dev/null || true)"
  SCRCPY_COMMAND="$(command -v scrcpy 2>/dev/null || true)"
}

require_adb() {
  [[ -n "$ADB_COMMAND" ]] || die 'adb no está instalado; ejecuta just install-android-tools --apply'
}

get_device_counts() {
  local devices_output serial state
  require_adb
  devices_output="$("$ADB_COMMAND" devices 2>/dev/null)" \
    || die 'adb no pudo consultar los dispositivos; revisa el servicio USB y las reglas udev'
  AUTHORIZED_COUNT=0
  TOTAL_COUNT=0
  UNAUTHORIZED_COUNT=0
  OFFLINE_COUNT=0
  UNKNOWN_COUNT=0
  while IFS= read -r serial state; do
    [[ -n "${serial:-}" && -n "${state:-}" ]] || continue
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    case "$state" in
      device) AUTHORIZED_COUNT=$((AUTHORIZED_COUNT + 1)) ;;
      unauthorized) UNAUTHORIZED_COUNT=$((UNAUTHORIZED_COUNT + 1)) ;;
      offline) OFFLINE_COUNT=$((OFFLINE_COUNT + 1)) ;;
      *) UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
    esac
  done < <(printf '%s\n' "$devices_output" | awk 'NR > 1 && NF >= 2 { print $1, $2 }')
}

show_devices() {
  get_device_counts
  printf '═══ Dispositivos Android ═══\n'
  if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    info 'no conectado'
    return 0
  fi
  printf 'total=%d autorizados=%d no_autorizados=%d offline=%d otros=%d\n' \
    "$TOTAL_COUNT" "$AUTHORIZED_COUNT" "$UNAUTHORIZED_COUNT" "$OFFLINE_COUNT" "$UNKNOWN_COUNT"
  if [[ "$UNAUTHORIZED_COUNT" -gt 0 ]]; then
    warn 'hay un teléfono pendiente de aceptar la huella RSA en su pantalla'
  fi
  if [[ "$OFFLINE_COUNT" -gt 0 ]]; then
    warn 'hay un dispositivo offline; desbloquea el teléfono y reconecta el cable'
  fi
}

require_one_device() {
  get_device_counts
  if [[ "$TOTAL_COUNT" -ne 1 || "$AUTHORIZED_COUNT" -ne 1 ]]; then
    if [[ "$TOTAL_COUNT" -eq 0 ]]; then
      die 'no hay un teléfono Android autorizado conectado; ejecuta --devices y acepta la huella RSA'
    fi
    die 'se requiere exactamente un teléfono Android autorizado; no se elige un dispositivo ambiguo'
  fi
}

validate_apk() {
  local canonical owner_uid user_uid
  [[ -e "$APK_PATH" ]] || die "no existe el archivo APK: $APK_PATH"
  canonical="$(realpath -e -- "$APK_PATH" 2>/dev/null)" \
    || die 'no se pudo resolver la ruta del APK'
  [[ -f "$canonical" && -r "$canonical" ]] || die 'el APK debe ser un archivo regular y legible'
  [[ "${canonical,,}" == *.apk ]] || die 'el archivo debe terminar en .apk'
  owner_uid="$(stat -c '%u' -- "$canonical" 2>/dev/null || true)"
  user_uid="$(id -u)"
  [[ "$owner_uid" == "$user_uid" ]] || die 'el APK debe pertenecer al usuario actual'
  case "$canonical" in
    /boot/*|/dev/*|/etc/*|/lib/*|/lib64/*|/proc/*|/root/*|/run/*|/sbin/*|/sys/*|/usr/*|/var/*)
      die 'por seguridad no se aceptan APK ubicadas en rutas del sistema' ;;
  esac
  APK_PATH="$canonical"
}

install_apk() {
  local -a install_args=(install)
  validate_apk
  require_one_device
  if [[ "$REPLACE" -eq 1 ]]; then
    install_args+=(-r)
    info 'actualización explícita de la APK solicitada con --replace'
  fi
  info 'instalando una APK en el único dispositivo autorizado'
  "$ADB_COMMAND" "${install_args[@]}" "$APK_PATH"
  ok 'operación ADB finalizada'
}

run_scrcpy() {
  [[ -n "${DISPLAY:-}" ]] || die 'scrcpy requiere una sesión gráfica X11 con DISPLAY'
  [[ -n "$SCRCPY_COMMAND" ]] || die 'scrcpy no está instalado; ejecuta just install-android-tools --apply'
  require_one_device
  info 'iniciando scrcpy como usuario normal'
  "$SCRCPY_COMMAND"
}

show_status() {
  local rule groups service_state
  printf '═══ Herramientas Android de usuario ═══\n'
  resolve_commands
  if [[ -n "$ADB_COMMAND" ]]; then
    ok "adb disponible: $ADB_COMMAND"
    "$ADB_COMMAND" version 2>/dev/null | sed -n '1p'
  else
    warn 'adb ausente'
  fi
  if [[ -n "$SCRCPY_COMMAND" ]]; then
    ok "scrcpy disponible: $SCRCPY_COMMAND"
    "$SCRCPY_COMMAND" --version 2>/dev/null | sed -n '1p'
  else
    warn 'scrcpy ausente'
  fi
  if command -v fastboot >/dev/null 2>&1; then
    ok 'fastboot disponible'
  else
    warn 'fastboot ausente'
  fi
  rule=''
  for rule in /usr/lib/udev/rules.d/51-android.rules /lib/udev/rules.d/51-android.rules; do
    if [[ -r "$rule" ]]; then
      ok "regla udev Android: $rule"
      break
    fi
  done
  if [[ -z "$rule" || ! -r "$rule" ]]; then
    warn 'regla udev Android ausente'
  fi
  if command -v systemctl >/dev/null 2>&1; then
    service_state="$(systemctl is-active usbguard.service 2>/dev/null || true)"
    info "USBGuard: ${service_state:-no disponible}; no se autoriza ningún teléfono automáticamente"
  fi
  groups="$(id -nG 2>/dev/null || true)"
  if [[ "$groups" == *plugdev* ]]; then
    info 'plugdev presente; no se modificaron grupos'
  else
    info 'no se modificaron grupos del usuario'
  fi
  info 'el servidor ADB solo se inicia al usar --devices, --install-apk o --scrcpy'
  info 'ADB por red, shell remoto, root, remount y fastboot automático no están habilitados'
}

main() {
  parse_args "$@"
  require_linux_user
  resolve_commands
  case "$ACTION" in
    status) show_status ;;
    devices) show_devices ;;
    install-apk) install_apk ;;
    scrcpy) run_scrcpy ;;
  esac
}

main "$@"
