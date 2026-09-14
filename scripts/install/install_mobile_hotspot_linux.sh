#!/usr/bin/env bash
# v1.0.0 - Prepara un AP Wi-Fi oculto administrado por NetworkManager.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly PROFILE_NAME="Rafex Mobile Hotspot"
readonly SSID="internet-movil"
readonly CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/mobile-hotspot.conf"
readonly PROFILE_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/mobile-hotspot/profile.env"
readonly PACKAGES=(iw rfkill)
TMP_FILES=()

cleanup() {
  local file
  for file in "${TMP_FILES[@]-}"; do
    rm -f -- "$file"
  done
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso: install_mobile_hotspot_linux.sh [--check|--plan|--apply|--status]

Prepara un perfil NetworkManager para un AP Wi-Fi oculto llamado
"internet-movil". La clave se lee desde ~/.config/rafex/mobile-hotspot.conf;
este instalador no inicia el AP.
EOF
}

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"
}

package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null \
    | awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

check_dependencies() {
  local package_name candidate missing=0
  require_command nmcli
  require_command dpkg-query
  require_command apt-cache
  require_command install
  require_command mktemp
  require_command mv
  require_command chmod
  require_command mkdir
  require_command awk
  require_command grep
  require_command sed
  require_command date
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    ok 'NetworkManager activo'
  else
    warn 'NetworkManager no está activo'
    missing=1
  fi
  if systemctl is-active --quiet ModemManager 2>/dev/null; then
    ok 'ModemManager activo'
  else
    warn 'ModemManager no está activo; el AP requiere una conexión WWAN activa'
  fi
  for package_name in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package_name")"
    if package_installed "$package_name"; then
      ok "$package_name instalado"
    else
      warn "$package_name no está instalado"
      missing=1
    fi
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "$package_name no tiene candidato APT"
      missing=1
    fi
  done
  if (( missing != 0 )); then
    return 1
  fi
}

wifi_interface() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
    | awk -F: '$2 == "wifi" && $1 !~ /^p2p-/ { print $1 }' \
    | awk 'NF { print; count++ } END { if (count != 1) exit 1 }'
}

has_ap_capability() {
  command -v iw >/dev/null 2>&1 || return 1
  iw list 2>/dev/null \
    | awk '
      /Supported interface modes:/ { in_modes=1; next }
      in_modes && /^Band / { exit }
      in_modes && /^[[:space:]]*\*[[:space:]]+AP([[:space:]]|$)/ { found=1 }
      END { exit(found ? 0 : 1) }
    '
}

