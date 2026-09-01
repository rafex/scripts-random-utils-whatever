#!/usr/bin/env bash
# Instala ClamAV y, opcionalmente, configura el escaneo USB tras udiskie.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
AUTO_USB=0
DISABLE_AUTO_USB=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCANNER_SOURCE="$REPO_ROOT/scripts/system/scan_usb_clamav_linux.sh"
SCANNER_TARGET="$HOME/.local/bin/scan-usb-clamav.sh"
UDISKIE_CONFIG="$HOME/.config/udiskie/config.yml"
STAMP="$(date +%Y%m%d_%H%M%S)"
readonly -a PACKAGES=(clamav clamav-daemon clamav-freshclam clamtk)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_antivirus_linux.sh [--check|--plan|--apply|--status]
  [--auto-usb] [--disable-auto-usb]

Instala ClamAV, su daemon, FreshClam y ClamTk. El escaneo USB es manual por
defecto. --auto-usb configura el event-hook de udiskie como opt-in.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --auto-usb) AUTO_USB=1 ;;
      --disable-auto-usb) DISABLE_AUTO_USB=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  ((AUTO_USB == 0 || DISABLE_AUTO_USB == 0)) || die 'no combines --auto-usb con --disable-auto-usb'
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
    [[ -f "$SCANNER_SOURCE" ]] || die "falta el escáner del repositorio: $SCANNER_SOURCE"
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

auto_hook_present() {
  grep -Fqx '# BEGIN rafex clamav usb' "$UDISKIE_CONFIG" 2>/dev/null
}

clamav_database_ready() {
  local main_file daily_file main_ready=0 daily_ready=0
  for main_file in /var/lib/clamav/main.cvd /var/lib/clamav/main.cld /var/lib/clamav/main.inc; do
    [[ -e "$main_file" ]] && main_ready=1
  done
  for daily_file in /var/lib/clamav/daily.cvd /var/lib/clamav/daily.cld /var/lib/clamav/daily.inc; do
    [[ -e "$daily_file" ]] && daily_ready=1
  done
  ((main_ready == 1 && daily_ready == 1))
}

wait_for_clamav_database() {
  local deadline=$((SECONDS + 30))
  while ! clamav_database_ready; do
    ((SECONDS >= deadline)) && return 1
    sleep 1
  done
  return 0
}

report() {
  local package candidate service
  printf '═══ Antivirus ClamAV ═══\n'
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      printf '✓ %-20s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-20s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
  if command -v clamscan >/dev/null 2>&1; then
    ok 'clamscan disponible'
  else
    warn 'clamscan no está disponible'
  fi
  if command -v clamdscan >/dev/null 2>&1; then
    ok 'clamdscan disponible'
  else
    warn 'clamdscan no está disponible (lo proporciona clamav-daemon)'
  fi
  for service in clamav-freshclam.service clamav-daemon.service; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      ok "$service activo"
    else
      warn "$service inactivo o no verificable"
    fi
  done
  if auto_hook_present; then
    ok 'escaneo automático de USB configurado en udiskie'
  else
    info 'escaneo automático de USB desactivado; se usa scan-usb manual'
  fi
  if systemctl is-enabled --quiet clamav-clamonacc.service 2>/dev/null; then
    warn 'clamonacc está habilitado; la política del perfil recomienda mantenerlo desactivado'
  else
    ok 'clamonacc no está habilitado'
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
  ((missing == 0)) || die 'algún paquete ClamAV no tiene candidato APT'
}

backup_if_needed() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "${target}.bak.${STAMP}"
  info "respaldo creado: ${target}.bak.${STAMP}"
}

install_scanner() {
  mkdir -p "$(dirname "$SCANNER_TARGET")"
  if [[ -f "$SCANNER_TARGET" ]] && cmp -s "$SCANNER_SOURCE" "$SCANNER_TARGET"; then
    return 0
  fi
  backup_if_needed "$SCANNER_TARGET"
  install -m 0755 "$SCANNER_SOURCE" "$SCANNER_TARGET"
  ok "escáner instalado: $SCANNER_TARGET"
}

