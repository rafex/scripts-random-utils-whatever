#!/usr/bin/env bash
# Instala fuentes para web, programación y cobertura CJK.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PROFILE="web-programming"
readonly -a BASE_PACKAGES=(
  fonts-dejavu fonts-liberation2 fonts-noto-core fonts-noto-color-emoji
  fonts-inter fonts-ibm-plex fonts-hack fonts-roboto fonts-firacode
  fonts-jetbrains-mono fonts-cascadia-code fonts-inconsolata
  fonts-crosextra-carlito fonts-crosextra-caladea
)
readonly -a CJK_PACKAGES=(fonts-noto-cjk)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_fonts_linux.sh [--check|--plan|--apply|--status] [--profile PERFIL]

Perfiles:
  web-programming  Fuentes latinas, UI, emoji y programación.
  cjk              Perfil base más Noto CJK (ocupa bastante espacio).
  all              Perfil base más Noto CJK.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --profile)
        (($# >= 2)) || die '--profile requiere un valor'
        PROFILE="$2"; shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  case "$PROFILE" in
    web-programming|cjk|all) ;;
    *) die "perfil desconocido: $PROFILE" ;;
  esac
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

selected_packages() {
  printf '%s\n' "${BASE_PACKAGES[@]}"
  if [[ "$PROFILE" == cjk || "$PROFILE" == all ]]; then
    printf '%s\n' "${CJK_PACKAGES[@]}"
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
  printf '═══ Fuentes (%s) ═══\n' "$PROFILE"
  while IFS= read -r package; do
    if package_installed "$package"; then
      printf '✓ %-28s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-28s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done < <(selected_packages)
  if command -v fc-match >/dev/null 2>&1; then
    printf 'sans='; fc-match sans -f '%{family}\n' 2>/dev/null | head -n 1
    printf 'monospace='; fc-match monospace -f '%{family}\n' 2>/dev/null | head -n 1
  else
    warn 'fc-match no está disponible'
  fi
}

validate_candidates() {
  local package candidate missing=0
  while IFS= read -r package; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done < <(selected_packages)
  ((missing == 0)) || die 'alguna fuente no tiene candidato APT'
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  local -a packages=()
  mapfile -t packages < <(selected_packages)
  info "instalando: ${packages[*]}"
  sudo apt-get install -y "${packages[@]}"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
  ok 'fuentes instaladas y caché actualizada'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check|status) report ;;
  plan)
    report
    info "[plan] perfil=$PROFILE"
    info '[plan] sudo apt-get update y apt-get install de las fuentes seleccionadas'
    ;;
  apply) apply_install; report ;;
  *) die "acción no válida: $ACTION" ;;
esac
