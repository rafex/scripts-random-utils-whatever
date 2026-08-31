#!/usr/bin/env bash
# shellcheck shell=bash
# Configura el módem WWAN Sierra EM7455 para datos OXXO Cel y consulta SMS.
set -Eeuo pipefail

readonly APN="internet.mvne1.com"
readonly PROFILE_NAME="${WWAN_OXXOCEL_PROFILE:-OXXO Cel}"
readonly ROUTE_METRIC=700
readonly FCC_USB_ID="1199:9079"
readonly FCC_CONFIG_DIR="/etc/ModemManager/fcc-unlock.d"
readonly FCC_AVAILABLE_DIR="/usr/share/ModemManager/fcc-unlock.available.d"
readonly FCC_LINK="${FCC_CONFIG_DIR}/${FCC_USB_ID}"
TARGET_USER="$(id -un)"
readonly TARGET_USER
readonly REQUIRED_PACKAGES=(
  network-manager
  modemmanager
  usb-modeswitch
  libmbim-utils
  libqmi-utils
  rfkill
  mobile-broadband-provider-info
)

ACTION="check"
MISSING_PACKAGES=()

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf '%b\n' "${CYAN}${BOLD}→${RESET} $*"; }
success() { printf '%b\n' "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { printf '%b\n' "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() {
  printf '%b\n' "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Uso:
  $0 --check
  $0 --plan
  $0 --apply
  $0 --status
  $0 --connect
  $0 --disconnect
  $0 --sms-list

Acciones:
  --check       Audita driver, servicios, módem, SIM y perfil sin modificar.
  --plan        Muestra paquetes y configuración prevista sin modificar.
  --apply       Instala dependencias y crea/actualiza el perfil OXXO Cel.
  --status      Muestra el estado actual sin modificar ni revelar IMEI.
  --connect     Activa WWAN y conecta por UUID como usuario normal; requiere TTY.
  --disconnect  Desconecta el perfil OXXO Cel.
  --sms-list    Lista los SMS expuestos por ModemManager.
  -h, --help    Muestra esta ayuda.

El perfil usa el APN ${APN}, no guarda PIN, usuario ni contraseña y no se
conecta automáticamente. Para cambiar el nombre del perfil usa:
  WWAN_OXXOCEL_PROFILE='Otro nombre' $0 --apply
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --status) ACTION="status"; shift ;;
      --connect) ACTION="connect"; shift ;;
      --disconnect) ACTION="disconnect"; shift ;;
      --sms-list) ACTION="sms-list"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script solo funciona en Linux"
  [[ "$(id -u)" -ne 0 ]] || die "ejecuta el script como ${TARGET_USER}; solo se usa sudo internamente"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "no se encontró '$1'"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
    | grep -Fxq 'install ok installed'
}

collect_missing_packages() {
  MISSING_PACKAGES=()
  local package
  for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! package_installed "$package"; then
      MISSING_PACKAGES+=("$package")
    fi
  done
}

find_modem_path() {
  mmcli -L 2>/dev/null \
    | sed -nE 's#.*(/org/freedesktop/ModemManager1/Modem/[0-9]+).*#\1#p' \
    | sed -n '1p' || true
}

find_modem_id() {
  local modem_path
  modem_path="$(find_modem_path)"
  [[ -n "$modem_path" ]] || return 1
  basename "$modem_path"
}

