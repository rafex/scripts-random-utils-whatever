#!/usr/bin/env bash
# configure_thinkpad_xorg_dri3_linux.sh v1.0.0
# Instala una configuración Xorg explícita para modesetting/DRI3 en la ThinkPad.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly VERSION="v1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly SOURCE_CONFIG="${REPO_ROOT}/dotfiles/profiles/thinkpad-x1-yoga-1st/config/X11/xorg.conf.d/20-thinkpad-modesetting.conf"
readonly TARGET_DIR="/etc/X11/xorg.conf.d"
readonly TARGET_CONFIG="${TARGET_DIR}/20-thinkpad-modesetting.conf"
readonly BACKUP_DIR="/var/backups/rafex-thinkpad-xorg"
readonly BEGIN_MARKER="# BEGIN rafex thinkpad dri3"
readonly END_MARKER="# END rafex thinkpad dri3"

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
  configure_thinkpad_xorg_dri3_linux.sh --check
  configure_thinkpad_xorg_dri3_linux.sh --plan
  configure_thinkpad_xorg_dri3_linux.sh --apply
  configure_thinkpad_xorg_dri3_linux.sh --rollback
  configure_thinkpad_xorg_dri3_linux.sh --status

Opciones:
  --check       Comprueba hardware, conflictos y estado sin modificar nada.
  --plan        Muestra las acciones previstas sin modificar nada.
  --dry-run     Alias de --plan.
  --apply       Instala el archivo Xorg explícito y crea un respaldo.
  --rollback    Restaura el respaldo más reciente creado por este instalador.
  --status      Muestra el estado actual sin solicitar sudo.
  --help        Muestra esta ayuda.

La configuración usa el driver modesetting sobre i915, glamor y PageFlip on.
No copia la configuración intel de la MacBook ni reinicia la sesión gráfica.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --rollback) ACTION="rollback"; shift ;;
      --status) ACTION="status"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux_user() {
  [[ "$(uname -s)" == "Linux" ]] || die 'este instalador solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecuta el instalador como usuario normal; sudo se solicita internamente'
}

require_commands() {
  local command_name
  for command_name in awk basename cmp cp date grep install readlink sort tail; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
}

validate_source() {
  [[ -s "$SOURCE_CONFIG" ]] || die "no existe la configuración del perfil: ${SOURCE_CONFIG}"
  grep -Fqx "$BEGIN_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador inicial de la configuración'
  grep -Fqx "$END_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador final de la configuración'
  grep -Fqx '    Driver "modesetting"' "$SOURCE_CONFIG" || die 'la configuración no declara Driver modesetting'
  grep -Fqx '    Option "AccelMethod" "glamor"' "$SOURCE_CONFIG" || die 'falta AccelMethod glamor'
  grep -Fqx '    Option "PageFlip" "on"' "$SOURCE_CONFIG" || die 'falta PageFlip on'
}

kernel_gpu_driver() {
  local driver_link
  for driver_link in /sys/class/drm/card*/device/driver; do
    [[ -e "$driver_link" ]] || continue
    basename -- "$(readlink -- "$driver_link")"
    return 0
  done
  printf '%s\n' 'N/D'
}

gpu_driver_log() {
  local log_file
  for log_file in /var/log/Xorg.0.log "$HOME/.local/share/xorg/Xorg.0.log"; do
    [[ -r "$log_file" ]] || continue
    awk '/Loading .*modules\/drivers\/(modesetting|intel)_drv\.so/ { print; exit }' "$log_file"
    return 0
  done
  return 1
}

