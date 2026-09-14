#!/usr/bin/env bash
# v1.0.0 - Activa un AP Rafex oculto y prioriza temporalmente la ruta WWAN.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="status"
readonly PROFILE_NAME="Rafex Mobile Hotspot"
readonly SSID="internet-movil"
readonly PROFILE_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/mobile-hotspot/profile.env"
readonly SESSION_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/mobile-hotspot/session.env"
readonly LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/rafex-mobile-hotspot.lock"
TMP_FILES=()
LOCK_FD=9

cleanup() {
  local file
  for file in "${TMP_FILES[@]-}"; do
    rm -f -- "$file"
  done
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso: mobile_hotspot_linux.sh [--status|--start|--stop|--toggle|--remove]

Opera únicamente el perfil Rafex Mobile Hotspot de NetworkManager.
No usa sudo, no ejecuta comandos arbitrarios y no modifica el firewall.
EOF
}

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

require_command() { command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"; }

load_value() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 1
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

profile_uuid() { load_value "$PROFILE_STATE" PROFILE_UUID; }

require_user() {
  (( EUID != 0 )) || die 'este helper debe ejecutarse como usuario normal, no como root'
}

lock() {
  local lock_dir
  lock_dir="$(dirname "$LOCK_FILE")"
  mkdir -p -- "$lock_dir"
  chmod 700 -- "$lock_dir"
  eval "exec ${LOCK_FD}>\"$LOCK_FILE\""
  flock -n "$LOCK_FD" || die 'ya hay otra operación del AP en curso'
}

wifi_interface() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
    | awk -F: '$2 == "wifi" && $1 !~ /^p2p-/ { print $1 }' \
    | awk 'NF { print; count++ } END { if (count != 1) exit 1 }'
}

has_ap_capability() {
  iw list 2>/dev/null \
    | awk '
      /Supported interface modes:/ { in_modes=1; next }
      in_modes && /^Band / { exit }
      in_modes && /^[[:space:]]*\*[[:space:]]+AP([[:space:]]|$)/ { found=1 }
      END { exit(found ? 0 : 1) }
    '
}

rfkill_ok() {
  ! rfkill list wifi 2>/dev/null \
    | grep -Eqi 'Soft blocked: yes|Hard blocked: yes'
}

active_wwan() {
  nmcli -t -f UUID,TYPE,DEVICE connection show --active 2>/dev/null \
    | awk -F: '$2 == "gsm" || $2 == "cdma" { print; count++ } END { if (count != 1) exit 1 }'
}

default_route_device() {
  ip -4 route show default 2>/dev/null | awk 'NR == 1 { print $5; exit }'
}

write_session_state() {
  local hotspot_uuid="$1" wifi_uuid="$2" wifi_iface="$3" wwan_uuid="$4" wwan_iface="$5" \
    ipv4_metric="$6" ipv6_metric="$7" tmp state_dir
  state_dir="$(dirname "$SESSION_STATE")"
  mkdir -p -- "$state_dir"
  chmod 700 -- "$(dirname "$state_dir")" "$state_dir"
  tmp="$(mktemp "${SESSION_STATE}.XXXXXX")"
  TMP_FILES+=("$tmp")
  {
    printf 'HOTSPOT_UUID=%s\n' "$hotspot_uuid"
    printf 'WIFI_UUID=%s\n' "$wifi_uuid"
    printf 'WIFI_IFACE=%s\n' "$wifi_iface"
    printf 'WWAN_UUID=%s\n' "$wwan_uuid"
    printf 'WWAN_IFACE=%s\n' "$wwan_iface"
    printf 'WWAN_IPV4_METRIC=%s\n' "$ipv4_metric"
    printf 'WWAN_IPV6_METRIC=%s\n' "$ipv6_metric"
    if [[ -n "$wifi_uuid" ]]; then
      printf 'WIFI_WAS_ACTIVE=1\n'
    else
      printf 'WIFI_WAS_ACTIVE=0\n'
    fi
  } > "$tmp"
  chmod 600 -- "$tmp"
  mv -f -- "$tmp" "$SESSION_STATE"
}