fcc_module_present() {
  local device vendor product
  for device in /sys/bus/usb/devices/*; do
    [[ -r "$device/idVendor" && -r "$device/idProduct" ]] || continue
    vendor="$(<"$device/idVendor")"
    product="$(<"$device/idProduct")"
    if [[ "$vendor:$product" == "$FCC_USB_ID" ]]; then
      return 0
    fi
  done

  command -v lsusb >/dev/null 2>&1 \
    && lsusb -d "$FCC_USB_ID" 2>/dev/null | grep -q .
}

fcc_available_script() {
  local candidate
  for candidate in \
    "${FCC_AVAILABLE_DIR}/${FCC_USB_ID}" \
    "${FCC_AVAILABLE_DIR}/${FCC_USB_ID%:*}"; do
    if [[ -f "$candidate" || -L "$candidate" ]] && [[ -r "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

show_fcc_status() {
  local target available
  printf '  FCC USB ID esperado: %s\n' "$FCC_USB_ID"
  if fcc_module_present; then
    success "EM7455 ${FCC_USB_ID} detectada"
  else
    info "EM7455 ${FCC_USB_ID} no está visible por USB en este momento"
  fi

  available="$(fcc_available_script || true)"
  if [[ -z "$available" ]]; then
    warn "no se encontró el script FCC disponible en ${FCC_AVAILABLE_DIR}"
    return 0
  fi

  if [[ -L "$FCC_LINK" ]]; then
    target="$(readlink -f "$FCC_LINK" 2>/dev/null || true)"
    if [[ -n "$target" && "$target" == "$(readlink -f "$available")" ]]; then
      success "desbloqueo FCC persistente configurado: ${FCC_LINK}"
    else
      warn "existe ${FCC_LINK}, pero no apunta al script FCC disponible esperado"
    fi
  elif [[ -e "$FCC_LINK" ]]; then
    warn "${FCC_LINK} existe y no es un enlace simbólico; no se sobrescribirá"
  else
    warn "desbloqueo FCC no habilitado: falta ${FCC_LINK}"
  fi
}

ensure_fcc_unlock() {
  local available current backup_root backup_path=""

  if ! fcc_module_present; then
    warn "no se habilitará FCC todavía: la EM7455 ${FCC_USB_ID} no está visible por USB"
    return 0
  fi

  available="$(fcc_available_script || true)"
  if [[ -z "$available" ]]; then
    warn "Debian no instaló un script FCC para ${FCC_USB_ID}; revisa el paquete ModemManager"
    return 0
  fi

  sudo install -d -m 0755 "$FCC_CONFIG_DIR"
  if [[ -L "$FCC_LINK" ]]; then
    current="$(readlink -f "$FCC_LINK" 2>/dev/null || true)"
    if [[ -n "$current" && "$current" == "$(readlink -f "$available")" ]]; then
      success "desbloqueo FCC ya estaba configurado: ${FCC_LINK}"
      return 0
    fi
  elif [[ -e "$FCC_LINK" ]]; then
    die "${FCC_LINK} existe y no es un enlace; no se modificará automáticamente"
  fi

  backup_root="/var/backups/rafex-wwan-oxxocel"
  if [[ -e "$FCC_LINK" || -L "$FCC_LINK" ]]; then
    sudo install -d -m 0700 "$backup_root"
    backup_path="${backup_root}/1199:9079.bak.$(date +%Y%m%d_%H%M%S)"
    sudo mv "$FCC_LINK" "$backup_path"
    info "enlace FCC anterior respaldado en ${backup_path}"
  fi

  sudo ln -s "$available" "$FCC_LINK"
  success "desbloqueo FCC habilitado: ${FCC_LINK} -> ${available}"

  if ! sudo systemctl restart ModemManager.service; then
    sudo rm -f "$FCC_LINK"
    if [[ -n "$backup_path" ]]; then
      sudo mv "$backup_path" "$FCC_LINK"
    fi
    die "no se pudo reiniciar ModemManager después de habilitar FCC; se restauró el estado anterior"
  fi
  success "ModemManager reiniciado para aplicar el desbloqueo FCC"
}

modem_field() {
  local raw="$1"
  local field="$2"
  sed -nE \
    -e "s/.*\\|[[:space:]]*${field}:[[:space:]]*//Ip" \
    -e "s/^[[:space:]]*${field}:[[:space:]]*//Ip" \
    <<< "$raw" | sed -n '1p' | sed -E "s/^'//; s/'$//"
}

