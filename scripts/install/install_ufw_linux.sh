#!/usr/bin/env bash
# shellcheck shell=bash
# Instala y configura UFW para una laptop Debian sin abrir servicios innecesarios.
set -Eeuo pipefail
umask 077

ACTION='check'
PROFILE='base'
REMOTE_SCOPE='anywhere'
LOG_FILE="${UFW_INSTALL_LOG_FILE:-}"
LOG_DIR="${UFW_INSTALL_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scripts-random-utils-whatever/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LAN_SUBNETS_RAW="${UFW_LAN_SUBNETS:-192.168.0.0/24 192.168.1.0/24 192.168.3.0/24}"
read -r -a LAN_SUBNETS <<< "$LAN_SUBNETS_RAW"

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
  install_ufw_linux.sh --check
  install_ufw_linux.sh --plan [--profile base|dev|media|all]
  install_ufw_linux.sh --apply [--profile base|dev|media|all]
  install_ufw_linux.sh --status

Perfiles:
  base   SSH 22/tcp y Mosh 60000:61000/udp (predeterminado)
  dev    base + servicios de desarrollo en las redes LAN configuradas
  media  base + OBS/MediaMTX en las redes LAN configuradas
  all    base + dev + media

Opciones:
  --lan-only             Limita SSH y Mosh a UFW_LAN_SUBNETS
  --log-file <archivo>   Guarda la salida en el archivo indicado
  --check                Diagnóstico sin cambios persistentes
  --plan                 Mostrar cambios sin aplicarlos
  --apply                Instalar y aplicar la política
  --status               Mostrar `ufw status verbose`
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --status) ACTION='status'; shift ;;
      --profile)
        [[ $# -ge 2 ]] || die '--profile requiere base, dev, media o all'
        PROFILE="$2"
        shift 2
        ;;
      --lan-only) REMOTE_SCOPE='lan'; shift ;;
      --log-file)
        [[ $# -ge 2 ]] || die '--log-file requiere un archivo'
        LOG_FILE="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  case "$PROFILE" in
    base|dev|media|all) ;;
    *) die "perfil desconocido: $PROFILE" ;;
  esac
}

init_logging() {
  [[ "$ACTION" == apply || -n "$LOG_FILE" ]] || return 0
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$LOG_DIR/install_ufw_${STAMP}.log"
  fi
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "log: $LOG_FILE"
}

