#!/usr/bin/env bash
# shellcheck shell=bash
# Configura el módem WWAN Sierra EM7455 para datos OXXO Cel y consulta SMS.
set -Eeuo pipefail

readonly APN="internet.mvne1.com"
readonly PROFILE_NAME="${WWAN_OXXOCEL_PROFILE:-OXXO Cel}"
readonly ROUTE_METRIC=700
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
  --connect     Activa WWAN y conecta el perfil usando nmcli --ask.
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

profile_exists() {
  [[ -n "$(profile_uuid)" ]]
}

profile_uuid() {
  nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null \
    | awk -F: -v wanted="$PROFILE_NAME" \
      '$1 == wanted && $3 == "gsm" { print $2; exit }'
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
  if raw="$(mmcli -m "$modem_id" 2>&1)"; then
    while IFS= read -r line; do
      if [[ "$line" =~ (manufacturer|model|firmware\ revision|drivers|plugin|primary\ port|ports|state|failed\ reason|power\ state|supported|current|sim\ slot\ paths): ]]; then
        printf '  %s\n' "$line"
      fi
    done <<< "$raw"
  else
    warn "no se pudo consultar el módem ${modem_id}"
    printf '%s\n' "$raw" | sed -E '/imei:|equipment id:|device id:/d' >&2
  fi

  voice_output="$(mmcli -m "$modem_id" --voice-list-calls 2>&1 || true)"
  if grep -qi 'no voice capabilities' <<< "$voice_output"; then
    warn "la EM7455 no expone capacidades de voz; no se pueden hacer llamadas nativas"
  elif grep -qi 'error\|failed\|not enabled' <<< "$voice_output"; then
    warn "no se pudo determinar la capacidad de voz; el módem puede estar deshabilitado o sin SIM"
  else
    info "ModemManager expone una interfaz de voz; no se configurará automáticamente"
  fi

  if grep -qi 'sim-missing' <<< "${raw:-}"; then
    warn "SIM no detectada; inserta la tarjeta antes de conectar o consultar SMS"
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
  local profile_type profile_ref
  require_command nmcli

  if profile_exists; then
    profile_ref="$(profile_uuid)"
    profile_type="$(nmcli -g connection.type connection show uuid "$profile_ref" 2>/dev/null | sed -n '1p')"
    [[ "$profile_type" == "gsm" ]] \
      || die "ya existe '${PROFILE_NAME}' con tipo '${profile_type}', no se sobrescribirá"
    info "actualizando perfil GSM ${PROFILE_NAME} (${profile_ref})"
  else
    info "creando perfil GSM ${PROFILE_NAME}"
    nmcli connection add type gsm ifname '*' con-name "$PROFILE_NAME" apn "$APN" >/dev/null
    profile_ref="$(profile_uuid)"
  fi

  nmcli connection modify uuid "$profile_ref" \
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
    connection.permissions "user:${TARGET_USER}" \
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
    show_profile_status
  fi
  if command -v mmcli >/dev/null 2>&1; then
    show_modem_summary
  fi
}

action_connect() {
  local modem_id
  require_command nmcli
  profile_exists || die "falta el perfil '${PROFILE_NAME}'; ejecuta primero --apply"
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem"
  if mmcli -m "$modem_id" 2>&1 | grep -qi 'sim-missing'; then
    die "la SIM no está insertada o no es detectada por la EM7455"
  fi
  nmcli radio wwan on
  info "conectando ${PROFILE_NAME}; nmcli puede solicitar el PIN de la SIM"
  nmcli --ask connection up id "$PROFILE_NAME"
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
  local modem_id
  require_command mmcli
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem"
  if mmcli -m "$modem_id" 2>&1 | grep -qi 'sim-missing'; then
    die "la SIM no está insertada o no es detectada por la EM7455"
  fi
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
