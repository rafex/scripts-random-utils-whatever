#!/usr/bin/env bash
# configure_thinkpad_touchpad_linux.sh v1.0.0
# Configura scroll natural persistente para el touchpad libinput de la ThinkPad.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly VERSION="v1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly SOURCE_CONFIG="${REPO_ROOT}/dotfiles/profiles/thinkpad-x1-yoga-1st/config/X11/xorg.conf.d/40-rafex-libinput-touchpad.conf"
readonly TARGET_DIR="/etc/X11/xorg.conf.d"
readonly TARGET_CONFIG="${TARGET_DIR}/40-rafex-libinput-touchpad.conf"
readonly BACKUP_DIR="/var/backups/rafex-thinkpad-xorg"
readonly BEGIN_MARKER="# BEGIN rafex thinkpad touchpad natural scrolling"
readonly END_MARKER="# END rafex thinkpad touchpad natural scrolling"

ACTION="check"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_thinkpad_touchpad_linux.sh --check
  configure_thinkpad_touchpad_linux.sh --plan
  configure_thinkpad_touchpad_linux.sh --status
  configure_thinkpad_touchpad_linux.sh --apply
  configure_thinkpad_touchpad_linux.sh --rollback

Opciones:
  --check       Valida la plantilla y detecta conflictos sin modificar nada.
  --plan        Muestra las acciones previstas sin modificar nada.
  --dry-run     Alias de --plan.
  --status      Muestra el archivo instalado y la propiedad XInput actual.
  --apply       Instala la regla Xorg y guarda un respaldo administrado.
  --rollback    Restaura el respaldo administrado más reciente.
  --help        Muestra esta ayuda.

La regla solo afecta dispositivos que Xorg identifica como touchpad. No
modifica el TrackPoint ni ratones externos. La sesión gráfica debe cerrarse y
abrirse de nuevo para que Xorg lea el archivo.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --status) ACTION='status'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --rollback) ACTION='rollback'; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux_user() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecuta el script como usuario normal; sudo se solicita internamente'
}

require_commands() {
  local command_name
  for command_name in awk basename cmp cp date grep install readlink rm sort tail; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
}

validate_source() {
  [[ -s "$SOURCE_CONFIG" ]] || die "no existe la configuración: ${SOURCE_CONFIG}"
  grep -Fqx "$BEGIN_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador inicial'
  grep -Fqx "$END_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador final'
  grep -Fqx '    MatchIsTouchpad "on"' "$SOURCE_CONFIG" || die 'falta MatchIsTouchpad'
  grep -Fqx '    Driver "libinput"' "$SOURCE_CONFIG" || die 'falta Driver libinput'
  grep -Fqx '    Option "NaturalScrolling" "true"' "$SOURCE_CONFIG" || die 'falta NaturalScrolling true'
  grep -Fqx '    Option "ScrollMethod" "twofinger"' "$SOURCE_CONFIG" || die 'falta ScrollMethod twofinger'
}

target_is_managed() {
  [[ -f "$TARGET_CONFIG" ]] || return 1
  grep -Fqx "$BEGIN_MARKER" "$TARGET_CONFIG" && grep -Fqx "$END_MARKER" "$TARGET_CONFIG"
}

