#!/usr/bin/env bash
# v1.0.0 - Instala Restic y el cliente Secret Service sin inicializar repositorios.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PACKAGES=(restic libsecret-tools gnome-keyring)

usage() {
  cat <<'EOF'
Uso: install_restic_backup_linux.sh [--check|--plan|--apply|--status]

Instala Restic y Secret Service. Nunca inicializa repositorios ni crea timers.
EOF
}

die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  exit 1
}

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

require_linux_debian() {
  [[ "$(uname -s)" == "Linux" ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

package_candidate() {
  local package_name="$1"
  apt-cache policy "$package_name" 2>/dev/null \
    | awk '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null \
    | grep -q '^ii '
}

report_packages() {
  local package_name candidate
  for package_name in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package_name")"
    if package_installed "$package_name"; then
      ok "$package_name instalado"
    else
      warn "$package_name no está instalado"
    fi
    if [[ -n "$candidate" && "$candidate" != '(none)' ]]; then
      info "$package_name candidato APT: $candidate"
    else
      warn "$package_name no tiene candidato APT"
    fi
  done
}

validate_packages() {
  local package_name candidate missing=0
  for package_name in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package_name")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package_name"
      missing=1
    fi
  done
  (( missing == 0 )) || die 'faltan candidatos APT; revisa las fuentes Debian'
}

status() {
  printf '═══ Restic y Secret Service ═══\n'
  report_packages
  if command -v restic >/dev/null 2>&1; then
    ok "restic disponible: $(restic version | awk 'NR == 1 { print $2 }')"
  else
    warn 'restic no está disponible'
  fi
  if command -v secret-tool >/dev/null 2>&1; then
    ok 'secret-tool disponible para GNOME Keyring/Secret Service'
  else
    warn 'secret-tool no está disponible'
  fi
  if command -v gnome-keyring >/dev/null 2>&1; then
    ok 'gnome-keyring disponible'
  else
    warn 'gnome-keyring no está disponible'
  fi
  info 'no se inicializan repositorios automáticamente'
}

apply_install() {
  command -v sudo >/dev/null 2>&1 || die 'sudo no está disponible'
  validate_packages
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  ok 'Restic y Secret Service instalados; no se inicializó ningún repositorio'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
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
    check)
      printf '═══ Instalador Restic ═══\n'
      report_packages
      validate_packages
      if command -v restic >/dev/null 2>&1 && command -v secret-tool >/dev/null 2>&1; then
        ok 'dependencias principales disponibles'
      else
        warn 'ejecuta --apply para instalar las dependencias faltantes'
        exit 1
      fi
      ;;
    plan)
      printf '═══ Plan Restic ═══\n'
      validate_packages
      info "instalar: ${PACKAGES[*]}"
      info 'no se crearán repositorios, no se tocará el SSD y no se instalará ningún timer'
      ;;
    apply) apply_install ;;
    status) status ;;
  esac
}

main "$@"
