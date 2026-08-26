#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prepara comandos de energía para Debian y un helper powerctl para sesiones
# i3/SSH. No ejecuta apagados durante --check, --plan ni --apply.
set -Eeuo pipefail
umask 077

ACTION="check"
PROFILE_FILE="${POWER_PROFILE_FILE:-$HOME/.profile}"
HELPER="$HOME/.local/bin/powerctl"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

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
  power_control_linux.sh --check
  power_control_linux.sh --plan
  power_control_linux.sh --apply

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Instalar comandos y configurar PATH/helper
  -h, --help             Mostrar esta ayuda

Después de --apply estarán disponibles:
  powerctl off | reboot | suspend | hibernate | lock

Este script no ejecuta ninguna acción de apagado por sí mismo.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script solo funciona en Linux"
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
  [[ "$EUID" -ne 0 ]] || die "ejecuta el script como el usuario normal, no como root"
  if [[ "$ACTION" == "apply" ]] && ! command -v sudo >/dev/null 2>&1; then
    die "sudo no está instalado; ejecuta configure_sudo_linux.sh primero"
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

append_profile_block() {
  local begin='# BEGIN power-control-linux'
  local end='# END power-control-linux'
  local block
  local temporary
  block='case ":${PATH}:" in
  *:/usr/local/sbin:*) ;;
  *) export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH" ;;
esac'

  if [[ -f "$PROFILE_FILE" ]] && grep -Fq "$begin" "$PROFILE_FILE"; then
    ok "PATH de administración ya configurado en $PROFILE_FILE"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] agregar PATH de /usr/local/sbin:/usr/sbin:/sbin a $PROFILE_FILE"
    return 0
  fi
  mkdir -p "$(dirname "$PROFILE_FILE")"
  if [[ -e "$PROFILE_FILE" ]]; then
    cp -a "$PROFILE_FILE" "${PROFILE_FILE}.bak.${BACKUP_STAMP}"
    info "respaldo creado: ${PROFILE_FILE}.bak.${BACKUP_STAMP}"
  fi
  temporary="$(mktemp)"
  [[ -f "$PROFILE_FILE" ]] && cp -p "$PROFILE_FILE" "$temporary"
  printf '\n%s\n%s\n%s\n' "$begin" "$block" "$end" >> "$temporary"
  mv "$temporary" "$PROFILE_FILE"
  chmod 600 "$PROFILE_FILE"
  ok "PATH configurado en $PROFILE_FILE"
}

helper_content() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf '%s\n' "Uso: powerctl {off|reboot|suspend|hibernate|lock}"
}

run_systemctl() {
  local action="$1"
  if /usr/bin/systemctl "$action"; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo /usr/bin/systemctl "$action"
  else
    printf 'No se pudo ejecutar systemctl %s y sudo no está disponible.\n' "$action" >&2
    return 1
  fi
}

case "${1:-}" in
  off|poweroff|shutdown)
    [[ "${POWERCTL_CONFIRM:-}" == yes ]] || {
      read -r -p '¿Apagar la computadora? [y/N] ' answer
      [[ "$answer" =~ ^[Yy]$ ]] || exit 0
    }
    run_systemctl poweroff
    ;;
  reboot|restart) run_systemctl reboot ;;
  suspend|sleep) run_systemctl suspend ;;
  hibernate) run_systemctl hibernate ;;
  lock)
    if command -v loginctl >/dev/null 2>&1 && loginctl lock-session; then
      exit 0
    elif command -v i3lock >/dev/null 2>&1; then
      exec i3lock -c 000000
    else
      printf '%s\n' 'No existe loginctl ni i3lock para bloquear la sesión.' >&2
      exit 1
    fi
    ;;
  *) usage; exit 2 ;;
esac
EOF
}

install_helper() {
  local temporary
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] instalar helper $HELPER"
    return 0
  fi
  mkdir -p "$(dirname "$HELPER")"
  if [[ -e "$HELPER" ]]; then
    cp -a "$HELPER" "${HELPER}.bak.${BACKUP_STAMP}"
    info "respaldo creado: ${HELPER}.bak.${BACKUP_STAMP}"
  fi
  temporary="$(mktemp)"
  helper_content > "$temporary"
  install -m 0755 "$temporary" "$HELPER"
  rm -f "$temporary"
  ok "helper instalado: $HELPER"
}

check_commands() {
  echo
  echo -e "${BOLD}${CYAN}═══ Comandos de energía ═══${RESET}"
  printf 'PATH=%s\n' "$PATH"
  for command_name in systemctl loginctl shutdown poweroff reboot; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=%s\n' "$command_name" "$(command -v "$command_name")"
    elif [[ -x "/sbin/$command_name" ]]; then
      printf '%s=/sbin/%s (fuera del PATH actual)\n' "$command_name" "$command_name"
    elif [[ -x "/usr/sbin/$command_name" ]]; then
      printf '%s=/usr/sbin/%s (fuera del PATH actual)\n' "$command_name" "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
  if [[ -f "$PROFILE_FILE" ]] && grep -Fq '# BEGIN power-control-linux' "$PROFILE_FILE"; then
    ok "PATH persistente configurado"
  else
    warn "PATH persistente no configurado: $PROFILE_FILE"
  fi
  if [[ -x "$HELPER" ]]; then
    ok "powerctl disponible: $HELPER"
  else
    warn "powerctl no disponible: $HELPER"
  fi
}

main() {
  parse_args "$@"
  require_linux

  if [[ "$ACTION" == "check" ]]; then
    check_commands
    exit 0
  fi

  if [[ "$ACTION" == "plan" ]]; then
    if package_installed systemd-sysv && package_installed util-linux; then
      info "[plan] systemd-sysv y util-linux ya están instalados"
    else
      info "[plan] sudo apt-get install -y systemd-sysv util-linux"
    fi
  elif ! package_installed systemd-sysv || ! package_installed util-linux; then
    command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
    sudo -v
    sudo apt-get update
    sudo apt-get install -y systemd-sysv util-linux
  fi

  append_profile_block
  install_helper
  check_commands
  ok "comandos de energía preparados; usa powerctl off para apagar"
}

main "$@"
