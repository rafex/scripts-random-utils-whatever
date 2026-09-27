#!/usr/bin/env bash
# shellcheck shell=bash
# Instala y configura mbpfan para el perfil MacBook Pro Late 2012.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
PROFILE_CONFIG_FILE="$REPO_ROOT/dotfiles/profiles/macbook-pro-late2012/config/mbpfan.conf"
USER_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mbpfan.conf"

ACTION='check'
CONFIG_FILE='/etc/mbpfan.conf'
BACKUP_ROOT='/var/backups/rafex-mbpfan'
STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_mbpfan_linux.sh --check
  configure_mbpfan_linux.sh --plan
  configure_mbpfan_linux.sh --status
  configure_mbpfan_linux.sh --apply
  configure_mbpfan_linux.sh --rollback

Configura mbpfan únicamente para el perfil MacBook Pro Late 2012.
--apply instala mbpfan desde Debian, carga applesmc/coretemp, instala
/etc/mbpfan.conf y habilita mbpfan.service.
EOF
}

parse_args() {
  [[ $# -le 1 ]] || die 'selecciona una sola acción'
  if [[ $# -eq 1 ]]; then
    case "$1" in
      --check|--plan|--status|--apply|--rollback) ACTION="${1#--}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  fi
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este script requiere Linux Debian'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "distribución no soportada: ${ID:-desconocida}"
  for command_name in apt-cache apt-get dpkg-query mktemp systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando: $command_name"
  done
  if [[ "$ACTION" == apply || "$ACTION" == rollback ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
    sudo -v
  fi
}

read_first() {
  local path="$1"
  [[ -r "$path" ]] && tr -d '\n' < "$path" || true
}

model_name() { read_first /sys/class/dmi/id/product_name; }
system_vendor() { read_first /sys/class/dmi/id/sys_vendor; }

is_macbook_profile() {
  [[ "$(system_vendor)" == Apple* && "$(model_name)" == MacBook* ]]
}

module_loaded() {
  local module="$1"
  [[ -r /proc/modules ]] && awk -v module="$module" '$1 == module { found=1 } END { exit !found }' /proc/modules
}

applesmc_available() {
  compgen -G '/sys/devices/platform/applesmc.*' >/dev/null 2>&1
}

fan_sensors_available() {
  compgen -G '/sys/devices/platform/applesmc.*/fan*_output' >/dev/null 2>&1
}

package_installed() {
  dpkg-query -W -f='${Status}' mbpfan 2>/dev/null | grep -Fq 'install ok installed'
}

package_version() {
  dpkg-query -W -f='${Version}' mbpfan 2>/dev/null || true
}

package_candidate() {
  apt-cache policy mbpfan 2>/dev/null | awk '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

service_exists() {
  systemctl list-unit-files --no-legend mbpfan.service 2>/dev/null \
    | awk '$1 == "mbpfan.service" { found=1 } END { exit !found }'
}

service_active() { systemctl is-active --quiet mbpfan.service; }
service_enabled() { systemctl is-enabled --quiet mbpfan.service; }

conflicting_service() {
  local service
  for service in macfanctld.service fancontrol.service thinkfan.service; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      printf '%s\n' "$service"
      return 0
    fi
  done
  return 1
}

render_config() {
  if [[ -r "$PROFILE_CONFIG_FILE" ]]; then
    cat "$PROFILE_CONFIG_FILE"
    return 0
  fi
  if [[ -r "$USER_CONFIG_FILE" ]]; then
    cat "$USER_CONFIG_FILE"
    return 0
  fi
  cat <<'EOF'
[general]
# mbpfan usa los límites de velocidad publicados por applesmc.
low_temp = 55
high_temp = 65
max_temp = 85
polling_interval = 1
EOF
}

show_status() {
  local conflict='' vendor product
  vendor="$(system_vendor)"
  product="$(model_name)"
  echo '═══ mbpfan — MacBook Pro ═══'
  printf 'vendor=%s\n' "${vendor:-unknown}"
  printf 'model=%s\n' "${product:-unknown}"
  if is_macbook_profile; then
    ok 'perfil=macbook'
  else
    warn 'perfil= no es un MacBook Apple; --apply quedará bloqueado'
  fi
  if package_installed; then
    printf 'package=installed\nversion=%s\n' "$(package_version)"
  else
    printf 'package=missing\ncandidate=%s\n' "$(package_candidate)"
  fi
  if module_loaded applesmc; then ok 'module applesmc=loaded'; else warn 'module applesmc=not-loaded'; fi
  if module_loaded coretemp; then ok 'module coretemp=loaded'; else warn 'module coretemp=not-loaded'; fi
  if applesmc_available; then ok 'applesmc=sysfs-present'; else warn 'applesmc=sysfs-missing'; fi
  if fan_sensors_available; then ok 'fans=sysfs-present'; else warn 'fans=sysfs-missing'; fi
  if service_exists; then
    printf 'service=installed\n'
    if service_enabled; then ok 'service enabled'; else warn 'service disabled'; fi
    if service_active; then ok 'service active'; else warn 'service inactive'; fi
  else
    warn 'service mbpfan.service no está instalado'
  fi
  if [[ -r "$CONFIG_FILE" ]]; then
    ok "configuración presente: $CONFIG_FILE"
    sed -n '/^low_temp[[:space:]]*=/p;/^high_temp[[:space:]]*=/p;/^max_temp[[:space:]]*=/p;/^polling_interval[[:space:]]*=/p' "$CONFIG_FILE"
  else
    warn "configuración ausente: $CONFIG_FILE"
  fi
  conflict="$(conflicting_service || true)"
  if [[ -n "$conflict" ]]; then
    warn "controlador de ventilador alternativo activo: $conflict"
  fi
}

ensure_macbook() {
  is_macbook_profile || die 'el equipo no coincide con el perfil MacBook Pro; se bloquea la configuración'
}

backup_config() {
  local backup="$BACKUP_ROOT/mbpfan.conf.bak.$STAMP" suffix=1
  sudo install -d -m 0700 "$BACKUP_ROOT"
  while sudo test -e "$backup"; do
    backup="$BACKUP_ROOT/mbpfan.conf.bak.$STAMP.$suffix"
    suffix=$((suffix + 1))
  done
  sudo cp -a -- "$CONFIG_FILE" "$backup"
  printf '%s\n' "$backup"
}

install_config() {
  local temporary_file backup='' changed=0
  temporary_file="$(mktemp)"
  render_config > "$temporary_file"
  if sudo test -r "$CONFIG_FILE" && sudo cmp -s "$temporary_file" "$CONFIG_FILE"; then
    ok 'configuración mbpfan ya estaba instalada'
  else
    changed=1
    if sudo test -e "$CONFIG_FILE"; then
      backup="$(backup_config)"
    fi
    sudo install -o root -g root -m 0644 "$temporary_file" "$CONFIG_FILE"
    [[ -z "$backup" ]] || info "respaldo creado: $backup"
    ok "configuración instalada: $CONFIG_FILE"
  fi
  if ! sudo systemctl daemon-reload || ! sudo systemctl enable --now mbpfan.service; then
    if ((changed == 1)); then
      if [[ -n "$backup" ]]; then
        sudo cp -a -- "$backup" "$CONFIG_FILE"
      else
        sudo rm -f -- "$CONFIG_FILE"
      fi
    fi
    die 'mbpfan.service no pudo iniciarse; se restauró la configuración anterior'
  fi
  if ! service_active; then
    rm -f -- "$temporary_file"
    die 'mbpfan.service no quedó activo; revisa journalctl -u mbpfan.service'
  fi
  rm -f -- "$temporary_file"
}

apply_config() {
  local conflict=''
  ensure_macbook
  if conflict="$(conflicting_service || true)"; then
    die "controlador alternativo activo: $conflict; no se mezclará con mbpfan"
  fi
  if ! package_installed; then
    [[ -n "$(package_candidate)" && "$(package_candidate)" != '(none)' ]] || die 'mbpfan no tiene candidato APT'
    info 'instalando mbpfan desde Debian'
    sudo apt-get update
    sudo apt-get install -y mbpfan
  fi
  sudo modprobe coretemp
  sudo modprobe applesmc
  applesmc_available || die 'applesmc no expone sysfs después de cargar el módulo'
  fan_sensors_available || die 'applesmc no expone sensores de ventilador; no se habilitará mbpfan'
  install_config
  ok 'mbpfan habilitado y activo para el perfil MacBook Pro'
}

rollback_config() {
  local latest
  latest="$(sudo find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'mbpfan.conf.bak.*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print }')"
  [[ -n "$latest" ]] || die 'no existe un respaldo mbpfan para restaurar'
  sudo install -o root -g root -m 0644 "$latest" "$CONFIG_FILE"
  sudo systemctl restart mbpfan.service
  ok 'configuración mbpfan restaurada desde el último respaldo'
}

main() {
  parse_args "$@"
  require_linux
  case "$ACTION" in
    check)
      show_status
      ;;
    status)
      show_status
      ;;
    plan)
      show_status
      info '[plan] instalar mbpfan desde Debian si falta'
      info '[plan] cargar los módulos coretemp y applesmc'
      info '[plan] respaldar /etc/mbpfan.conf si existe'
      info '[plan] instalar la configuración conservadora 55/65/85 con polling de 1s'
      info '[plan] habilitar y arrancar mbpfan.service'
      ;;
    apply)
      apply_config
      ;;
    rollback)
      rollback_config
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