modem_sim_status() {
  local raw="$1"
  local state lock sim_path failed_reason
  local unlock_retries enabled_locks
  state="$(modem_field "$raw" "state" | tr '[:upper:]' '[:lower:]')"
  lock="$(modem_field "$raw" "lock" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$lock" ]]; then
    lock="$(modem_field "$raw" "sim lock" | tr '[:upper:]' '[:lower:]')"
  fi
  sim_path="$(modem_field "$raw" "primary sim path" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$sim_path" ]]; then
    sim_path="$(modem_field "$raw" "sim" | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ -z "$sim_path" ]]; then
    sim_path="$(modem_field "$raw" "sim slot paths" | tr '[:upper:]' '[:lower:]')"
  fi
  failed_reason="$(modem_field "$raw" "failed reason" | tr '[:upper:]' '[:lower:]')"
  unlock_retries="$(modem_field "$raw" "unlock retries" | tr '[:upper:]' '[:lower:]')"
  enabled_locks="$(modem_field "$raw" "enabled locks" | tr '[:upper:]' '[:lower:]')"

  if grep -qi 'sim-missing' <<< "$raw" \
    || [[ "$sim_path" == *sim-missing* || "$sim_path" == none ]]; then
    printf '%s\n' 'missing'
  elif [[ "$state" == locked* && ("$lock" == *sim-pin2* || "$failed_reason" == *sim-pin2*) ]]; then
    printf '%s\n' 'pin2-locked'
  elif [[ "$state" == locked* && ("$lock" == *sim-pin* || "$failed_reason" == *sim-pin*) ]]; then
    printf '%s\n' 'pin-locked'
  elif [[ "$lock" == *sim-pin2* || "$unlock_retries" == *sim-pin2* || "$enabled_locks" == *fixed-dialing* ]]; then
    printf '%s\n' 'pin2-capability'
  elif [[ -n "$sim_path" && "$sim_path" != *unknown* ]]; then
    printf '%s\n' 'detected'
  else
    printf '%s\n' 'unknown'
  fi
}

report_modem_state() {
  local raw="$1"
  local state power sim_status failed_reason
  state="$(modem_field "$raw" "state")"
  power="$(modem_field "$raw" "power state")"
  failed_reason="$(modem_field "$raw" "failed reason")"
  sim_status="$(modem_sim_status "$raw")"

  printf '  estado módem: %s\n' "${state:-desconocido}"
  printf '  estado energía: %s\n' "${power:-desconocido}"
  case "$sim_status" in
    missing)
      warn "SIM ausente o no detectada" ;;
    pin2-locked)
      warn "SIM bloqueada por PIN2; no se intentará adivinar ni guardar el PIN2" ;;
    pin2-capability)
      warn "ModemManager reporta PIN2/fixed-dialing como función de la SIM; no bloquea necesariamente los datos" ;;
    pin-locked)
      warn "SIM bloqueada por PIN; desbloquéala de forma interactiva antes de conectar" ;;
    detected)
      success "SIM detectada" ;;
    *)
      warn "no se pudo determinar el estado de la SIM" ;;
  esac

  if [[ "$state" == disabled* || "$power" == off* ]]; then
    warn "módem deshabilitado o apagado; revisa WWAN en BIOS y el estado de rfkill"
  elif [[ "$state" == registered* ]]; then
    warn "módem registrado en la red, pero todavía sin conexión de datos"
  elif [[ "$state" == connected* ]]; then
    success "módem registrado y con conexión de datos"
  elif [[ "$state" == failed* ]]; then
    warn "ModemManager reporta fallo${failed_reason:+: $failed_reason}"
  elif [[ -n "$state" ]]; then
    info "módem habilitado; estado de red: $state"
  fi
}

active_gsm_profile() {
  local uuid="$1"
  local active

  active="$(nmcli -t -g connection.uuid,connection.type connection show --active 2>/dev/null || true)"
  if awk -F: -v wanted="$uuid" '$1 == wanted && $2 == "gsm" { found = 1 } END { exit !found }' <<< "$active"; then
    return 0
  fi

  # Compatibilidad con versiones que solo aceptan los alias cortos en este contexto.
  active="$(nmcli -t -g UUID,TYPE connection show --active 2>/dev/null || true)"
  awk -F: -v wanted="$uuid" '$1 == wanted && $2 == "gsm" { found = 1 } END { exit !found }' <<< "$active"
}

require_interactive_terminal() {
  [[ -t 0 && -t 1 ]] || die "--connect requiere una terminal interactiva; ejecútalo desde la sesión local o usa ssh -tt"
}