update_udiskie_hook() {
  local enable="$1" temp hook
  mkdir -p "$(dirname "$UDISKIE_CONFIG")"
  hook="$SCANNER_TARGET --auto-event {event}"
  temp="$(mktemp "${UDISKIE_CONFIG}.tmp.XXXXXX")"
  if [[ -f "$UDISKIE_CONFIG" ]]; then
    awk '
      /# BEGIN rafex clamav usb/ { skip=1; next }
      /# END rafex clamav usb/ { skip=0; next }
      !skip { print }
    ' "$UDISKIE_CONFIG" > "$temp"
  else
    cat > "$temp" <<'EOF'
program_options:
  tray: auto
  automount: true
  notify: true
EOF
  fi
  if ((enable)); then
    if grep -Eq '^[[:space:]]+event_hook:' "$temp"; then
      rm -f -- "$temp"
      die "udiskie ya tiene un event_hook no administrado; revísalo antes de usar --auto-usb"
    fi
    awk -v hook="$hook" '
      function block() {
        print "  # BEGIN rafex clamav usb"
        print "  event_hook: \"" hook "\""
        print "  # END rafex clamav usb"
        inserted=1
      }
      /^program_options:[[:space:]]*$/ { in_program=1; print; next }
      /^[^[:space:]][^:]*:/ {
        if (in_program && !inserted) block()
        in_program=0
      }
      /^device_config:[[:space:]]*$/ && !inserted { block() }
      { print }
      END {
        if (in_program && !inserted) block()
        if (!inserted) {
          print "program_options:"
          block()
        }
      }
    ' "$temp" > "${temp}.next"
    mv -f -- "${temp}.next" "$temp"
  fi
  if [[ -f "$UDISKIE_CONFIG" ]] && cmp -s "$temp" "$UDISKIE_CONFIG"; then
    rm -f -- "$temp"
    return 0
  fi
  backup_if_needed "$UDISKIE_CONFIG"
  install -m 0644 "$temp" "$UDISKIE_CONFIG"
  rm -f -- "$temp"
  if ((enable)); then
    ok 'event-hook de ClamAV añadido a udiskie'
  else
    ok 'event-hook automático de ClamAV retirado de udiskie'
  fi
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  sudo systemctl enable --now clamav-freshclam.service
  if wait_for_clamav_database; then
    sudo systemctl enable clamav-daemon.service clamav-daemon.socket
    if sudo systemctl restart clamav-daemon.service; then
      ok 'clamav-daemon iniciado después de confirmar las firmas'
    else
      warn 'clamav-daemon no pudo iniciar; clamscan manual permanece disponible'
    fi
  else
    warn 'las firmas aún no están disponibles; se conserva FreshClam y se omitió el arranque del daemon'
  fi
  install_scanner
  if ((AUTO_USB)); then
    update_udiskie_hook 1
    warn 'reinicia udiskie o abre una nueva sesión para cargar el event-hook'
  elif ((DISABLE_AUTO_USB)); then
    update_udiskie_hook 0
  fi
  ok 'ClamAV instalado; no se habilitó clamonacc'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check|status) report ;;
  plan)
    report
    info "[plan] sudo apt-get update && sudo apt-get install -y ${PACKAGES[*]}"
    info '[plan] habilitar clamav-freshclam y clamav-daemon; no habilitar clamonacc'
    info "[plan] instalar $SCANNER_TARGET"
    ((AUTO_USB)) && info '[plan] añadir event-hook opt-in a udiskie' || true
    ((DISABLE_AUTO_USB)) && info '[plan] retirar event-hook administrado de udiskie' || true
    ;;
  apply) apply_install; report ;;
  *) die "acción no válida: $ACTION" ;;
esac
