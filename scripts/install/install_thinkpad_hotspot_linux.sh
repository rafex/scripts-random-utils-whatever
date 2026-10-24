#!/usr/bin/env bash
# v1.0.0 - Prepara el perfil Wi-Fi THINKPAD_RAFEX en NetworkManager.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly PROFILE_NAME="ThinkPad Rafex Hotspot"
readonly SSID="THINKPAD_RAFEX"
readonly CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/thinkpad-hotspot.conf"
readonly PROFILE_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/thinkpad-hotspot/profile.env"
readonly PACKAGES=(iw rfkill)
TMP_FILES=()

cleanup() {
  local file
  for file in "${TMP_FILES[@]-}"; do rm -f -- "$file"; done
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso: install_thinkpad_hotspot_linux.sh [--check|--plan|--apply|--set-key|--status]

Prepara un perfil NetworkManager para el SSID visible THINKPAD_RAFEX.
La clave se guarda en ~/.config/rafex/thinkpad-hotspot.conf con permisos 0600.
El instalador no inicia el AP.
EOF
}

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"; }

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
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
  for cmd in nmcli dpkg-query apt-cache install mktemp mv chmod mkdir awk grep sed date stat; do
    require_command "$cmd"
  done
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    ok 'NetworkManager activo'
  else
    warn 'NetworkManager no está activo'
    missing=1
  fi
  for package_name in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package_name")"
    if package_installed "$package_name"; then ok "$package_name instalado"; else warn "$package_name no está instalado"; missing=1; fi
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then warn "$package_name no tiene candidato APT"; missing=1; fi
  done
  (( missing == 0 ))
}

wifi_interface() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
    | awk -F: '$2 == "wifi" && $1 !~ /^p2p-/ { print $1 }' \
    | awk 'NF { print; count++ } END { if (count != 1) exit 1 }'
}

