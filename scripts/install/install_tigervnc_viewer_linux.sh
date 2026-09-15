#!/usr/bin/env bash
# shellcheck shell=bash
# Instala el cliente VNC TigerVNC de Debian para el usuario de la ThinkPad.
set -Eeuo pipefail
umask 077

ACTION='check'
readonly PACKAGE='tigervnc-viewer'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_tigervnc_viewer_linux.sh --check
  install_tigervnc_viewer_linux.sh --plan
  install_tigervnc_viewer_linux.sh --apply
  install_tigervnc_viewer_linux.sh --status

Instala únicamente el cliente TigerVNC de Debian. No inicia un servidor VNC,
no habilita servicios y no abre puertos.
EOF
}

parse_args() {
  [[ $# -le 1 ]] || die 'selecciona una sola acción'
  if [[ $# -eq 1 ]]; then
    case "$1" in
      --check|--plan|--apply|--status) ACTION="${1#--}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  fi
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "distribución no soportada: ${ID:-desconocida}"
  for command_name in apt-cache apt-get dpkg-query; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando: $command_name"
  done
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null | grep -Fq 'install ok installed'
}

candidate_version() {
  apt-cache policy "$PACKAGE" 2>/dev/null | awk '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

viewer_command() {
  command -v vncviewer 2>/dev/null || command -v xtigervncviewer 2>/dev/null || true
}

show_state() {
  printf 'paquete=%s\n' "$PACKAGE"
  printf 'candidato=%s\n' "$(candidate_version)"
  if package_installed; then
    ok "paquete instalado: $(dpkg-query -W -f='${Version}' "$PACKAGE")"
  else
    warn 'paquete no instalado'
  fi
  printf 'binario=%s\n' "$(viewer_command)"
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      echo '═══ Cliente VNC TigerVNC ═══'
      show_state
      ;;
    status)
      show_state
      ;;
    plan)
      echo '═══ Plan cliente VNC TigerVNC ═══'
      printf 'paquete=%s\n' "$PACKAGE"
      printf 'candidato=%s\n' "$(candidate_version)"
      printf '%s\n' 'Se instalará con APT solo durante --apply; no se iniciará ningún servidor ni servicio.'
      ;;
    apply)
      if package_installed; then
        ok 'TigerVNC ya está instalado; no se ejecuta APT'
      else
        sudo -v
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends "$PACKAGE"
        ok 'TigerVNC instalado'
      fi
      show_state
      ;;
  esac
}

main "$@"
