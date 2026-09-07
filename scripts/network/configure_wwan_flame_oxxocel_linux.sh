#!/usr/bin/env bash
# shellcheck shell=bash
# Configura el módem expuesto por un Firefox OS Flame conectado por USB para
# datos OXXO Cel y consulta SMS. Hermano de configure_wwan_oxxocel_linux.sh
# (esa administra la EM7455 interna); esta administra el módem del Flame,
# que ModemManager también reconoce por QMI al conectarlo por USB.
set -Eeuo pipefail

readonly APN="internet.mvne1.com"
readonly PROFILE_NAME="${FLAME_OXXOCEL_PROFILE:-Flame Oxxo Cel}"
readonly ROUTE_METRIC=700
readonly FLAME_USB_ID="05c6:9025"
readonly RAWIP_UDEV_RULE="/etc/udev/rules.d/79-flame-oxxocel-qmi-rawip.rules"
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
  --apply       Instala dependencias y crea/actualiza el perfil Flame Oxxo Cel.
  --status      Muestra el estado actual sin modificar ni revelar IMEI.
  --connect     Activa WWAN y conecta por UUID como usuario normal; requiere TTY.
  --disconnect  Desconecta el perfil Flame Oxxo Cel.
  --sms-list    Lista los SMS expuestos por ModemManager.
  -h, --help    Muestra esta ayuda.

El perfil usa el APN ${APN} (el mismo SIM OXXO Cel que
configure_wwan_oxxocel_linux.sh, pero insertado en el Firefox OS Flame en
vez de la EM7455 interna), no guarda PIN, usuario ni contraseña, y se
conecta automáticamente cuando el Flame está conectado por USB y la SIM y
la red están disponibles. Para cambiar el nombre del perfil usa:
  FLAME_OXXOCEL_PROFILE='Otro nombre' $0 --apply
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
  local listing match
  listing="$(mmcli -L 2>/dev/null || true)"
  # Simétrico a configure_wwan_oxxocel_linux.sh: con dos módems WWAN
  # presentes, el orden de /org/.../Modem/<N> no es estable entre
  # reinicios de ModemManager. Aquí se busca explícitamente el módem que
  # NO sea la EM7455 Sierra Wireless (esa la administra el otro script),
  # para no competir por el mismo dispositivo ni depender del orden en
  # que ModemManager los enumere.
  match="$(grep -vi 'Sierra Wireless' <<< "$listing" | grep -E '/Modem/[0-9]+' | sed -n '1p')"
  [[ -n "$match" ]] || match="$(sed -n '1p' <<< "$listing")"
  sed -nE 's#.*(/org/freedesktop/ModemManager1/Modem/[0-9]+).*#\1#p' <<< "$match"
}

find_modem_id() {
  local modem_path
  modem_path="$(find_modem_path)"
  [[ -n "$modem_path" ]] || return 1
  basename "$modem_path"
}

current_net_iface() {
  local modem_id raw ports
  modem_id="$(find_modem_id)" || return 1
  raw="$(mmcli -m "$modem_id" 2>&1 || true)"
  ports="$(modem_field "$raw" "ports")"
  grep -oE '[A-Za-z0-9]+ \(net\)' <<< "$ports" | awk '{print $1}' | sed -n '1p'
}

# El módem del Flame (qmi_wwan genérico, sin plugin dedicado en
# ModemManager) arranca su interfaz de red en modo "ether" (raw_ip=N).
# En ese modo la sesión de datos se registra y sube por UUID sin error,
# pero NetworkManager nunca logra reservar una IP ("no hay direcciones
# disponibles, tiempo de espera, etc.") porque el driver está enviando
# tramas Ethernet emuladas en vez de paquetes IP crudos, que es lo que
# entrega el firmware por QMI. Confirmado en vivo el 2026-09-06:
# cambiar manualmente a raw_ip=Y resolvió la conexión de inmediato.
raw_ip_rule_content() {
  local vendor="${FLAME_USB_ID%:*}" product="${FLAME_USB_ID#*:}"
  cat <<EOF
SUBSYSTEM=="net", ATTRS{idVendor}=="$vendor", ATTRS{idProduct}=="$product", RUN+="/bin/sh -c 'echo Y > /sys/class/net/%k/qmi/raw_ip'"
EOF
}

raw_ip_path_for() {
  printf '/sys/class/net/%s/qmi/raw_ip\n' "$1"
}

