#!/usr/bin/env bash
# configure_alacritty_macos.sh v1.0.0
# Instala una configuración oscura de Alacritty en macOS sin instalar la app.
set -Eeuo pipefail
umask 077

readonly VERSION="v1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly SOURCE_CONFIG="${REPO_ROOT}/dotfiles/macos/alacritty/alacritty.toml"
readonly TARGET_DIR="${CONFIG_HOME}/alacritty"
readonly TARGET_CONFIG="${TARGET_DIR}/alacritty.toml"
readonly BACKUP_DIR="${HOME}/.local/share/rafex/alacritty-macos/rollback"
readonly BEGIN_MARKER="# BEGIN rafex macOS Alacritty"
readonly END_MARKER="# END rafex macOS Alacritty"

ACTION='check'
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
  configure_alacritty_macos.sh --check
  configure_alacritty_macos.sh --plan
  configure_alacritty_macos.sh --status
  configure_alacritty_macos.sh --apply
  configure_alacritty_macos.sh --rollback

Opciones:
  --check       Valida la plantilla y el entorno sin modificar archivos.
  --plan        Muestra las acciones previstas sin modificar archivos.
  --dry-run     Alias de --plan.
  --status      Muestra el estado de la configuración y del runtime.
  --apply       Instala el perfil oscuro y crea un respaldo fechado.
  --rollback    Restaura el respaldo administrado más reciente.
  --help        Muestra esta ayuda.

Este script solo configura Alacritty. No instala ni actualiza la aplicación,
Homebrew ni Gatekeeper.
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

require_macos_user() {
  [[ "$(uname -s)" == 'Darwin' ]] || die 'este script solo funciona en macOS'
  (( EUID != 0 )) || die 'ejecuta el script como usuario normal'
}

require_commands() {
  local command_name
  for command_name in awk cmp cp date grep install mkdir mktemp mv rm sed; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
}

validate_source() {
  [[ -s "$SOURCE_CONFIG" ]] || die "no existe la plantilla: ${SOURCE_CONFIG}"
  grep -Fqx "$BEGIN_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador inicial'
  grep -Fqx "$END_MARKER" "$SOURCE_CONFIG" || die 'falta el marcador final'
  grep -Fqx 'program = "__RAFEX_LOGIN_SHELL__"' "$SOURCE_CONFIG" || die 'falta el marcador del shell'
  grep -Fqx 'background = "#16181d"' "$SOURCE_CONFIG" || die 'la plantilla no es oscura'
}

target_is_managed() {
  [[ -f "$TARGET_CONFIG" ]] || return 1
  grep -Fqx "$BEGIN_MARKER" "$TARGET_CONFIG" && grep -Fqx "$END_MARKER" "$TARGET_CONFIG"
}

login_shell() {
  local shell_path="${SHELL:-/bin/zsh}"
  [[ -x "$shell_path" ]] || shell_path='/bin/zsh'
  printf '%s\n' "$shell_path"
}

runtime_status() {
  if command -v alacritty >/dev/null 2>&1; then
    printf 'runtime=available\n'
    printf 'runtime_version=%s\n' "$(alacritty --version 2>/dev/null || printf 'N/D')"
  else
    printf 'runtime=missing\n'
  fi
}

show_status() {
  echo '═══ Alacritty macOS: perfil oscuro ═══'
  printf 'versión=%s\n' "$VERSION"
  printf 'fuente=%s\n' "$SOURCE_CONFIG"
  printf 'destino=%s\n' "$TARGET_CONFIG"
  printf 'shell=%s\n' "$(login_shell)"
  runtime_status
  if [[ -f "$TARGET_CONFIG" ]]; then
    if target_is_managed; then
      ok 'configuración administrada presente'
    else
      warn 'existe una configuración manual sin marcadores Rafex'
    fi
  else
    warn 'configuración aún no instalada'
  fi
}

backup_target() {
  local backup_base="${BACKUP_DIR}/alacritty.toml.${TIMESTAMP}"
  mkdir -p "$BACKUP_DIR"
  if [[ -e "$TARGET_CONFIG" ]]; then
    cp -p -- "$TARGET_CONFIG" "${backup_base}.bak"
  else
    : > "${backup_base}.absent"
  fi
  info "respaldo creado bajo ${BACKUP_DIR}"
}

render_config() {
  local destination="$1"
  awk -v shell_path="$(login_shell)" \
    '{ gsub(/__RAFEX_LOGIN_SHELL__/, shell_path); print }' \
    "$SOURCE_CONFIG" > "$destination"
  grep -Fqx "program = \"$(login_shell)\"" "$destination" || die 'no se pudo fijar el shell de inicio'
}

apply_config() {
  local temporary
  validate_source
  mkdir -p "$TARGET_DIR"
  [[ ! -L "$TARGET_CONFIG" ]] || die "${TARGET_CONFIG} es un enlace simbólico; revísalo manualmente"
  temporary="$(mktemp "${TARGET_DIR}/.alacritty.toml.tmp.XXXXXX")"
  trap 'rm -f -- "$temporary"' RETURN
  render_config "$temporary"
  if [[ -f "$TARGET_CONFIG" ]] && cmp -s "$temporary" "$TARGET_CONFIG"; then
    rm -f -- "$temporary"
    trap - RETURN
    ok 'la configuración ya está instalada'
    return 0
  fi
  backup_target
  mv -f -- "$temporary" "$TARGET_CONFIG"
  trap - RETURN
  chmod 600 "$TARGET_CONFIG"
  ok "configuración instalada: ${TARGET_CONFIG}"
  if command -v alacritty >/dev/null 2>&1; then
    ok 'Alacritty está disponible para validar la configuración al abrir una nueva ventana'
  else
    warn 'Alacritty no está instalado; la configuración queda preparada, sin instalar la aplicación'
  fi
}

rollback_config() {
  local latest=''
  local candidate
  for candidate in "$BACKUP_DIR"/alacritty.toml.*; do
    [[ -f "$candidate" ]] || continue
    latest="$candidate"
  done
  [[ -n "$latest" ]] || die "no hay respaldos administrados en ${BACKUP_DIR}"
  mkdir -p "$TARGET_DIR"
  if [[ "$latest" == *.absent ]]; then
    target_is_managed || die 'el destino actual no está administrado; no se eliminará'
    rm -f -- "$TARGET_CONFIG"
    ok 'se restauró el estado anterior: configuración ausente'
  else
    if [[ -e "$TARGET_CONFIG" ]] && ! target_is_managed; then
      die 'el destino actual no está administrado; no se sobrescribirá'
    fi
    cp -p -- "$latest" "$TARGET_CONFIG"
    chmod 600 "$TARGET_CONFIG"
    ok "respaldo restaurado: ${latest}"
  fi
}

main() {
  parse_args "$@"
  require_macos_user
  require_commands
  validate_source
  case "$ACTION" in
    check|status) show_status ;;
    plan)
      show_status
      info '[plan] resolver el shell de inicio del usuario'
      info '[plan] respaldar ~/.config/alacritty/alacritty.toml si existe'
      info '[plan] instalar la plantilla oscura mediante reemplazo atómico'
      info '[plan] no instalar Alacritty, Homebrew ni modificar Gatekeeper'
      ;;
    apply) apply_config ;;
    rollback) rollback_config ;;
    *) die "acción inválida: ${ACTION}" ;;
  esac
}

main "$@"