has_ap_capability() {
  iw list 2>/dev/null | awk '
    /Supported interface modes:/ { in_modes=1; next }
    in_modes && /^Band / { exit }
    in_modes && /^[[:space:]]*\*[[:space:]]+AP([[:space:]]|$)/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

read_psk() {
  local line value=''
  [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || return 1
  [[ "$(stat -c '%u' "$CONFIG_FILE" 2>/dev/null || printf -1)" == "$EUID" ]] \
    || die "la clave debe pertenecer al usuario actual: $CONFIG_FILE"
  [[ "$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || printf '')" == 600 ]] \
    || die "la clave debe tener permisos 0600: $CONFIG_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in HOTSPOT_PSK=*) value="${line#HOTSPOT_PSK=}" ;; esac
  done < "$CONFIG_FILE"
  value="${value#\'}"; value="${value%\'}"; value="${value#\"}"; value="${value%\"}"
  LC_ALL=C awk 'length($0) >= 8 && length($0) <= 63 && $0 !~ /[^ -~]/ { valid=1 } END { exit(valid ? 0 : 1) }' <<< "$value" \
    || return 1
  printf '%s' "$value"
}

profile_uuid() {
  [[ -f "$PROFILE_STATE" ]] && sed -n 's/^PROFILE_UUID=//p' "$PROFILE_STATE" | head -n 1
}

profile_exists() {
  local uuid
  uuid="$(profile_uuid || true)"
  [[ -n "$uuid" ]] && nmcli connection show uuid "$uuid" >/dev/null 2>&1 && return 0
  nmcli connection show id "$PROFILE_NAME" >/dev/null 2>&1
}

write_profile_state() {
  local uuid="$1" state_dir tmp
  state_dir="$(dirname "$PROFILE_STATE")"
  mkdir -p -- "$state_dir"
  chmod 700 -- "$(dirname "$state_dir")" "$state_dir"
  tmp="$(mktemp "${PROFILE_STATE}.XXXXXX")"; TMP_FILES+=("$tmp")
  printf 'PROFILE_UUID=%s\n' "$uuid" > "$tmp"
  chmod 600 -- "$tmp"
  mv -f -- "$tmp" "$PROFILE_STATE"
}

set_key() {
  local first second config_dir tmp answer
  require_command install
  if [[ -e "$CONFIG_FILE" || -L "$CONFIG_FILE" ]]; then
    [[ ! -L "$CONFIG_FILE" ]] || die "no se sobrescribirá un enlace simbólico: $CONFIG_FILE"
    read -r -p "Ya existe $CONFIG_FILE. ¿Reemplazar la clave? [s/N] " answer
    [[ "$answer" == [sS] || "$answer" == [sS][iI] ]] || die 'operación cancelada'
  fi
  IFS= read -r -s -p 'Clave WPA2 (8-63 caracteres ASCII): ' first </dev/tty || die 'se requiere una terminal'
  printf '\n' >/dev/tty
  IFS= read -r -s -p 'Confirma la clave WPA2: ' second </dev/tty || die 'se requiere una terminal'
  printf '\n' >/dev/tty
  [[ "$first" == "$second" ]] || die 'las claves no coinciden'
  LC_ALL=C awk 'length($0) >= 8 && length($0) <= 63 && $0 !~ /[^ -~]/ { valid=1 } END { exit(valid ? 0 : 1) }' <<< "$first" \
    || die 'la clave debe contener 8-63 caracteres ASCII imprimibles'
  config_dir="$(dirname "$CONFIG_FILE")"
  install -d -m 700 -- "$config_dir"
  tmp="$(mktemp "${CONFIG_FILE}.XXXXXX")"; TMP_FILES+=("$tmp")
  printf 'HOTSPOT_PSK=%s\n' "$first" > "$tmp"
  chmod 600 -- "$tmp"
  mv -f -- "$tmp" "$CONFIG_FILE"
  ok "clave guardada localmente en $CONFIG_FILE (no se muestra)"
}

validate_runtime() {
  local iface
  iface="$(wifi_interface)" || die 'se requiere exactamente una interfaz Wi-Fi administrada por NetworkManager'
  ok "interfaz Wi-Fi detectada: $iface"
  has_ap_capability || die 'la tarjeta Wi-Fi no declara soporte AP o iw no puede leer sus capacidades'
  ok 'la tarjeta Wi-Fi declara soporte para modo AP'
  if [[ -f "$CONFIG_FILE" ]]; then
    read_psk >/dev/null || die "HOTSPOT_PSK inválida en $CONFIG_FILE"
    ok 'clave WPA2 configurada localmente (no se muestra)'
  else
    warn 'falta la clave local; ejecuta just install-thinkpad-hotspot --set-key'
  fi
}

show_status() {
  local uuid active mode
  printf '═══ ThinkPad Rafex Hotspot ═══\nSSID: %s (visible)\nPerfil: %s\n' "$SSID" "$PROFILE_NAME"
  uuid="$(profile_uuid || true)"
  if [[ -n "$uuid" ]] && nmcli connection show uuid "$uuid" >/dev/null 2>&1; then
    ok 'perfil administrado presente'
    mode="$(nmcli -g 802-11-wireless.mode connection show uuid "$uuid" 2>/dev/null || true)"
    printf 'Modo: %s\n' "${mode:-N/D}"
    active="$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null | awk -F: -v u="$uuid" '$1 == u { print $2; exit }')"
    [[ -n "$active" ]] && ok "AP activo en $active" || info 'AP inactivo'
  else
    warn 'perfil administrado ausente'
  fi
  if [[ -f "$CONFIG_FILE" ]] && read_psk >/dev/null 2>&1; then ok 'clave local válida (no se muestra)'; else warn 'clave local no configurada o inválida'; fi
}

create_profile() {
  local iface="$1" psk="$2" uuid="${3:-}" keyfile loaded_uuid
  [[ -n "$uuid" ]] || uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
  [[ "$uuid" =~ ^[0-9a-f-]{36}$ ]] || die 'no se pudo generar un UUID de NetworkManager'
  keyfile="$(mktemp)"; TMP_FILES+=("$keyfile"); chmod 600 -- "$keyfile"
  cat > "$keyfile" <<EOF
[connection]
id=$PROFILE_NAME
uuid=$uuid
type=wifi
interface-name=$iface
autoconnect=false
permissions=user:$USER;
stable-id=rafex-thinkpad-hotspot-v1

[wifi]
mode=ap
ssid=$SSID
hidden=false
ap-isolation=true

[wifi-security]
key-mgmt=wpa-psk
proto=rsn
psk=$psk
psk-flags=0

[ipv4]
method=shared
address1=10.42.79.1/24

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
  check_dependencies || { info 'instalando iw y rfkill mediante APT'; sudo apt-get update; sudo apt-get install -y "${PACKAGES[@]}"; }
  require_command iw; require_command rfkill
  validate_runtime
  psk="$(read_psk || true)"
  [[ -n "$psk" ]] || die 'crea una clave con: just install-thinkpad-hotspot --set-key'
  iface="$(wifi_interface)" || die 'se requiere exactamente una interfaz Wi-Fi'
  if profile_exists; then
    existing_uuid="$(profile_uuid)"
    [[ -n "$existing_uuid" ]] || existing_uuid="$(nmcli -g connection.uuid connection show id "$PROFILE_NAME")"
    existing_iface="$(nmcli -g connection.interface-name connection show uuid "$existing_uuid" 2>/dev/null || true)"
    existing_mode="$(nmcli -g 802-11-wireless.mode connection show uuid "$existing_uuid" 2>/dev/null || true)"
    existing_stable="$(nmcli -g connection.stable-id connection show uuid "$existing_uuid" 2>/dev/null || true)"
    [[ "$existing_iface" == "$iface" && "$existing_mode" == ap && "$existing_stable" == rafex-thinkpad-hotspot-v1 ]] \
      || die 'existe un perfil con el mismo nombre que no coincide con este hotspot administrado'
    create_profile "$iface" "$psk" "$existing_uuid"
    info 'perfil administrado actualizado; no se duplicará'
  else
    create_profile "$iface" "$psk"
  fi
  ok 'perfil THINKPAD_RAFEX preparado y visible; permanece inactivo hasta iniciar el AP'
}

plan() {
  printf '═══ Plan ThinkPad Rafex Hotspot ═══\nSSID visible: %s\nPerfil NetworkManager: %s\nModo IPv4: shared (DHCP/NAT)\nDependencias: %s\n' "$SSID" "$PROFILE_NAME" "${PACKAGES[*]}"
  info 'no se iniciará el AP ni se modificará la conexión WWAN'
  check_dependencies || true
  validate_runtime || true
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --set-key) ACTION=set-key ;;
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
    check) check_dependencies; require_command iw; require_command rfkill; validate_runtime ;;
    plan) plan ;;
    apply) apply_profile ;;
    set-key) set_key ;;
    status) show_status ;;
  esac
}

main "$@"