show_raw_ip_status() {
  local iface path value
  iface="$(current_net_iface || true)"
  [[ -n "$iface" ]] || { warn "no se pudo determinar la interfaz de red del módem del Flame"; return 0; }
  path="$(raw_ip_path_for "$iface")"
  if [[ ! -r "$path" ]]; then
    warn "$path no existe; el driver puede no ser qmi_wwan en este dispositivo"
    return 0
  fi
  value="$(cat "$path" 2>/dev/null || true)"
  printf '  raw_ip (%s): %s\n' "$iface" "$value"
  if [[ "$value" == "Y" ]]; then
    success "interfaz en modo raw_ip; la sesión de datos QMI debería poder obtener IP"
  else
    warn "interfaz en modo Ethernet emulado (raw_ip=N); NetworkManager fallará al reservar IP hasta corregirlo (usa --apply)"
  fi
  if [[ -L "$RAWIP_UDEV_RULE" || -f "$RAWIP_UDEV_RULE" ]]; then
    success "regla udev raw_ip instalada: $RAWIP_UDEV_RULE"
  else
    warn "falta la regla udev raw_ip persistente: $RAWIP_UDEV_RULE (usa --apply)"
  fi
}

ensure_raw_ip_udev_rule() {
  local desired current temp_file backup_path iface path value

  desired="$(raw_ip_rule_content)"
  if [[ -f "$RAWIP_UDEV_RULE" ]] && current="$(cat "$RAWIP_UDEV_RULE" 2>/dev/null)" && [[ "$current" == "$desired" ]]; then
    success "regla udev raw_ip ya estaba instalada: $RAWIP_UDEV_RULE"
  else
    if [[ -e "$RAWIP_UDEV_RULE" ]]; then
      backup_path="${RAWIP_UDEV_RULE}.bak.$(date +%Y%m%d_%H%M%S)"
      sudo cp -a -- "$RAWIP_UDEV_RULE" "$backup_path"
      info "respaldo de regla udev anterior: $backup_path"
    fi
    temp_file="$(mktemp)"
    printf '%s' "$desired" > "$temp_file"
    sudo install -D -m 0644 -- "$temp_file" "$RAWIP_UDEV_RULE"
    rm -f -- "$temp_file"
    success "regla udev raw_ip instalada: $RAWIP_UDEV_RULE"
  fi

  sudo udevadm control --reload-rules

  # Si el módem ya está conectado en modo Ethernet, aplicarlo de
  # inmediato en vez de esperar a que el Flame se desconecte y reconecte
  # físicamente: hace falta bajar la interfaz para poder escribir
  # raw_ip, y volver a subirla para que ModemManager/NetworkManager la
  # usen normalmente.
  iface="$(current_net_iface || true)"
  [[ -n "$iface" ]] || return 0
  path="$(raw_ip_path_for "$iface")"
  [[ -r "$path" ]] || return 0
  value="$(cat "$path" 2>/dev/null || true)"
  if [[ "$value" == "N" ]]; then
    info "aplicando raw_ip=Y de inmediato a $iface (sin esperar a reconectar el Flame)"
    sudo ip link set "$iface" down
    printf 'Y\n' | sudo tee "$path" >/dev/null
    sudo ip link set "$iface" up
    success "$iface actualizada a modo raw_ip"
  else
    success "$iface ya estaba en modo raw_ip"
  fi
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
    warn "módem deshabilitado o apagado; revisa que el Flame esté conectado por USB y con la pantalla desbloqueada"
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
          die "la SIM está ausente o no es detectada por el módem del Flame" ;;
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
      die "el módem permanece deshabilitado; revisa que el Flame siga conectado por USB, desbloqueado y con depuración USB activa"
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

  "${nmcli_cmd[@]}" -t -g NAME,UUID,TYPE connection show 2>/dev/null || true
}

nmcli_active_profile_rows() {
  local -a nmcli_cmd=(nmcli)
  if [[ "${1:-}" == root ]]; then
    nmcli_cmd=(sudo nmcli)
  fi

  "${nmcli_cmd[@]}" -t -g NAME,UUID,TYPE connection show --active 2>/dev/null || true
}