unmanaged_touchpad_configs() {
  local config_file
  for config_file in /etc/X11/xorg.conf "$TARGET_DIR"/*.conf; do
    [[ -f "$config_file" ]] || continue
    [[ "$config_file" == "$TARGET_CONFIG" ]] && continue
    if grep -Eqi '^[[:space:]]*(MatchIsTouchpad|NaturalScrolling|Driver[[:space:]]+"libinput")' "$config_file"; then
      printf '%s\n' "$config_file"
    fi
  done
}

current_natural_scrolling() {
  local output
  command -v xinput >/dev/null 2>&1 || {
    printf '%s\n' 'N/D (falta xinput)'
    return 0
  }
  [[ -n "${DISPLAY:-}" ]] || {
    printf '%s\n' 'N/D (DISPLAY no disponible)'
    return 0
  }
  output="$(xinput list-props 'SynPS/2 Synaptics TouchPad' 2>/dev/null || true)"
  if [[ -z "$output" ]]; then
    printf '%s\n' 'N/D (touchpad no visible en esta sesión)'
  else
    awk -F': ' '/Natural Scrolling Enabled \(/ { print $2; found=1; exit } END { if (!found) print "N/D" }' <<<"$output"
  fi
}

show_status() {
  local conflicts
  echo "═══ Touchpad ThinkPad: scroll natural ═══"
  printf 'versión=%s\n' "$VERSION"
  printf 'fuente=%s\n' "$SOURCE_CONFIG"
  printf 'destino=%s\n' "$TARGET_CONFIG"
  printf 'natural_scrolling_actual=%s\n' "$(current_natural_scrolling)"
  if [[ -f "$TARGET_CONFIG" ]]; then
    if target_is_managed; then
      ok 'regla Xorg administrada presente'
    else
      warn 'existe el destino, pero no está administrado por Rafex'
    fi
  else
    warn 'regla Xorg aún no instalada'
  fi
  conflicts="$(unmanaged_touchpad_configs)"
  if [[ -n "$conflicts" ]]; then
    warn 'se detectan archivos Xorg relacionados que requieren revisión:'
    printf '  %s\n' "$conflicts" >&2
  else
    ok 'no se detectan reglas Xorg externas relacionadas'
  fi
}

validate_apply_context() {
  local conflicts
  if [[ -e "$TARGET_CONFIG" ]] && ! target_is_managed; then
    die "${TARGET_CONFIG} existe y no está administrado; no se sobrescribirá"
  fi
  [[ ! -L "$TARGET_CONFIG" ]] || die "${TARGET_CONFIG} es un enlace simbólico; revísalo manualmente"
  conflicts="$(unmanaged_touchpad_configs)"
  [[ -z "$conflicts" ]] || die "hay reglas Xorg relacionadas no administradas: ${conflicts//$'\n'/, }"
}

require_sudo() {
  command -v sudo >/dev/null 2>&1 || die 'falta sudo'
  sudo -v
}

backup_target() {
  local backup_base="${BACKUP_DIR}/40-rafex-libinput-touchpad.conf.${TIMESTAMP}"
  sudo install -d -m 0700 -- "$BACKUP_DIR"
  if sudo test -e "$TARGET_CONFIG"; then
    sudo cp -p -- "$TARGET_CONFIG" "${backup_base}.bak"
  else
    sudo touch "${backup_base}.absent"
  fi
  info "respaldo creado bajo ${BACKUP_DIR}"
}

apply_config() {
  validate_source
  validate_apply_context
  [[ ! -L "$TARGET_CONFIG" ]] || die "${TARGET_CONFIG} es un enlace simbólico; revísalo manualmente"
  if [[ -f "$TARGET_CONFIG" ]] && cmp -s "$SOURCE_CONFIG" "$TARGET_CONFIG"; then
    ok 'la regla Xorg ya está instalada'
    return 0
  fi
  require_sudo
  backup_target
  sudo install -d -m 0755 -- "$TARGET_DIR"
  sudo install -o root -g root -m 0644 -- "$SOURCE_CONFIG" "$TARGET_CONFIG"
  sudo cmp -s "$SOURCE_CONFIG" "$TARGET_CONFIG" || die 'la validación del archivo instalado falló'
  ok "regla instalada: ${TARGET_CONFIG}"
  warn 'cierra y abre la sesión gráfica; no se reinició Xorg automáticamente'
}

rollback_config() {
  local latest candidate
  latest=''
  for candidate in "$BACKUP_DIR"/40-rafex-libinput-touchpad.conf.*; do
    [[ -f "$candidate" ]] || continue
    latest="$candidate"
  done
  [[ -n "$latest" ]] || die "no hay respaldos administrados en ${BACKUP_DIR}"
  require_sudo
  if [[ "$latest" == *.absent ]]; then
    target_is_managed || die 'el destino actual no está administrado; no se eliminará'
    sudo rm -f -- "$TARGET_CONFIG"
    ok 'se restauró el estado anterior: regla ausente'
  else
    if [[ -e "$TARGET_CONFIG" ]] && ! target_is_managed; then
      die 'el destino actual no está administrado; no se sobrescribirá'
    fi
    sudo install -o root -g root -m 0644 -- "$latest" "$TARGET_CONFIG"
    ok "respaldo restaurado: ${latest}"
  fi
  warn 'la sesión gráfica debe reiniciarse para leer el rollback'
}

main() {
  parse_args "$@"
  require_linux_user
  require_commands
  validate_source
  case "$ACTION" in
    check|status) show_status ;;
    plan)
      show_status
      info "[plan] detectar conflictos en ${TARGET_DIR}"
      info "[plan] respaldar ${TARGET_CONFIG} si existe y registrar si estaba ausente"
      info '[plan] instalar como root:root con permisos 0644'
      info '[plan] no reiniciar Xorg ni cambiar TrackPoint o mouse externo'
      ;;
    apply) apply_config ;;
    rollback) rollback_config ;;
    *) die "acción inválida: ${ACTION}" ;;
  esac
}

main "$@"
