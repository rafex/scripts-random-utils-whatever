#!/usr/bin/env bash
# v1.0.0 - Instala input y el respaldo Polkit para el brillo de teclado.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION='check'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_USER="$(id -un)"
readonly HELPER_SOURCE="$REPO_ROOT/scripts/system/kbd_brightness_privileged_linux.sh"
readonly POLICY_SOURCE="$REPO_ROOT/scripts/install/assets/org.rafex.kbd-backlight.policy"
readonly HELPER_TARGET='/usr/local/libexec/rafex-kbd-backlight'
readonly POLICY_TARGET='/etc/polkit-1/actions/org.rafex.kbd-backlight.policy'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_kbd_brightness_policy_linux.sh --check
  install_kbd_brightness_policy_linux.sh --plan
  install_kbd_brightness_policy_linux.sh --apply
  install_kbd_brightness_policy_linux.sh --status

Añade al usuario actual al grupo input y registra un helper Polkit restringido
al LED tpacpi::kbd_backlight. No usa sudo durante el uso diario.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION='check' ;;
      --plan|--dry-run) ACTION='plan' ;;
      --apply) ACTION='apply' ;;
      --status) ACTION='status' ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}"
  command -v id >/dev/null 2>&1 || die 'falta id'
  command -v getent >/dev/null 2>&1 || die 'falta getent'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  [[ -f "$HELPER_SOURCE" ]] || die "falta el helper: $HELPER_SOURCE"
  [[ -f "$POLICY_SOURCE" ]] || die "falta la política: $POLICY_SOURCE"
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

user_in_input() {
  id -nG "$TARGET_USER" | tr ' ' '\n' | grep -Fqx input
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

show_status() {
  echo '═══ Permisos de brillo de teclado ═══'
  if user_in_input; then
    ok "$TARGET_USER pertenece al grupo input"
  else
    warn "$TARGET_USER no pertenece al grupo input"
  fi
  if package_installed pkexec; then ok 'pkexec instalado'; else warn 'pkexec ausente'; fi
  if [[ -x "$HELPER_TARGET" ]]; then
    ok "helper presente: $HELPER_TARGET"
    stat -c '  propietario=%U:%G modo=%a' "$HELPER_TARGET" 2>/dev/null || true
  else
    warn "helper ausente: $HELPER_TARGET"
  fi
  if [[ -f "$POLICY_TARGET" ]]; then
    ok "política Polkit presente: $POLICY_TARGET"
  else
    warn "política Polkit ausente: $POLICY_TARGET"
  fi
  if [[ -e /sys/class/leds/tpacpi::kbd_backlight/brightness ]]; then
    printf 'dispositivo=tpacpi::kbd_backlight actual=%s máximo=%s\n' \
      "$(cat /sys/class/leds/tpacpi::kbd_backlight/brightness)" \
      "$(cat /sys/class/leds/tpacpi::kbd_backlight/max_brightness)"
  else
    warn 'el LED tpacpi::kbd_backlight no está expuesto por el kernel'
  fi
  warn 'el grupo input permite leer eventos de /dev/input/event*; requiere cerrar y abrir sesión'
}

backup_system_file() {
  local target="$1" backup="${1}.bak.${STAMP}"
  if sudo test -e "$target" || sudo test -L "$target"; then
    if ! sudo test -e "$backup" && ! sudo test -L "$backup"; then
      sudo cp -a -- "$target" "$backup"
      info "respaldo creado: $backup"
    fi
  fi
}

install_system_file() {
  local source="$1" target="$2" mode="$3"
  if sudo test -f "$target" && sudo cmp -s "$source" "$target"; then
    return 0
  fi
  backup_system_file "$target"
  sudo install -o root -g root -m "$mode" "$source" "$target"
  ok "instalado: $target"
}

validate_policy() {
  command -v pkexec >/dev/null 2>&1 || die 'pkexec no está disponible'
  command -v pkaction >/dev/null 2>&1 || die 'pkaction no está disponible'
  pkaction --verbose 2>/dev/null | grep -Fq 'org.rafex.kbd-backlight' ||
    warn 'la política aún no aparece en pkaction; puede requerir unos segundos para recargarse'
}

apply_install() {
  local candidate
  sudo -v
  getent group input >/dev/null || die 'el grupo input no existe en este sistema'
  if ! package_installed pkexec; then
    candidate="$(package_candidate pkexec)"
    [[ -n "$candidate" && "$candidate" != '(none)' ]] || die 'pkexec no tiene candidato APT'
    sudo apt-get update
    sudo apt-get install -y pkexec
  fi
  if user_in_input; then
    ok "$TARGET_USER ya pertenece al grupo input"
  else
    sudo usermod -aG input "$TARGET_USER"
    ok "$TARGET_USER añadido al grupo input"
  fi
  sudo install -d -o root -g root -m 0755 /usr/local/libexec
  sudo install -d -o root -g root -m 0755 /etc/polkit-1/actions
  install_system_file "$HELPER_SOURCE" "$HELPER_TARGET" 0755
  install_system_file "$POLICY_SOURCE" "$POLICY_TARGET" 0644
  validate_policy
  ok 'brillo XF86 preparado; cierra y abre sesión para activar el grupo input'
}

main() {
  parse_args "$@"
  require_linux
  case "$ACTION" in
    check|status) show_status ;;
    plan)
      echo '═══ Plan permisos de brillo de teclado ═══'
      info '[plan] instalar pkexec si falta'
      info "[plan] añadir $TARGET_USER al grupo input si falta"
      info "[plan] instalar $HELPER_TARGET y $POLICY_TARGET"
      warn 'no se modificará nada en modo plan'
      ;;
    apply) apply_install ;;
  esac
}

main "$@"