restore_session() {
  local wifi_uuid wifi_iface wwan_uuid wwan_iface ipv4_metric ipv6_metric wifi_was_active restore_ok=1
  [[ -r "$SESSION_STATE" ]] || return 0
  wifi_uuid="$(load_value "$SESSION_STATE" WIFI_UUID || true)"
  wifi_iface="$(load_value "$SESSION_STATE" WIFI_IFACE || true)"
  wwan_uuid="$(load_value "$SESSION_STATE" WWAN_UUID || true)"
  wwan_iface="$(load_value "$SESSION_STATE" WWAN_IFACE || true)"
  ipv4_metric="$(load_value "$SESSION_STATE" WWAN_IPV4_METRIC || true)"
  ipv6_metric="$(load_value "$SESSION_STATE" WWAN_IPV6_METRIC || true)"
  wifi_was_active="$(load_value "$SESSION_STATE" WIFI_WAS_ACTIVE || true)"
  if [[ -n "$wwan_uuid" && -n "$ipv4_metric" && -n "$ipv6_metric" ]]; then
    if ! nmcli connection modify uuid "$wwan_uuid" \
      ipv4.route-metric "$ipv4_metric" ipv6.route-metric "$ipv6_metric" >/dev/null; then
      warn 'no se pudo restaurar la métrica original de WWAN'
      restore_ok=0
    fi
    if [[ -n "$wwan_iface" ]]; then
      nmcli device reapply "$wwan_iface" >/dev/null 2>&1 || true
    fi
  fi
  if [[ "$wifi_was_active" == 1 && -n "$wifi_uuid" ]]; then
    if ! nmcli connection up uuid "$wifi_uuid" ifname "$wifi_iface" >/dev/null; then
      warn 'no se pudo reconectar automáticamente la Wi-Fi anterior'
      restore_ok=0
    fi
  fi
  if (( restore_ok == 1 )); then
    rm -f -- "$SESSION_STATE"
    return 0
  fi
  warn "se conserva el estado de recuperación: $SESSION_STATE"
  return 1
}

session_active() {
  [[ -r "$SESSION_STATE" ]] || return 1
  local uuid
  uuid="$(load_value "$SESSION_STATE" HOTSPOT_UUID || true)"
  [[ -n "$uuid" ]] || return 1
  nmcli -t -f UUID connection show --active 2>/dev/null | grep -Fxq "$uuid"
}

show_status() {
  local uuid active mode route
  printf '═══ Rafex Mobile Hotspot ═══\n'
  printf 'SSID: %s (oculto)\n' "$SSID"
  printf 'Perfil: %s\n' "$PROFILE_NAME"
  uuid="$(profile_uuid || true)"
  if [[ -z "$uuid" ]] || ! nmcli connection show uuid "$uuid" >/dev/null 2>&1; then
    warn 'perfil ausente; ejecuta install-mobile-hotspot --apply'
    return 1
  fi
  ok 'perfil administrado presente'
  mode="$(nmcli -g 802-11-wireless.mode connection show uuid "$uuid" 2>/dev/null || true)"
  printf 'Modo: %s\n' "${mode:-N/D}"
  active="$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null \
    | awk -F: -v uuid="$uuid" '$1 == uuid { print $2; exit }')"
  if [[ -n "$active" ]]; then
    ok "AP activo en $active"
    route="$(default_route_device || true)"
    printf 'Ruta IPv4 por defecto: %s\n' "${route:-N/D}"
  else
    info 'AP inactivo'
  fi
}