unmanaged_gpu_configs() {
  local config_file
  for config_file in /etc/X11/xorg.conf /etc/X11/xorg.conf.d/*.conf; do
    [[ -f "$config_file" ]] || continue
    [[ "$config_file" == "$TARGET_CONFIG" ]] && continue
    if grep -Eqi '^[[:space:]]*Driver[[:space:]]+"(intel|modesetting|amdgpu|nouveau|radeon|vesa|fbdev)"' "$config_file"; then
      printf '%s\n' "$config_file"
    fi
  done
}

target_is_managed() {
  [[ -f "$TARGET_CONFIG" ]] || return 1
  grep -Fqx "$BEGIN_MARKER" "$TARGET_CONFIG" && grep -Fqx "$END_MARKER" "$TARGET_CONFIG"
}

show_status() {
  local driver log_line conflicts
  driver="$(kernel_gpu_driver)"

  echo '═══ Xorg explícito: ThinkPad modesetting/DRI3 ═══'
  printf 'versión=%s\n' "$VERSION"
  printf 'fuente=%s\n' "$SOURCE_CONFIG"
  printf 'destino=%s\n' "$TARGET_CONFIG"
  printf 'driver_kernel=%s\n' "$driver"
  if [[ "$driver" == "i915" ]]; then
    ok 'GPU Intel usa i915'
  elif [[ "$driver" == 'N/D' ]]; then
    warn 'no se pudo detectar el driver DRM; ejecuta el estado desde la ThinkPad'
  else
    warn "driver DRM detectado: ${driver}; no se debe forzar esta configuración"
  fi

  if [[ -f "$TARGET_CONFIG" ]]; then
    if target_is_managed; then
      ok 'archivo Xorg administrado presente'
    else
      warn 'existe un archivo con el mismo nombre, pero no está administrado por Rafex'
    fi
  else
    warn 'archivo Xorg explícito aún no instalado'
  fi

  if log_line="$(gpu_driver_log 2>/dev/null)"; then
    printf 'driver_xorg_activo=%s\n' "$log_line"
  else
    info 'no hay un registro Xorg legible para confirmar el driver de la sesión actual'
  fi

  conflicts="$(unmanaged_gpu_configs)"
  if [[ -n "$conflicts" ]]; then
    warn 'hay configuraciones de GPU no administradas que requieren revisión:'
    printf '  %s\n' "$conflicts" >&2
  else
    ok 'no se detectan archivos Xorg de GPU externos en conflicto'
  fi
}

validate_apply_context() {
  local driver conflicts
  driver="$(kernel_gpu_driver)"
  [[ "$driver" == "i915" ]] || die "se esperaba driver DRM i915; se detectó ${driver}; no se forzará modesetting"
  if [[ -e "$TARGET_CONFIG" ]] && ! target_is_managed; then
    die "${TARGET_CONFIG} existe y no está administrado; no se sobrescribirá"
  fi
  if [[ -L "$TARGET_CONFIG" ]]; then
    die "${TARGET_CONFIG} es un enlace simbólico; revísalo manualmente"
  fi
  conflicts="$(unmanaged_gpu_configs)"
  [[ -z "$conflicts" ]] || die "hay configuraciones de GPU no administradas en conflicto: ${conflicts//$'\n'/, }"
}

require_sudo() {
  command -v sudo >/dev/null 2>&1 || die 'falta sudo para esta operación'
  sudo -v
}

backup_target() {
  local backup_file="${BACKUP_DIR}/20-thinkpad-modesetting.conf.${TIMESTAMP}.bak"
  sudo install -d -m 0700 -- "$BACKUP_DIR"
  sudo cp -p -- "$TARGET_CONFIG" "$backup_file"
  info "respaldo creado: ${backup_file}"
}

apply_config() {
  validate_source
  validate_apply_context

  if [[ -f "$TARGET_CONFIG" ]] && cmp -s "$SOURCE_CONFIG" "$TARGET_CONFIG"; then
    ok 'la configuración Xorg explícita ya está instalada'
    return 0
  fi

  require_sudo
  sudo install -d -m 0755 -- "$TARGET_DIR"
  if sudo test -e "$TARGET_CONFIG"; then
    backup_target
  fi
  sudo install -o root -g root -m 0644 -- "$SOURCE_CONFIG" "$TARGET_CONFIG"
  sudo cmp -s "$SOURCE_CONFIG" "$TARGET_CONFIG" || die 'la validación del archivo instalado falló'
  ok "configuración instalada: ${TARGET_CONFIG}"
  warn 'Xorg leerá este archivo en el próximo reinicio de la sesión gráfica; no se reinició LightDM'
}

rollback_config() {
  local candidate latest backup_files=()
  for candidate in "$BACKUP_DIR"/20-thinkpad-modesetting.conf.*.bak; do
    [[ -f "$candidate" ]] || continue
    backup_files+=("$candidate")
  done
  ((${#backup_files[@]} > 0)) || die "no hay respaldos disponibles en ${BACKUP_DIR}"
  latest="$(printf '%s\n' "${backup_files[@]}" | sort | tail -n 1)"
  require_sudo
  if [[ -e "$TARGET_CONFIG" ]] && ! target_is_managed; then
    die "${TARGET_CONFIG} no está administrado; no se sobrescribirá durante rollback"
  fi
  sudo install -o root -g root -m 0644 -- "$latest" "$TARGET_CONFIG"
  ok "respaldo restaurado: ${latest}"
  warn 'Xorg leerá el rollback en el próximo reinicio de la sesión gráfica'
}

main() {
  parse_args "$@"
  require_linux_user
  require_commands
  validate_source

  case "$ACTION" in
    check|status)
      show_status
      ;;
    plan)
      show_status
      info '[plan] validar que la ThinkPad use i915'
      info "[plan] detectar conflictos en ${TARGET_DIR}"
      info "[plan] respaldar ${TARGET_CONFIG} si existe"
      info '[plan] instalar como root:root con permisos 0644'
      info '[plan] no reiniciar LightDM ni modificar Picom, Mesa, GRUB o el kernel'
      ;;
    apply)
      apply_config
      ;;
    rollback)
      rollback_config
      ;;
    *)
      die "acción inválida: ${ACTION}"
      ;;
  esac
}

main "$@"
