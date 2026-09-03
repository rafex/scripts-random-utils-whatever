#!/usr/bin/env bash
# v1.0.0 - Instala certutil para preparar una base NSS de Firefox OS.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly NSS_TOOLS_PACKAGE="libnss3-tools"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_firefoxos_ca_tools_linux.sh --check
  install_firefoxos_ca_tools_linux.sh --plan
  install_firefoxos_ca_tools_linux.sh --apply
  install_firefoxos_ca_tools_linux.sh --status

Instala libnss3-tools para preparar y validar bases NSS de Firefox OS. No
modifica el teléfono ni descarga certificados.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | \
    grep -Fqx 'install ok installed'
}

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

package_candidate() {
  apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

check_candidate() {
  local candidate
  candidate="$(package_candidate "$NSS_TOOLS_PACKAGE")"
  [[ -n "$candidate" && "$candidate" != '(none)' ]] ||
    die "sin candidato APT: $NSS_TOOLS_PACKAGE"
}

show_status() {
  local candidate version
  printf '═══ Herramientas CA Firefox OS ═══\n'
  candidate="$(package_candidate "$NSS_TOOLS_PACKAGE")"
  if package_installed "$NSS_TOOLS_PACKAGE"; then
    version="$(package_version "$NSS_TOOLS_PACKAGE")"
    ok "$NSS_TOOLS_PACKAGE instalado (${version:-versión desconocida})"
  else
    warn "$NSS_TOOLS_PACKAGE ausente (candidato: ${candidate:-(none)})"
  fi
  if command -v certutil >/dev/null 2>&1; then
    ok "certutil disponible: $(command -v certutil)"
  else
    info 'certutil no está disponible; se instalará con --apply'
  fi
  info 'no se modifica el teléfono ni se inicia adb'
}

show_plan() {
  check_candidate
  printf '═══ Plan herramientas CA Firefox OS ═══\n'
  info "instalar con APT: $NSS_TOOLS_PACKAGE"
  info 'proporcionar certutil para leer y escribir una copia de cert9.db'
  info 'no compilar B2G/NSS, no descargar certificados y no tocar el teléfono'
}

apply_install() {
  check_candidate
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  info "instalando $NSS_TOOLS_PACKAGE desde Debian"
  sudo apt-get --no-remove install --no-install-recommends -y "$NSS_TOOLS_PACKAGE"
  ok 'certutil y herramientas NSS instalados'
  info 'la instalación de certificados requiere ejecutar después el helper Firefox OS'
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      show_status
      check_candidate
      ;;
    plan) show_plan ;;
    apply) apply_install ;;
    status) show_status ;;
  esac
}

main "$@"
