#!/usr/bin/env bash
# shellcheck shell=bash
# Instala ZoiteChat, cliente IRC GTK3 sucesor de la línea XChat/HexChat.
set -Eeuo pipefail
umask 077

ACTION='check'
readonly PACKAGE='zoitechat'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_zoitechat_linux.sh --check
  install_zoitechat_linux.sh --plan
  install_zoitechat_linux.sh --apply
  install_zoitechat_linux.sh --status

Instala ZoiteChat desde Debian. No configura redes IRC, no guarda credenciales
en el repositorio y no inicia el cliente automáticamente.
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

show_state() {
  printf 'paquete=%s\n' "$PACKAGE"
  printf 'candidato=%s\n' "$(candidate_version)"
  if package_installed; then
    ok "paquete instalado: $(dpkg-query -W -f='${Version}' "$PACKAGE")"
  else
    warn 'paquete no instalado'
  fi
  if command -v zoitechat >/dev/null 2>&1; then
    printf 'binario=%s\n' "$(command -v zoitechat)"
  else
    printf 'binario=ausente\n'
  fi
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      echo '═══ Cliente IRC ZoiteChat ═══'
      show_state
      ;;
    status)
      show_state
      ;;
    plan)
      echo '═══ Plan cliente IRC ZoiteChat ═══'
      printf 'paquete=%s\n' "$PACKAGE"
      printf 'candidato=%s\n' "$(candidate_version)"
      printf '%s\n' 'Se instalará con APT solo durante --apply; no se configurará una red ni se iniciará el cliente.'
      ;;
    apply)
      if package_installed; then
        ok 'ZoiteChat ya está instalado; no se ejecuta APT'
      else
        sudo -v
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends "$PACKAGE"
        ok 'ZoiteChat instalado'
      fi
      show_state
      ;;
  esac
}

main "$@"