wait_for_modem_ready() {
  local attempts=15
  local attempt raw modem_id state sim_status

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    modem_id="$(find_modem_id || true)"
    if [[ -n "$modem_id" ]]; then
      raw="$(mmcli -m "$modem_id" 2>&1 || true)"
      sim_status="$(modem_sim_status "$raw")"
      case "$sim_status" in
        missing)
          die "la SIM está ausente o no es detectada por la EM7455" ;;
        pin2-locked)
          warn "la SIM reporta PIN2; se intentará únicamente la conexión de datos"
          info "si nmcli solicita PIN2, cancela: no se puede omitir ni adivinar ese código"
          return 0 ;;
        pin2-capability)
          warn "la SIM reporta PIN2/fixed-dialing como capacidad; se intentará únicamente la conexión de datos"
          return 0 ;;
        pin-locked)
          info "la SIM está protegida por PIN; se continuará para que nmcli --ask pueda solicitarlo"
          return 0 ;;
      esac
      state="$(modem_field "$raw" "state" | tr '[:upper:]' '[:lower:]')"
      if [[ "$state" != disabled* && "$state" != failed* && -n "$state" ]]; then
        return 0
      fi
    fi
    sleep 1
  done

  modem_id="$(find_modem_id || true)"
  if [[ -n "$modem_id" ]]; then
    raw="$(mmcli -m "$modem_id" 2>&1 || true)"
    report_modem_state "$raw"
    state="$(modem_field "$raw" "state" | tr '[:upper:]' '[:lower:]')"
    if [[ "$state" == disabled* ]]; then
      die "el módem permanece deshabilitado; revisa WWAN en BIOS, rfkill y ModemManager como acción administrativa separada"
    fi
  fi
  die "ModemManager no dejó listo ningún módem después de ${attempts} segundos"
}

profile_exists() {
  [[ -n "$(profile_uuid)" ]]
}

nmcli_profile_rows() {
  local -a nmcli_cmd=(nmcli)
  if [[ "${1:-}" == root ]]; then
    nmcli_cmd=(sudo nmcli)
  fi

  "${nmcli_cmd[@]}" -t -g connection.id,connection.uuid,connection.type connection show 2>/dev/null || true
}

nmcli_active_profile_rows() {
  local -a nmcli_cmd=(nmcli)
  if [[ "${1:-}" == root ]]; then
    nmcli_cmd=(sudo nmcli)
  fi

  "${nmcli_cmd[@]}" -t -g connection.id,connection.uuid,connection.type connection show --active 2>/dev/null || true
}

profile_uuid() {
  local uuid rows

  rows="$(nmcli_profile_rows "${1:-}")"
  uuid="$(awk -F: -v wanted="$PROFILE_NAME" \
    '$1 == wanted && $3 == "gsm" { print $2; exit }' <<< "$rows")"
  if [[ -n "$uuid" ]]; then
    printf '%s\n' "$uuid"
    return 0
  fi

  # Algunas versiones o políticas de NetworkManager ocultan perfiles de
  # sistema en la lista general, aunque dejan visible la conexión activa.
  rows="$(nmcli_active_profile_rows "${1:-}")"
  awk -F: -v wanted="$PROFILE_NAME" \
    '$1 == wanted && $3 == "gsm" { print $2; exit }' <<< "$rows"
}

profile_count() {
  local rows
  rows="$(nmcli_profile_rows "${1:-}")"
  awk -F: -v wanted="$PROFILE_NAME" \
    '$1 == wanted && $3 == "gsm" { count++ } END { print count + 0 }' <<< "$rows"
}

