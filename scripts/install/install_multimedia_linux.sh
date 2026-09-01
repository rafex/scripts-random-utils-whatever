#!/usr/bin/env bash
# Instala reproducción, codificación y plugins multimedia desde Debian.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PREEXISTING_CONSUMERS=()
readonly -a PACKAGES=(
  ffmpeg libavcodec-extra libx264-165 libx265-216 x264 mpv vlc
  gstreamer1.0-libav gstreamer1.0-plugins-base gstreamer1.0-plugins-good
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-pipewire
  gstreamer1.0-tools
)
readonly -a CONSUMER_PACKAGES=(
  ffmpeg x264 vlc gstreamer1.0-libav obs-studio guvcview
  ffmpegthumbs
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_multimedia_linux.sh [--check|--plan|--apply|--status]

Instala FFmpeg, codecs x264/x265, mpv, VLC y plugins GStreamer. No cambia
PipeWire, WirePlumber ni la configuración de red.
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
  printf '═══ Multimedia ═══\n'
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      printf '✓ %-28s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-28s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
  for command_name in ffmpeg mpv vlc; do
    if command -v "$command_name" >/dev/null 2>&1; then
      ok "$command_name disponible"
    else
      warn "$command_name no está disponible"
    fi
  done
  if command -v pactl >/dev/null 2>&1; then
    pactl info 2>/dev/null | awk -F': ' '/^Server Name:/ { print "audio=" $2; exit }' || true
  fi
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
  ((missing == 0)) || die 'algún paquete multimedia no tiene candidato APT'
}

capture_preexisting_consumers() {
  local package
  PREEXISTING_CONSUMERS=()
  for package in "${CONSUMER_PACKAGES[@]}"; do
    if package_installed "$package"; then
      PREEXISTING_CONSUMERS+=("$package")
    fi
  done
}

repair_multimedia_dependencies() {
  local package
  local -a removed_consumers=()
  info 'reparando dependencias después de cambiar la variante FFmpeg'
  sudo apt-get -f install -y
  for package in "${PREEXISTING_CONSUMERS[@]}"; do
    if ! package_installed "$package"; then
      removed_consumers+=("$package")
    fi
  done
  if ((${#removed_consumers[@]} > 0)); then
    warn "reinstalando consumidores multimedia removidos: ${removed_consumers[*]}"
    sudo apt-get install -y "${removed_consumers[@]}"
  fi
  sudo apt-get check
  ok 'dependencias multimedia consistentes'
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  capture_preexisting_consumers
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  repair_multimedia_dependencies
  ok 'soporte multimedia instalado'
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
