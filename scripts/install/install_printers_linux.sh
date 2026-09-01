#!/usr/bin/env bash
# v1.0.0 - Instala CUPS, SANE y controladores Debian para impresoras locales.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PACKAGES=(
  cups
  cups-client
  cups-daemon
  cups-filters
  printer-driver-escpr
  printer-driver-splix
  libsane1
  sane-utils
  sane-airscan
  ipp-usb
  simple-scan
  avahi-utils
)

usage() {
  cat <<'EOF'
Uso: install_printers_linux.sh [--check|--plan|--apply|--status]

Instala CUPS/SANE y los controladores Debian para Epson XP-241 y Xerox Phaser
3020. No crea colas ni comparte impresoras; eso se realiza con
configure_printers_linux.sh.
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
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null \
    | awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
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
    package_installed "$package_name" && continue
    candidate="$(package_candidate "$package_name")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package_name"
      missing=1
    fi
  done
  (( missing == 0 )) || die 'faltan candidatos APT; revisa las fuentes Debian'
}

show_cups_status() {
  if command -v systemctl >/dev/null 2>&1 \
    && systemctl is-active --quiet cups.service 2>/dev/null; then
    ok 'cups.service activo'
  else
    warn 'cups.service no está activo'
  fi
  if command -v systemctl >/dev/null 2>&1 \
    && systemctl is-enabled --quiet cups.service 2>/dev/null; then
    ok 'cups.service habilitado al arrancar'
  else
    warn 'cups.service no está habilitado al arrancar'
  fi
  if command -v lpstat >/dev/null 2>&1; then
    if lpstat -r 2>/dev/null | grep -qi 'running\|ejecutándose\|activo'; then
      ok 'planificador CUPS responde'
    else
      warn 'el planificador CUPS no responde'
    fi
  else
    warn 'lpstat no está disponible'
  fi
  if [[ -r /etc/cups/cupsd.conf ]]; then
    if grep -Eq '^[[:space:]]*Listen[[:space:]]+localhost:631|^[[:space:]]*Listen[[:space:]]+/run/cups/cups.sock' /etc/cups/cupsd.conf; then
      ok 'CUPS conserva escucha local'
    else
      info 'revisa manualmente /etc/cups/cupsd.conf si necesitas confirmar escucha local'
    fi
    if grep -Eq '^[[:space:]]*(Allow|BrowseAllow|Listen)[[:space:]]+all' /etc/cups/cupsd.conf; then
      warn 'CUPS contiene una directiva amplia; no fue modificada por este script'
    else
      ok 'no se detecta una directiva CUPS explícita de acceso global'
    fi
  fi
}

apply_installation() {
  command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  validate_packages
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  info "instalando: ${PACKAGES[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${PACKAGES[@]}"
  info 'habilitando CUPS; no se habilitará cups-browsed ni se compartirán impresoras'
  sudo systemctl enable --now cups.service
  show_cups_status
}

show_status() {
  printf '═══ Impresión y escaneo ═══\n'
  report_packages
  show_cups_status
  if command -v lpstat >/dev/null 2>&1; then
    lpstat -p -d 2>/dev/null || true
  fi
  if command -v scanimage >/dev/null 2>&1; then
    info 'dispositivos SANE visibles:'
    scanimage -L 2>/dev/null || true
  fi
  info 'las colas se crean con configure-printers; no se habilitó saned ni CUPS remoto'
}

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

require_linux_debian

case "$ACTION" in
  check)
    printf '═══ Check impresión/escaneo ═══\n'
    report_packages
    show_cups_status
    ;;
  plan)
    printf '═══ Plan impresión/escaneo ═══\n'
    validate_packages
    info "instalar: ${PACKAGES[*]}"
    info 'habilitar cups.service y conservar CUPS local'
    info 'no crear colas, no habilitar saned, no compartir impresoras y no abrir UFW'
    info 'no se escribirá nada en modo plan'
    ;;
  apply) apply_installation ;;
  status) show_status ;;
esac