read_psk() {
  local line value=''
  [[ -f "$CONFIG_FILE" ]] || return 1
  [[ ! -L "$CONFIG_FILE" ]] || die "la clave no puede ser un enlace simbólico: $CONFIG_FILE"
  [[ "$(stat -c '%u' "$CONFIG_FILE" 2>/dev/null || printf -1)" == "$EUID" ]] \
    || die "la clave debe pertenecer al usuario actual: $CONFIG_FILE"
  [[ "$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || printf 600)" == 600 ]] \
    || die "la clave debe tener permisos 0600: $CONFIG_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      HOTSPOT_PSK=*) value="${line#HOTSPOT_PSK=}" ;;
    esac
  done < "$CONFIG_FILE"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  [[ "$value" =~ ^[\ -~]{8,63}$ ]] || return 1
  printf '%s' "$value"
}

profile_uuid() {
  if [[ -f "$PROFILE_STATE" ]]; then
    sed -n 's/^PROFILE_UUID=//p' "$PROFILE_STATE" | head -n 1
  fi
}

profile_exists() {
  local uuid
  uuid="$(profile_uuid)"
  if [[ -n "$uuid" ]]; then
    nmcli connection show uuid "$uuid" >/dev/null 2>&1 && return 0
  fi
  nmcli connection show id "$PROFILE_NAME" >/dev/null 2>&1
}

write_profile_state() {
  local uuid="$1" state_dir tmp
  state_dir="$(dirname "$PROFILE_STATE")"
  mkdir -p -- "$state_dir"
  chmod 700 -- "$(dirname "$state_dir")" "$state_dir"
  tmp="$(mktemp "${PROFILE_STATE}.XXXXXX")"
  TMP_FILES+=("$tmp")
  printf 'PROFILE_UUID=%s\n' "$uuid" > "$tmp"
  chmod 600 -- "$tmp"
  mv -f -- "$tmp" "$PROFILE_STATE"
}

validate_runtime() {
  local iface
  iface="$(wifi_interface)" || die 'se requiere exactamente una interfaz Wi-Fi física administrada por NetworkManager'
  ok "interfaz Wi-Fi detectada: $iface"
  if has_ap_capability; then
    ok 'la tarjeta Wi-Fi declara soporte para modo AP'
  else
    die 'la tarjeta Wi-Fi no declara soporte AP o iw no puede leer sus capacidades'
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    if read_psk >/dev/null; then
      ok 'clave WPA2 configurada en archivo local 0600'
    else
      die "HOTSPOT_PSK debe contener 8-63 caracteres ASCII en $CONFIG_FILE"
    fi
  else
    warn "falta la clave local: $CONFIG_FILE"
  fi
}

show_status() {
  local uuid active iface
  printf '═══ Rafex Mobile Hotspot ═══\n'
  printf 'SSID: %s (oculto)\n' "$SSID"
  printf 'Perfil: %s\n' "$PROFILE_NAME"
  uuid="$(profile_uuid)"
  if [[ -n "$uuid" ]] && nmcli connection show uuid "$uuid" >/dev/null 2>&1; then
    ok 'perfil administrado presente'
    iface="$(nmcli -g 802-11-wireless.mode connection show uuid "$uuid" 2>/dev/null || true)"
    printf 'Modo: %s\n' "${iface:-N/D}"
    active="$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null \
      | awk -F: -v uuid="$uuid" '$1 == uuid { print $2; exit }')"
    if [[ -n "$active" ]]; then
      ok "AP activo en $active"
    else
      info 'AP inactivo'
    fi
  else
    warn 'perfil administrado ausente'
  fi
  if [[ -f "$CONFIG_FILE" ]] && read_psk >/dev/null 2>&1; then
    ok 'clave local válida (no se muestra)'
  else
    warn 'clave local no configurada o inválida'
  fi
}

plan() {
  printf '═══ Plan Mobile Hotspot ═══\n'
  printf 'SSID oculto: %s\n' "$SSID"
  printf 'Perfil NetworkManager: %s\n' "$PROFILE_NAME"
  printf 'Modo IPv4: shared (DHCP/NAT administrado por NetworkManager)\n'
  printf 'Dependencias opcionales a instalar: %s\n' "${PACKAGES[*]}"
  info 'no se iniciará el AP, no se tocará WWAN y no se modificará firewall'
  info 'la activación diaria usará nmcli como usuario normal'
  check_dependencies || true
  validate_runtime || true
}

create_profile() {
  local iface="$1" psk="$2" uuid="${3:-}" keyfile loaded_uuid
  if [[ -z "$uuid" ]]; then
    uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  [[ "$uuid" =~ ^[0-9a-f-]{36}$ ]] || die 'no se pudo generar un UUID de NetworkManager'
  keyfile="$(mktemp)"
  TMP_FILES+=("$keyfile")
  chmod 600 -- "$keyfile"
  cat > "$keyfile" <<EOF
[connection]
id=$PROFILE_NAME
uuid=$uuid
type=wifi
interface-name=$iface
autoconnect=false
  permissions=user:$USER;
stable-id=rafex-mobile-hotspot-v1

[wifi]
mode=ap
ssid=$SSID
hidden=true
ap-isolation=true

[wifi-security]
key-mgmt=wpa-psk
proto=rsn
psk=$psk
psk-flags=0

[ipv4]
method=shared
address1=10.42.78.1/24

[ipv6]
method=disabled
EOF
  nmcli connection load "$keyfile" >/dev/null \
    || die 'NetworkManager no permitió cargar el perfil como usuario normal; revisa Polkit'
  loaded_uuid="$(nmcli -g connection.uuid connection show id "$PROFILE_NAME" 2>/dev/null | head -n 1)"
  [[ "$loaded_uuid" == "$uuid" ]] || die 'NetworkManager no devolvió el UUID esperado'
  write_profile_state "$uuid"
}

apply_profile() {
  local iface psk existing_uuid existing_iface existing_mode existing_stable
  require_command sudo
  check_dependencies || {
    info 'instalando dependencias faltantes mediante APT: iw rfkill'
    sudo apt-get update
    sudo apt-get install -y "${PACKAGES[@]}"
  }
  require_command iw
  require_command rfkill
  validate_runtime
  psk="$(read_psk || true)"
  [[ -n "$psk" ]] || die "crea $CONFIG_FILE con HOTSPOT_PSK=... y permisos 0600; no se creó ningún perfil"
  iface="$(wifi_interface)" || die 'se requiere exactamente una interfaz Wi-Fi'
  if profile_exists; then
    existing_uuid="$(profile_uuid)"
    [[ -n "$existing_uuid" ]] || existing_uuid="$(nmcli -g connection.uuid connection show id "$PROFILE_NAME")"
    existing_iface="$(nmcli -g connection.interface-name connection show uuid "$existing_uuid" 2>/dev/null || true)"
    existing_mode="$(nmcli -g 802-11-wireless.mode connection show uuid "$existing_uuid" 2>/dev/null || true)"
    existing_stable="$(nmcli -g connection.stable-id connection show uuid "$existing_uuid" 2>/dev/null || true)"
    [[ "$existing_iface" == "$iface" && "$existing_mode" == ap \
      && "$existing_stable" == rafex-mobile-hotspot-v1 ]] \
      || die 'existe un perfil con el mismo nombre pero no coincide con el AP administrado'
    create_profile "$iface" "$psk" "$existing_uuid"
    write_profile_state "$existing_uuid"
    info 'perfil administrado ya existe; no se duplicará'
  else
    create_profile "$iface" "$psk"
  fi
  ok 'perfil NetworkManager preparado; permanece inactivo hasta usar mobile-hotspot --start'
}

check() {
  check_dependencies
  require_command iw
  require_command rfkill
  validate_runtime
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción no reconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux_debian
  case "$ACTION" in
    check) check ;;
    plan) plan ;;
    apply) apply_profile ;;
    status) show_status ;;
  esac
}

main "$@"