show_packages() {
  collect_missing_packages
  if ((${#MISSING_PACKAGES[@]} == 0)); then
    success "dependencias WWAN instaladas"
  else
    warn "paquetes ausentes: ${MISSING_PACKAGES[*]}"
  fi
}

show_driver_state() {
  if command -v lsmod >/dev/null 2>&1 \
    && lsmod | awk '$1 == "cdc_mbim" { found = 1 } END { exit !found }'; then
    success "driver cdc_mbim cargado"
  else
    warn "driver cdc_mbim no aparece cargado"
  fi

  if compgen -G '/dev/cdc-wdm*' >/dev/null; then
    printf '  nodos MBIM: '
    compgen -G '/dev/cdc-wdm*' | paste -sd ' ' -
  else
    warn "no existe ningún nodo /dev/cdc-wdm*"
  fi

  if command -v nmcli >/dev/null 2>&1; then
    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null \
      | awk '$2 == "gsm" || NR == 1'
    nmcli radio 2>/dev/null
  fi
}

show_modem_summary() {
  local modem_id raw voice_output
  require_command mmcli

  if ! modem_id="$(find_modem_id)"; then
    warn "ModemManager no detecta ningún módem WWAN"
    return 0
  fi

  info "módem detectado: índice ${modem_id}"
  raw="$(mmcli -m "$modem_id" 2>&1 || true)"
  if [[ -n "$raw" ]]; then
    while IFS= read -r line; do
      if [[ "$line" =~ (manufacturer|model|firmware\ revision|drivers|plugin|primary\ port|ports|state|failed\ reason|power\ state|lock|unlock\ retries|enabled\ locks|registration|packet\ service\ state|access\ tech|supported|current|sim\ slot\ paths): ]]; then
        printf '  %s\n' "$line"
      fi
    done <<< "$raw"
    report_modem_state "$raw"
  else
    warn "no se pudo consultar el módem ${modem_id}"
  fi

  voice_output="$(mmcli -m "$modem_id" --voice-list-calls 2>&1 || true)"
  if grep -qi 'no voice capabilities' <<< "$voice_output"; then
    warn "la EM7455 no expone capacidades de voz; no se pueden hacer llamadas nativas"
  elif grep -qi 'error\|failed\|not enabled' <<< "$voice_output"; then
    warn "no se pudo determinar la capacidad de voz; el módem puede estar deshabilitado o sin SIM"
  else
    info "ModemManager expone una interfaz de voz; no se configurará automáticamente"
  fi

}

show_profile_status() {
  if ! command -v nmcli >/dev/null 2>&1; then
    warn "nmcli no está disponible; no se puede revisar el perfil"
    return 0
  fi

  if ! profile_exists; then
    warn "perfil NetworkManager ausente: ${PROFILE_NAME}"
    return 0
  fi

  success "perfil NetworkManager presente: ${PROFILE_NAME}"
  local uuid
  uuid="$(profile_uuid)"
  printf '  uuid: %s\n' "$uuid"
  printf '  tipo: %s\n' "$(nmcli -g connection.type connection show uuid "$uuid")"
  printf '  autoconnect: %s\n' "$(nmcli -g connection.autoconnect connection show uuid "$uuid")"
  printf '  interfaz: %s\n' "$(nmcli -g connection.interface-name connection show uuid "$uuid")"
  if active_gsm_profile "$uuid"; then
    success "perfil OXXO Cel activo: conexión de datos en curso"
  else
    info "perfil OXXO Cel no está activo; no hay conexión de datos mediante este perfil"
  fi
  nmcli -g gsm.apn,gsm.auto-config,gsm.home-only,connection.autoconnect,\
    connection.autoconnect-priority,ipv4.route-metric,ipv6.route-metric \
    connection show uuid "$uuid" 2>/dev/null || true
}

action_check() {
  local missing_tools=0
  local tool
  for tool in nmcli mmcli systemctl lsmod; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      warn "comando ausente: ${tool}"
      missing_tools=1
    fi
  done

  show_packages
  show_fcc_status
  show_driver_state
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet NetworkManager; then
      success "NetworkManager activo"
    else
      warn "NetworkManager no está activo"
    fi
    if systemctl is-active --quiet ModemManager; then
      success "ModemManager activo"
    else
      warn "ModemManager no está activo"
    fi
  fi
  if command -v mmcli >/dev/null 2>&1; then
    show_modem_summary
  fi
  show_profile_status

  if ((missing_tools != 0 || ${#MISSING_PACKAGES[@]} != 0)); then
    return 1
  fi
  success "auditoría WWAN completada; SIM y voz se validan por separado"
}

action_plan() {
  collect_missing_packages
  printf '%b\n' "${BOLD}═══ Plan WWAN OXXO Cel ═══${RESET}"
  printf 'APN=%s\n' "$APN"
  printf 'perfil=%s\n' "$PROFILE_NAME"
  printf 'usuario=%s\n' "$TARGET_USER"
  if ((${#MISSING_PACKAGES[@]} > 0)); then
    info "[plan] sudo apt-get update"
    info "[plan] sudo apt-get install -y ${MISSING_PACKAGES[*]}"
  else
    success "[plan] no faltan paquetes WWAN"
  fi
  info "[plan] habilitar NetworkManager y ModemManager"
  if fcc_module_present && [[ -n "$(fcc_available_script || true)" ]]; then
    if [[ -L "$FCC_LINK" ]]; then
      info "[plan] conservar o validar el enlace FCC ${FCC_LINK}"
    else
      info "[plan] crear ${FCC_LINK} apuntando al script FCC oficial de Debian"
      info "[plan] reiniciar ModemManager para aplicar el desbloqueo FCC"
    fi
  else
    info "[plan] revisar FCC después de insertar/detectar la EM7455 ${FCC_USB_ID}"
  fi
  info "[plan] crear o actualizar el perfil GSM ${PROFILE_NAME}"
  info "[plan] APN ${APN}, IPv4/IPv6 automático, métrica 700"
  info "[plan] autoconnect desactivado y roaming desactivado"
  info "[plan] no activar la conexión ni almacenar PIN o credenciales"
  success "plan terminado; no se modificó el sistema"
}

ensure_packages() {
  collect_missing_packages
  if ((${#MISSING_PACKAGES[@]} == 0)); then
    success "dependencias WWAN ya estaban instaladas"
    return 0
  fi

  sudo apt-get update
  sudo apt-get install -y "${MISSING_PACKAGES[@]}"
}

validate_sudo() {
  if ! sudo -v; then
    die "no se pudo validar sudo; ejecuta --apply desde una terminal interactiva y vuelve a intentarlo"
  fi
}

configure_profile() {
  local profile_count_value profile_type profile_ref profile_scope
  local -a nmcli_cmd=(nmcli)
  require_command nmcli

  # NetworkManager puede reservar la creación de perfiles del sistema para
  # root aunque el usuario tenga permitido administrarlos después. --connect
  # nunca usa esta ruta privilegiada; solo --apply llega aquí con sudo validado.
  if [[ "$ACTION" == apply ]]; then
    nmcli_cmd=(sudo nmcli)
    profile_scope=root
  fi

  profile_ref="$(profile_uuid "$profile_scope")"
  if [[ -n "$profile_ref" ]]; then
    profile_type="$("${nmcli_cmd[@]}" -g connection.type connection show uuid "$profile_ref" 2>/dev/null | sed -n '1p')"
    [[ "$profile_type" == "gsm" ]] \
      || die "ya existe '${PROFILE_NAME}' con tipo '${profile_type}', no se sobrescribirá"
    info "actualizando perfil GSM ${PROFILE_NAME} (${profile_ref})"
    profile_count_value="$(profile_count "$profile_scope")"
    if ((profile_count_value > 1)); then
      warn "hay ${profile_count_value} perfiles GSM llamados '${PROFILE_NAME}'; se reutiliza ${profile_ref} y no se creará otro"
    fi
  else
    info "creando perfil GSM ${PROFILE_NAME}"
    "${nmcli_cmd[@]}" connection add type gsm ifname '*' con-name "$PROFILE_NAME" apn "$APN" >/dev/null \
      || die "NetworkManager no permitió crear el perfil '${PROFILE_NAME}'; revisa sudo y Polkit"
    profile_ref="$(profile_uuid root)"
  fi

  [[ -n "$profile_ref" ]] \
    || die "NetworkManager no devolvió el UUID del perfil '${PROFILE_NAME}'; revisa el servicio y los permisos"

  "${nmcli_cmd[@]}" connection modify uuid "$profile_ref" \
    gsm.apn "$APN" \
    gsm.auto-config no \
    gsm.home-only yes \
    gsm.username '' \
    gsm.password '' \
    gsm.password-flags not-required \
    gsm.pin '' \
    gsm.pin-flags not-required \
    connection.autoconnect no \
    connection.autoconnect-priority -100 \
    connection.permissions '' \
    connection.metered yes \
    ipv4.method auto \
    ipv4.never-default no \
    ipv4.route-metric "$ROUTE_METRIC" \
    ipv6.method auto \
    ipv6.never-default no \
    ipv6.route-metric "$ROUTE_METRIC"
  success "perfil ${PROFILE_NAME} configurado; conexión manual y Wi-Fi preferida"
}

action_apply() {
  require_command sudo
  validate_sudo
  ensure_packages
  if ! sudo systemctl enable --now NetworkManager.service ModemManager.service; then
    die "no se pudieron activar NetworkManager y ModemManager; revisa systemctl status NetworkManager ModemManager"
  fi
  ensure_fcc_unlock
  configure_profile
  if ! find_modem_id >/dev/null 2>&1; then
    warn "perfil creado, pero ModemManager todavía no detecta el módem"
  fi
  if ! compgen -G '/dev/cdc-wdm*' >/dev/null; then
    warn "no se detecta /dev/cdc-wdm*; inserta la SIM y revisa el estado del módem"
  fi
  info "usa --connect únicamente después de insertar la SIM"
}

action_status() {
  printf '%b\n' "${BOLD}═══ Estado WWAN OXXO Cel ═══${RESET}"
  if command -v nmcli >/dev/null 2>&1; then
    show_driver_state
    show_fcc_status
    show_profile_status
  fi
  if command -v mmcli >/dev/null 2>&1; then
    show_modem_summary
  fi
}

action_connect() {
  local modem_id profile_ref
  require_interactive_terminal
  require_command nmcli
  require_command mmcli
  profile_exists || die "falta el perfil '${PROFILE_NAME}'; ejecuta primero --apply"
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem"
  profile_ref="$(profile_uuid)"
  info "activando radio WWAN como ${TARGET_USER}"
  nmcli radio wwan on || die "NetworkManager no permitió activar WWAN para el usuario actual"
  info "esperando a que ModemManager actualice el estado"
  wait_for_modem_ready
  info "conectando ${PROFILE_NAME} por UUID; solo se solicitará autenticación necesaria para datos"
  warn "no se enviará PIN2, PUK2 ni ningún comando AT"
  if ! nmcli --ask connection up uuid "$profile_ref"; then
    modem_id="$(find_modem_id || true)"
    if [[ -n "$modem_id" ]]; then
      report_modem_state "$(mmcli -m "$modem_id" 2>&1 || true)"
    fi
    die "NetworkManager no pudo activar el perfil; revisa el estado anterior y el journal de NetworkManager"
  fi
  success "conexión WWAN activa"
}

action_disconnect() {
  require_command nmcli
  profile_exists || die "no existe el perfil '${PROFILE_NAME}'"
  nmcli connection down id "$PROFILE_NAME" >/dev/null 2>&1 \
    || warn "el perfil no estaba conectado"
  success "perfil WWAN desconectado"
}

action_sms_list() {
  local modem_id raw sim_status
  require_command mmcli
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem"
  raw="$(mmcli -m "$modem_id" 2>&1 || true)"
  sim_status="$(modem_sim_status "$raw")"
  case "$sim_status" in
    missing) die "la SIM está ausente o no es detectada por la EM7455" ;;
    pin2-locked) die "la SIM está bloqueada por PIN2; desbloquéala manualmente, sin guardar el PIN2" ;;
    pin-locked) die "la SIM está bloqueada por PIN; desbloquéala de forma interactiva" ;;
  esac
  mmcli -m "$modem_id" --messaging-list-sms
}

parse_args "$@"
require_linux

case "$ACTION" in
  check) action_check ;;
  plan) action_plan ;;
  apply) action_apply ;;
  status) action_status ;;
  connect) action_connect ;;
  disconnect) action_disconnect ;;
  sms-list) action_sms_list ;;
  *) die "acción interna inválida: ${ACTION}" ;;
esac
