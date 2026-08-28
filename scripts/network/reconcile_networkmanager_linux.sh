#!/usr/bin/env bash
# shellcheck shell=bash
# Reconciliación segura de ifupdown/dhcpcd hacia NetworkManager.
set -Eeuo pipefail
umask 077

ACTION="check"
ALLOW_SSH_DISCONNECT=0
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="/var/backups/rafex-networkmanager"
INTERFACES_FILE="/etc/network/interfaces"
INTERFACES_DIR="/etc/network/interfaces.d"
NM_DROPIN="/etc/NetworkManager/conf.d/90-rafex-managed.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  reconcile_networkmanager_linux.sh --check
  reconcile_networkmanager_linux.sh --plan
  reconcile_networkmanager_linux.sh --apply

Opciones:
  --check                    Diagnosticar sin modificar el sistema (default)
  --plan                     Mostrar cambios previstos sin modificar
  --dry-run                  Alias de --plan
  --apply                    Migrar ifupdown/dhcpcd a NetworkManager
  --allow-ssh-disconnect     Permitir perder la conexión SSH durante la migración
  -h, --help                 Mostrar esta ayuda

La etapa --apply solicita la contraseña únicamente mediante sudo -v.
Después de migrar, recrea las redes Wi-Fi manualmente con nmcli --ask.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --allow-ssh-disconnect) ALLOW_SSH_DISCONNECT=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script requiere Linux"
  command -v nmcli >/dev/null 2>&1 || warn "nmcli no está instalado; se revisará tras instalar NetworkManager"
}

interfaces() {
  local path name
  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    name="${path##*/}"
    [[ "$name" == lo ]] || printf '%s\n' "$name"
  done
}

