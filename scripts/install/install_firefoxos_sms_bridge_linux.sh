#!/usr/bin/env bash
# v1.0.0 - Instala el puente local de SMS para Firefox OS.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/scripts/system/firefoxos_sms_bridge_linux.sh"
TARGET="$HOME/.local/bin/firefoxos-sms-bridge.sh"
STATE_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/rafex/firefoxos-sms"
readonly -a PACKAGES=(podman python3)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_firefoxos_sms_bridge_linux.sh --check
  install_firefoxos_sms_bridge_linux.sh --plan
  install_firefoxos_sms_bridge_linux.sh --apply
  install_firefoxos_sms_bridge_linux.sh --status

Prepara Podman rootless y el helper del puente SMS ThinkPad ↔ Firefox OS.
No inicia el servicio, no modifica UFW y no configura ADB ni el teléfono.
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
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el instalador como usuario normal'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] ||
    die 'se requiere Debian o un derivado compatible'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
    [[ -f "$SOURCE" ]] || die "falta el helper del repositorio: $SOURCE"
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

validate_candidates() {
  local package candidate missing=0
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      ok "$package ya está instalado"
      continue
    fi
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    else
      info "$package disponible: $candidate"
    fi
  done
  ((missing == 0)) || die 'algún paquete requerido no tiene candidato APT'
}

validate_sources() {
  local required
  [[ -f "$SOURCE" ]] || die "falta el helper del repositorio: $SOURCE"
  for required in \
    "$REPO_ROOT/containers/firefoxos-sms-bridge/Containerfile" \
    "$REPO_ROOT/containers/firefoxos-sms-bridge/server.py" \
    "$REPO_ROOT/examples/firefoxos/sms-bridge/manifest.webapp" \
    "$REPO_ROOT/examples/firefoxos/sms-bridge/index.html" \
    "$REPO_ROOT/examples/firefoxos/sms-bridge/style.css" \
    "$REPO_ROOT/examples/firefoxos/sms-bridge/app.js"; do
    [[ -f "$required" ]] || die "falta componente del puente: $required"
  done
}

backup_if_needed() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "${target}.bak.${STAMP}"
  info "respaldo creado: ${target}.bak.${STAMP}"
}

install_helper() {
  mkdir -p -- "$(dirname -- "$TARGET")"
  if [[ -f "$TARGET" ]] && cmp -s "$SOURCE" "$TARGET"; then
    ok "helper ya está actualizado: $TARGET"
    return
  fi
  backup_if_needed "$TARGET"
  install -m 0755 -- "$SOURCE" "$TARGET"
  ok "helper instalado: $TARGET"
}

show_status() {
  local package version candidate
  printf '═══ Puente SMS Firefox OS ═══\n'
  for package in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package")"
    if package_installed "$package"; then
      version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
      ok "$package instalado (${version:-versión desconocida})"
    else
      warn "$package ausente (candidato: ${candidate:-(none)})"
    fi
  done
  if [[ -f "$TARGET" ]]; then
    ok "helper instalado: $TARGET"
  else
    info "helper no instalado todavía"
  fi
  if [[ -d "$STATE_ROOT" ]]; then
    printf 'estado=%s\n' "$STATE_ROOT"
    info 'el directorio de estado existe; no se muestran tokens ni mensajes'
  else
    info 'el directorio de estado se creará al iniciar el servicio'
  fi
  info 'no se inicia el puente, no se modifica UFW y no se toca el Flame'
}

show_plan() {
  validate_sources
  validate_candidates
  printf '═══ Plan de instalación del puente SMS Firefox OS ═══\n'
  info "instalar si faltan: ${PACKAGES[*]}"
  info "instalar helper: $TARGET"
  info "preparar estado privado: $STATE_ROOT (0700)"
  info 'no iniciar Podman, no crear tokens, no modificar UFW y no usar ADB'
}

apply_install() {
  local package missing=0
  validate_sources
  validate_candidates
  for package in "${PACKAGES[@]}"; do
    package_installed "$package" || missing=1
  done
  if ((missing)); then
    sudo -v
    info 'actualizando índices APT'
    sudo apt-get update
    info "instalando: ${PACKAGES[*]}"
    sudo apt-get --no-remove install --no-install-recommends -y "${PACKAGES[@]}"
  fi
  command -v podman >/dev/null 2>&1 || die 'Podman no quedó instalado'
  command -v python3 >/dev/null 2>&1 || die 'python3 no quedó instalado'
  install_helper
  mkdir -p -- "$STATE_ROOT"
  chmod 0700 -- "$STATE_ROOT"
  ok 'estado privado preparado; no se inicializó ninguna credencial'
  info 'inicia el servicio explícitamente con just firefoxos-sms --serve-podman'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check)
    validate_sources
    show_status
    validate_candidates
    ok 'puente SMS listo para instalar; --check no modificó archivos'
    ;;
  plan) show_plan ;;
  apply) apply_install ;;
  status) show_status ;;
esac