start_hotspot() {
  local wifi_iface wwan_row wwan_uuid wwan_iface wifi_row wifi_uuid old_ipv4 old_ipv6 \
    hotspot_uuid route
  require_command nmcli
  require_command iw
  require_command rfkill
  require_command ip
  hotspot_uuid="$(profile_uuid || true)"
  [[ -n "$hotspot_uuid" ]] || die 'perfil ausente; ejecuta primero install-mobile-hotspot --apply'
  session_active && { ok 'AP ya estaba activo; no se duplicará'; return 0; }
  [[ ! -e "$SESSION_STATE" ]] || die 'hay un estado anterior incompleto; ejecuta --stop para restaurarlo'
  wifi_iface="$(wifi_interface)" || die 'se requiere exactamente una interfaz Wi-Fi física'
  has_ap_capability || die 'la tarjeta Wi-Fi no soporta modo AP'
  rfkill_ok || die 'la interfaz Wi-Fi está bloqueada por rfkill'
  wwan_row="$(active_wwan || true)"
  [[ -n "$wwan_row" ]] || die 'se requiere exactamente una conexión WWAN activa'
  IFS=: read -r wwan_uuid _ wwan_iface <<< "$wwan_row"
  [[ -n "$wwan_uuid" && -n "$wwan_iface" ]] || die 'no se pudo identificar la conexión WWAN activa'
  wifi_row="$(nmcli -t -f UUID,TYPE,DEVICE connection show --active 2>/dev/null \
    | awk -F: '$2 == "802-11-wireless" { print; exit }')"
  wifi_uuid=""
  if [[ -n "$wifi_row" ]]; then
    IFS=: read -r wifi_uuid _ _ <<< "$wifi_row"
  fi
  old_ipv4="$(nmcli -g ipv4.route-metric connection show uuid "$wwan_uuid")"
  old_ipv6="$(nmcli -g ipv6.route-metric connection show uuid "$wwan_uuid")"
  [[ -n "$old_ipv4" ]] || old_ipv4=-1
  [[ -n "$old_ipv6" ]] || old_ipv6=-1
  write_session_state "$hotspot_uuid" "$wifi_uuid" "$wifi_iface" "$wwan_uuid" "$wwan_iface" \
    "$old_ipv4" "$old_ipv6"
  if ! nmcli connection modify uuid "$wwan_uuid" ipv4.route-metric 25 ipv6.route-metric 25 \
    || ! nmcli device reapply "$wwan_iface" >/dev/null 2>&1; then
    restore_session
    die 'no se pudo priorizar WWAN; no se inició el AP'
  fi
  if [[ -n "$wifi_uuid" ]] && ! nmcli connection down uuid "$wifi_uuid" >/dev/null; then
    restore_session
    die 'no se pudo desconectar la Wi-Fi actual; no se inició el AP'
  fi
  route="$(default_route_device || true)"
  [[ "$route" == "$wwan_iface" ]] || {
    restore_session
    die 'la ruta por defecto no quedó en WWAN; no se inició el AP'
  }
  if ! nmcli connection up uuid "$hotspot_uuid" ifname "$wifi_iface" >/dev/null; then
    restore_session
    die 'NetworkManager no pudo activar el AP; se restauró el estado anterior'
  fi
  if ! session_active; then
    nmcli connection down uuid "$hotspot_uuid" >/dev/null 2>&1 || true
    restore_session
    die 'el AP no quedó activo; se restauró el estado anterior'
  fi
  ok 'AP activo: internet-movil (SSID oculto, WPA2)'
  warn 'la ruta móvil fue priorizada temporalmente; una sesión SSH por Wi-Fi puede cortarse'
}

stop_hotspot() {
  local uuid stop_ok=1
  uuid="$(profile_uuid || true)"
  if [[ -n "$uuid" ]] && nmcli -t -f UUID connection show --active 2>/dev/null | grep -Fxq "$uuid"; then
    if ! nmcli connection down uuid "$uuid" >/dev/null; then
      warn 'el AP no pudo desactivarse completamente'
      stop_ok=0
    fi
  fi
  if (( stop_ok == 1 )) && [[ -r "$SESSION_STATE" ]]; then
    if ! restore_session; then
      return 1
    fi
    ok 'métricas WWAN y Wi-Fi anterior restauradas'
  elif (( stop_ok == 0 )); then
    return 1
  else
    info 'no había estado temporal que restaurar'
  fi
}

remove_profile() {
  local uuid
  stop_hotspot
  uuid="$(profile_uuid || true)"
  if [[ -n "$uuid" ]] && nmcli connection show uuid "$uuid" >/dev/null 2>&1; then
    nmcli connection delete uuid "$uuid" >/dev/null \
      || die 'no se pudo eliminar el perfil administrado'
    rm -f -- "$PROFILE_STATE"
    ok 'perfil NetworkManager eliminado; la clave local se conservó'
  else
    info 'perfil ya estaba ausente'
  fi
}

parse_args() {
  while (($#)); do
    case "$1" in
      --status) ACTION=status ;;
      --start) ACTION=start ;;
      --stop) ACTION=stop ;;
      --toggle) ACTION=toggle ;;
      --remove) ACTION=remove ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción no reconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_user
  require_command nmcli
  require_command mkdir
  require_command chmod
  require_command mv
  require_command rm
  require_command sed
  require_command head
  require_command awk
  require_command grep
  require_command flock
  lock
  case "$ACTION" in
    status) show_status ;;
    start) start_hotspot ;;
    stop) stop_hotspot ;;
    toggle)
      if session_active; then stop_hotspot; else start_hotspot; fi
      ;;
    remove) remove_profile ;;
  esac
}

main "$@"