profile_uuid() {
  local uuid rows

  # Si hay más de un perfil con el mismo nombre, conservar primero el que
  # está conectado. Así --apply no puede elegir un duplicado inactivo y
  # desmontar accidentalmente el perfil de datos funcional.
  rows="$(nmcli_active_profile_rows "${1:-}")"
  uuid="$(awk -F: -v wanted="$PROFILE_NAME" \
    '$1 == wanted && $3 == "gsm" { print $2; exit }' <<< "$rows")"
  if [[ -n "$uuid" ]]; then
    printf '%s\n' "$uuid"
    return 0
  fi

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

deduplicate_profiles() {
  local keep_uuid="$1" scope="${2:-}" rows name uuid type
  local -a nmcli_cmd=(nmcli)
  [[ "$scope" == root ]] && nmcli_cmd=(sudo nmcli)
  rows="$(nmcli_profile_rows "$scope")"

  while IFS=: read -r name uuid type; do
    [[ "$name" == "$PROFILE_NAME" && "$type" == gsm ]] || continue
    [[ -n "$uuid" && "$uuid" != "$keep_uuid" ]] || continue
    if awk -F: -v wanted="$uuid" \
      '$1 == wanted && $2 == "gsm" { found = 1 } END { exit !found }' \
      <<< "$(nmcli_active_profile_rows "$scope")"; then
      warn "se conserva el duplicado activo ${uuid}; no se eliminará automáticamente"
      continue
    fi
    info "eliminando perfil Flame Oxxo Cel duplicado e inactivo (${uuid})"
    "${nmcli_cmd[@]}" connection delete uuid "$uuid" >/dev/null \
      || die "no se pudo eliminar el perfil duplicado ${uuid}"
  done <<< "$rows"
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
    && lsmod | awk '$1 == "qmi_wwan" { found = 1 } END { exit !found }'; then
    success "driver qmi_wwan cargado"
  else
    warn "driver qmi_wwan no aparece cargado"
  fi

  if compgen -G '/dev/cdc-wdm*' >/dev/null; then
    printf '  nodos QMI/MBIM: '
    compgen -G '/dev/cdc-wdm*' | paste -sd ' ' -
  else
    warn "no existe ningún nodo /dev/cdc-wdm*; conecta el Flame por USB"
  fi

  if command -v nmcli >/dev/null 2>&1; then
    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null \
      | awk '$2 == "gsm" || NR == 1'
    nmcli radio 2>/dev/null
  fi
}

show_modem_summary() {
  local modem_id raw
  require_command mmcli

  if ! modem_id="$(find_modem_id)"; then
    warn "ModemManager no detecta ningún módem del Flame; confirma que esté conectado por USB"
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
    success "perfil Flame Oxxo Cel activo: conexión de datos en curso"
  else
    info "perfil Flame Oxxo Cel no está activo; no hay conexión de datos mediante este perfil"
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
    show_raw_ip_status
  fi
  show_profile_status

  if ((missing_tools != 0 || ${#MISSING_PACKAGES[@]} != 0)); then
    return 1
  fi
  success "auditoría WWAN completada; SIM se valida por separado"
}

action_plan() {
  collect_missing_packages
  printf '%b\n' "${BOLD}═══ Plan WWAN Flame Oxxo Cel ═══${RESET}"
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
  info "[plan] instalar/actualizar $RAWIP_UDEV_RULE (raw_ip para el módem $FLAME_USB_ID)"
  info "[plan] crear o actualizar el perfil GSM ${PROFILE_NAME}"
  info "[plan] APN ${APN}, IPv4/IPv6 automático, métrica ${ROUTE_METRIC}"
  info "[plan] autoconnect habilitado, métrica ${ROUTE_METRIC} y roaming desactivado"
  info "[plan] no ejecutar una conexión directa; dejar autoconexión sin almacenar PIN o credenciales"
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
    connection.autoconnect yes \
    connection.autoconnect-priority -100 \
    connection.permissions '' \
    connection.metered yes \
    ipv4.method auto \
    ipv4.never-default no \
    ipv4.route-metric "$ROUTE_METRIC" \
    ipv6.method auto \
    ipv6.never-default no \
    ipv6.route-metric "$ROUTE_METRIC"
  deduplicate_profiles "$profile_ref" "$profile_scope"
  profile_count_value="$(profile_count "$profile_scope")"
  if ((profile_count_value > 1)); then
    warn "quedan ${profile_count_value} perfiles GSM llamados '${PROFILE_NAME}'; revisa los duplicados activos"
  fi
  success "perfil ${PROFILE_NAME} configurado; autoconexión habilitada y Wi-Fi preferida"
}

action_apply() {
  require_command sudo
  validate_sudo
  ensure_packages
  if ! sudo systemctl enable --now NetworkManager.service ModemManager.service; then
    die "no se pudieron activar NetworkManager y ModemManager; revisa systemctl status NetworkManager ModemManager"
  fi
  ensure_raw_ip_udev_rule
  configure_profile
  if ! find_modem_id >/dev/null 2>&1; then
    warn "perfil creado, pero ModemManager todavía no detecta el módem del Flame; confirma que esté conectado por USB"
  fi
  if ! compgen -G '/dev/cdc-wdm*' >/dev/null; then
    warn "no se detecta /dev/cdc-wdm*; conecta el Flame por USB y revisa el estado del módem"
  fi
  info "NetworkManager intentará conectar WWAN automáticamente; usa --connect para forzar la conexión"
}

action_status() {
  printf '%b\n' "${BOLD}═══ Estado WWAN Flame Oxxo Cel ═══${RESET}"
  if command -v nmcli >/dev/null 2>&1; then
    show_driver_state
    show_raw_ip_status
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
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem del Flame; confirma que esté conectado por USB"
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
  modem_id="$(find_modem_id)" || die "ModemManager no detecta ningún módem del Flame"
  raw="$(mmcli -m "$modem_id" 2>&1 || true)"
  sim_status="$(modem_sim_status "$raw")"
  case "$sim_status" in
    missing) die "la SIM está ausente o no es detectada por el módem del Flame" ;;
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