report_failure() {
  local status="$?"
  if [[ "$status" -ne 0 && -n "$LOG_FILE" ]]; then
    echo "✗ ejecución fallida; log: $LOG_FILE" >&2
  fi
  exit "$status"
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "distribución no soportada: ${ID:-desconocida}"
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el script como usuario normal; se usará sudo cuando sea necesario'
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
  command -v dpkg-query >/dev/null 2>&1 || die 'dpkg-query no está disponible'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
    sudo -v
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

profile_has_dev() { [[ "$PROFILE" == dev || "$PROFILE" == all ]]; }
profile_has_media() { [[ "$PROFILE" == media || "$PROFILE" == all ]]; }

ufw_status() {
  sudo -n ufw status 2>/dev/null
}

rule_present() {
  local needle="$1"
  ufw_status | grep -F "$needle" | grep -Fq 'Anywhere'
}

lan_rule_present() {
  local subnet="$1" port="$2" protocol="$3"
  ufw_status | grep -F "$subnet" | grep -Fq "${port}/${protocol}"
}

print_rule_plan() {
  local subnet
  if [[ "$REMOTE_SCOPE" == anywhere ]]; then
    info '[plan] sudo ufw allow 22/tcp comment "SSH"'
    info '[plan] sudo ufw allow 60000:61000/udp comment "Mosh"'
  else
    for subnet in "${LAN_SUBNETS[@]}"; do
      info "[plan] sudo ufw allow from $subnet to any port 22 proto tcp comment \"SSH LAN\""
      info "[plan] sudo ufw allow from $subnet to any port 60000:61000 proto udp comment \"Mosh LAN\""
    done
  fi
  if profile_has_dev; then
    info '[plan] reglas LAN dev: 3000/tcp, 5173/tcp, 8443/tcp y 30083/tcp'
  fi
  if profile_has_media; then
    info '[plan] reglas LAN media: 4455/tcp, 8889/tcp, 8882/udp y 9000:9100/udp'
  fi
}

check_rules() {
  local subnet
  if ! command -v ufw >/dev/null 2>&1; then
    warn 'ufw no está instalado'
    return 0
  fi
  if ! sudo -n ufw status verbose >/dev/null 2>&1; then
    warn 'no se puede leer UFW sin sudo; usa --apply para autorizar sudo o ejecuta sudo ufw status verbose'
    return 0
  fi
  if [[ "$REMOTE_SCOPE" == anywhere ]]; then
    if rule_present '22/tcp'; then
      ok 'SSH 22/tcp configurado'
    else
      warn 'falta SSH 22/tcp'
    fi
    if rule_present '60000:61000/udp'; then
      ok 'Mosh 60000:61000/udp configurado'
    else
      warn 'falta Mosh 60000:61000/udp'
    fi
  else
    for subnet in "${LAN_SUBNETS[@]}"; do
      if lan_rule_present "$subnet" 22 tcp; then
        ok "SSH permitido desde $subnet"
      else
        warn "falta SSH desde $subnet"
      fi
      if lan_rule_present "$subnet" 60000:61000 udp; then
        ok "Mosh permitido desde $subnet"
      else
        warn "falta Mosh desde $subnet"
      fi
    done
  fi
}

check_installation() {
  echo '═══ UFW para ThinkPad ═══'
  if package_installed ufw; then
    ok 'paquete ufw instalado'
  else
    warn 'paquete ufw pendiente'
  fi
  if command -v ufw >/dev/null 2>&1; then
    sudo -n ufw status verbose 2>/dev/null || warn 'estado UFW requiere sudo -n o aún no está configurado'
  else
    echo 'ufw=missing'
  fi
  echo "profile=$PROFILE"
  echo "remote_scope=$REMOTE_SCOPE"
  echo "lan_subnets=${LAN_SUBNETS[*]}"
  check_rules
}

install_packages() {
  if [[ "$ACTION" == plan ]]; then
    info '[plan] sudo apt-get update'
    info '[plan] sudo apt-get install -y ufw'
    return 0
  fi
  [[ "$ACTION" == apply ]] || return 0
  sudo apt-get update
  sudo apt-get install -y ufw
}

allow_rule() {
  local description="$1"
  shift
  if rule_present "$description"; then
    ok "regla existente: $description"
    return 0
  fi
  sudo ufw allow "$@"
  ok "regla añadida: $description"
}

allow_lan_rule() {
  local subnet="$1" port="$2" protocol="$3" comment="$4"
  if lan_rule_present "$subnet" "$port" "$protocol"; then
    ok "regla existente: $port/$protocol desde $subnet"
    return 0
  fi
  sudo ufw allow from "$subnet" to any port "$port" proto "$protocol" comment "$comment"
  ok "regla añadida: $port/$protocol desde $subnet"
}

apply_rules() {
  local subnet
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw default deny routed
  sudo ufw logging low

  if [[ "$REMOTE_SCOPE" == anywhere ]]; then
    allow_rule '22/tcp' 22/tcp comment 'SSH'
    allow_rule '60000:61000/udp' 60000:61000/udp comment 'Mosh'
  else
    for subnet in "${LAN_SUBNETS[@]}"; do
      allow_lan_rule "$subnet" 22 tcp 'SSH LAN'
      allow_lan_rule "$subnet" 60000:61000 udp 'Mosh LAN'
    done
  fi

  if profile_has_dev; then
    for subnet in "${LAN_SUBNETS[@]}"; do
      allow_lan_rule "$subnet" 3000 tcp 'dev web 3000'
      allow_lan_rule "$subnet" 5173 tcp 'Vite dev server'
      allow_lan_rule "$subnet" 8443 tcp 'dev HTTPS 8443'
      allow_lan_rule "$subnet" 30083 tcp 'FHS agent-server'
    done
  fi

  if profile_has_media; then
    for subnet in "${LAN_SUBNETS[@]}"; do
      allow_lan_rule "$subnet" 4455 tcp 'OBS WebSocket'
      allow_lan_rule "$subnet" 8889 tcp 'MediaMTX WHIP'
      allow_lan_rule "$subnet" 8882 udp 'MediaMTX ICE media'
      allow_lan_rule "$subnet" 9000:9100 udp 'media streaming'
    done
  fi

  sudo ufw --force enable
  sudo ufw status verbose
}

main() {
  parse_args "$@"
  init_logging
  require_debian
  case "$ACTION" in
    check|status)
      [[ "$ACTION" == status ]] && { sudo ufw status verbose; return 0; }
      check_installation
      ;;
    plan)
      echo '═══ Plan UFW para ThinkPad ═══'
      info '[plan] sudo -v'
      info '[plan] política: deny incoming, allow outgoing, deny routed, logging low'
      install_packages
      print_rule_plan
      ok 'plan terminado; no se modificó el sistema'
      ;;
    apply)
      echo '═══ Aplicando UFW para ThinkPad ═══'
      install_packages
      apply_rules
      ok "UFW configurado; perfil=$PROFILE; alcance SSH/Mosh=$REMOTE_SCOPE"
      ;;
  esac
}

trap report_failure EXIT
main "$@"
