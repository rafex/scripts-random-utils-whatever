#!/usr/bin/env bash
# Instala herramientas gráficas opcionales para la estación ThinkPad.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly -a PACKAGES=(gimp gimp-help-es krita krita-l10n)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_graphics_linux.sh [--check|--plan|--apply|--status]

Instala GIMP, ayuda en español, Krita y su localización. No modifica el
perfil gráfico ni descarga complementos fuera de Debian.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el instalador como usuario normal'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}"
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

report() {
  local package candidate
  printf '═══ Herramientas gráficas ═══\n'
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      printf '✓ %-18s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-18s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
  for command_name in gimp krita; do
    if command -v "$command_name" >/dev/null 2>&1; then
      ok "$command_name disponible"
    else
      warn "$command_name no está disponible"
    fi
  done
}

validate_candidates() {
  local package candidate missing=0
  for package in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done
  ((missing == 0)) || die 'algún paquete gráfico no tiene candidato APT'
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  ok 'herramientas gráficas instaladas'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check|status) report ;;
  plan)
    report
    info "[plan] sudo apt-get update && sudo apt-get install -y ${PACKAGES[*]}"
    ;;
  apply) apply_install; report ;;
  *) die "acción no válida: $ACTION" ;;
esac