non_loopback_ifupdown() {
  awk '
    /^[[:space:]]*(auto|allow-hotplug)[[:space:]]+/ {
      for (i = 2; i <= NF; i++) if ($i != "lo") found = 1
    }
    /^[[:space:]]*iface[[:space:]]+/ && $2 != "lo" { found = 1 }
    /^[[:space:]]*mapping[[:space:]]+/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

show_nm_status() {
  if ! command -v nmcli >/dev/null 2>&1; then
    warn "NetworkManager/nmcli no disponible"
    return 0
  fi
  nmcli general status 2>&1 || true
  nmcli device status 2>&1 || true
}

check_ifupdown() {
  local file
  if [[ -r "$INTERFACES_FILE" ]]; then
    if non_loopback_ifupdown "$INTERFACES_FILE"; then
      warn "$INTERFACES_FILE contiene interfaces no-loopback gestionadas por ifupdown"
    else
      ok "$INTERFACES_FILE no contiene interfaces no-loopback"
    fi
  else
    warn "no se puede leer $INTERFACES_FILE sin privilegios"
  fi

  if [[ -d "$INTERFACES_DIR" ]]; then
    while IFS= read -r -d '' file; do
      if [[ -r "$file" ]] && non_loopback_ifupdown "$file"; then
        warn "$file contiene configuración no-loopback"
      fi
    done < <(find "$INTERFACES_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
  fi
}

check_policy() {
  local matches
  matches="$(grep -R -n -E 'unmanaged-devices|NM_UNMANAGED|managed[[:space:]]*=' \
    /etc/NetworkManager /etc/udev/rules.d 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
    warn "existen políticas que pueden mantener dispositivos fuera de NetworkManager"
  else
    ok "no se detectaron políticas explícitas de interfaces unmanaged"
  fi
}

check_ifup_units() {
  local iface
  while IFS= read -r iface; do
    if systemctl is-active --quiet "ifup@${iface}.service" 2>/dev/null; then
      warn "ifup@${iface}.service está activo"
    fi
  done < <(interfaces)
}

check_mode() {
  echo '═══ NetworkManager: auditoría de control de interfaces ═══'
  printf 'NetworkManager.service: '
  systemctl is-active NetworkManager 2>/dev/null || true
  printf 'NetworkManager habilitado: '
  systemctl is-enabled NetworkManager 2>/dev/null || true
  check_ifupdown
  check_policy
  check_ifup_units
  echo
  show_nm_status
  echo
  info "La aplicación conservará respaldos en $BACKUP_ROOT"
  info "Las contraseñas Wi-Fi no se copian; se recrean con nmcli --ask"
}

plan_mode() {
  echo '═══ Plan NetworkManager ═══'
  info "[plan] sudo -v"
  info "[plan] instalar network-manager y wpasupplicant si faltan"
  info "[plan] respaldar $INTERFACES_FILE y archivos no-loopback de $INTERFACES_DIR"
  info "[plan] dejar $INTERFACES_FILE con solo loopback"
  info "[plan] escribir $NM_DROPIN con ifupdown managed=true"
  info "[plan] detener ifup@*.service activos"
  info "[plan] habilitar y reiniciar NetworkManager"
  info "[plan] marcar interfaces no-loopback como managed=yes"
  info "[plan] verificar que ninguna interfaz permanezca unmanaged"
  warn "la conexión actual puede perderse; ejecuta --apply desde la consola local"
}

require_apply_safety() {
  if [[ -n "${SSH_CONNECTION:-}" && "$ALLOW_SSH_DISCONNECT" -ne 1 ]]; then
    die "--apply se ejecutó por SSH; usa la consola local o confirma explícitamente con --allow-ssh-disconnect"
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
  sudo -v
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
}

backup_path() {
  local source="$1"
  local name destination suffix=0
  [[ -e "$source" || -L "$source" ]] || return 0
  name="$(basename "$source").bak.$STAMP"
  sudo install -d -m 700 "$BACKUP_ROOT"
  destination="$BACKUP_ROOT/$name"
  while sudo test -e "$destination" || sudo test -L "$destination"; do
    suffix=$((suffix + 1))
    destination="$BACKUP_ROOT/$name.$suffix"
  done
  sudo cp -a -- "$source" "$destination"
  info "respaldo creado: $destination"
}

move_to_backup() {
  local source="$1"
  local name destination suffix=0
  [[ -e "$source" || -L "$source" ]] || return 0
  name="interfaces.d.$(basename "$source").$STAMP"
  sudo install -d -m 700 "$BACKUP_ROOT"
  destination="$BACKUP_ROOT/$name"
  while sudo test -e "$destination" || sudo test -L "$destination"; do
    suffix=$((suffix + 1))
    destination="$BACKUP_ROOT/$name.$suffix"
  done
  sudo mv -- "$source" "$destination"
  info "configuración ifupdown apartada: $source (respaldo: $destination)"
}

install_nm_dropin() {
  local temporary
  temporary="$(mktemp)"
  cat > "$temporary" <<'EOF'
# Gestionado por reconcile_networkmanager_linux.sh.
# ifupdown conserva únicamente loopback; NetworkManager gestiona interfaces físicas.
[ifupdown]
managed=true
EOF
  if sudo test -f "$NM_DROPIN" && sudo cmp -s "$temporary" "$NM_DROPIN"; then
    rm -f -- "$temporary"
    ok "drop-in NetworkManager ya está actualizado"
    return 0
  fi
  backup_path "$NM_DROPIN"
  sudo install -d -m 755 "$(dirname "$NM_DROPIN")"
  sudo install -o root -g root -m 644 "$temporary" "$NM_DROPIN"
  rm -f -- "$temporary"
  ok "drop-in NetworkManager instalado"
}

quarantine_ifupdown() {
  local file temporary
  if [[ -e "$INTERFACES_FILE" ]]; then
    if sudo awk '
      /^[[:space:]]*(auto|allow-hotplug)[[:space:]]+/ {
        for (i = 2; i <= NF; i++) if ($i != "lo") found = 1
      }
      /^[[:space:]]*iface[[:space:]]+/ && $2 != "lo" { found = 1 }
      /^[[:space:]]*mapping[[:space:]]+/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$INTERFACES_FILE"; then
      backup_path "$INTERFACES_FILE"
      temporary="$(mktemp)"
      cat > "$temporary" <<'EOF'
# This file is managed by NetworkManager.
# The previous ifupdown configuration is in /var/backups/rafex-networkmanager/.
auto lo
iface lo inet loopback
EOF
      sudo install -o root -g root -m 644 "$temporary" "$INTERFACES_FILE"
      rm -f -- "$temporary"
      ok "ifupdown principal reducido a loopback"
    else
      ok "$INTERFACES_FILE ya contiene solo loopback"
    fi
  fi

  [[ -d "$INTERFACES_DIR" ]] || return 0
  while IFS= read -r -d '' file; do
    if sudo awk '
      /^[[:space:]]*(auto|allow-hotplug)[[:space:]]+/ {
        for (i = 2; i <= NF; i++) if ($i != "lo") found = 1
      }
      /^[[:space:]]*iface[[:space:]]+/ && $2 != "lo" { found = 1 }
      /^[[:space:]]*mapping[[:space:]]+/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$file"; then
      move_to_backup "$file"
    fi
  done < <(find "$INTERFACES_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
}

stop_ifup_services() {
  local iface
  while IFS= read -r iface; do
    if sudo systemctl is-active --quiet "ifup@${iface}.service" 2>/dev/null; then
      sudo systemctl stop "ifup@${iface}.service"
      info "detenido ifup@${iface}.service"
    fi
  done < <(interfaces)
}

stop_conflicting_services() {
  local unit
  for unit in networking.service wpa_supplicant.service dhcpcd.service; do
    if sudo systemctl is-active --quiet "$unit" 2>/dev/null; then
      sudo systemctl stop "$unit"
      info "detenido servicio independiente: $unit"
    fi
    if sudo systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      sudo systemctl disable "$unit" >/dev/null
      info "deshabilitado servicio independiente: $unit"
    fi
  done
}

apply_mode() {
  local iface unmanaged=0
  require_apply_safety
  sudo apt-get update
  sudo apt-get install -y network-manager wpasupplicant
  quarantine_ifupdown
  install_nm_dropin
  stop_ifup_services
  stop_conflicting_services
  sudo systemctl enable NetworkManager.service
  sudo systemctl restart NetworkManager.service
  nmcli networking on || true
  nmcli radio wifi on || true
  while IFS= read -r iface; do
    nmcli device set "$iface" managed yes || warn "no se pudo marcar $iface como managed=yes"
  done < <(interfaces)
  if command -v nmcli >/dev/null 2>&1; then
    while IFS=: read -r iface state _; do
      if [[ "$iface" != lo && "$state" == unmanaged ]]; then
        warn "$iface continúa unmanaged"
        unmanaged=$((unmanaged + 1))
      fi
    done < <(nmcli -t -f DEVICE,STATE device status 2>/dev/null || true)
  fi
  (( unmanaged == 0 )) || die "quedaron $unmanaged interfaz(es) unmanaged; revisa las políticas de NetworkManager"
  ok "interfaces físicas entregadas a NetworkManager"
  warn "no se copiaron perfiles ni contraseñas Wi-Fi"
  info "reconecta manualmente con: nmcli device wifi connect \"SSID\" --ask"
  show_nm_status
}

main() {
  parse_args "$@"
  require_linux
  case "$ACTION" in
    check) check_mode ;;
    plan) plan_mode ;;
    apply) apply_mode ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
