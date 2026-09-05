#!/usr/bin/env bash
# picom_debian_linux.sh v1.0.0
# Usa el Picom de Debian con la configuración visual versionada de Rafex.
# shellcheck shell=bash
set -Eeuo pipefail
umask 077

ACTION=check
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_PICOM_BIN=/usr/bin/picom
CONFIG_SOURCE="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/picom.conf"
SHADER_SOURCE_DIR="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/shaders"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/picom"
CONFIG_TARGET="$CONFIG_DIR/picom.conf"
SHADER_TARGET_DIR="$CONFIG_DIR/shaders"
MANIFEST_TARGET="$CONFIG_DIR/.rafex-picom-debian-managed"
TOGGLE_SOURCE="$REPO_ROOT/scripts/system/picom_toggle_linux.sh"
SHADER_FILES=(neutral.glsl nord.glsl paper.glsl everforest.glsl dracula.glsl)
CONFIG_MARKER='# Managed by rafex install_picom_upstream_linux.sh'
MANIFEST_MARKER='managed by rafex picom-debian'
CHOSEN=false

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  picom_debian_linux.sh --check|--plan|--apply|--status
  picom_debian_linux.sh --enable|--disable|--toggle|--reload

Acciones:
  --check       comprobar /usr/bin/picom y fuentes sin escribir
  --plan        mostrar los destinos y el comando previsto
  --apply       instalar la configuración y los shaders versionados
  --status      mostrar versión, configuración y estado del proceso
  --enable      iniciar /usr/bin/picom con la configuración administrada
  --disable     detener la instancia de picom y desactivar su autoinicio
  --toggle      alternar picom usando /usr/bin/picom
  --reload      reiniciar picom para cargar la configuración actual
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--apply|--status|--enable|--disable|--toggle|--reload)
        [[ "$CHOSEN" == false ]] || die 'selecciona una sola acción'
        ACTION="${1#--}"
        CHOSEN=true
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_base() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper requiere Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
  [[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
  [[ -x "$SYSTEM_PICOM_BIN" ]] || die "falta el Picom de Debian: $SYSTEM_PICOM_BIN"
  [[ -f "$CONFIG_SOURCE" ]] || die "falta la configuración versionada: $CONFIG_SOURCE"
  [[ -d "$SHADER_SOURCE_DIR" ]] || die "falta el directorio de shaders: $SHADER_SOURCE_DIR"
  [[ -f "$TOGGLE_SOURCE" ]] || die "falta el helper de control: $TOGGLE_SOURCE"
  command -v pgrep >/dev/null 2>&1 || die 'falta pgrep'
  local shader_file
  for shader_file in "${SHADER_FILES[@]}"; do
    [[ -f "$SHADER_SOURCE_DIR/$shader_file" ]] \
      || die "falta el shader versionado: $SHADER_SOURCE_DIR/$shader_file"
  done
}

running() { pgrep -x picom >/dev/null 2>&1; }

show_version() {
  "$SYSTEM_PICOM_BIN" --version | head -n 1
}

show_targets() {
  printf 'binario: %s — ' "$SYSTEM_PICOM_BIN"
  show_version
  printf 'configuración fuente: %s\n' "$CONFIG_SOURCE"
  printf 'configuración activa: %s\n' "$CONFIG_TARGET"
  printf 'shaders activos: %s\n' "$SHADER_TARGET_DIR"
  printf 'instancia: %s\n' "$(if running; then echo activa; else echo detenida; fi)"
}

show_plan() {
  printf '═══ Picom Debian + configuración Rafex ═══\n'
  show_targets
  printf '%s\n' "acción apply: copiar picom.conf y ${#SHADER_FILES[@]} shaders de forma atómica"
  printf '%s\n' 'acción enable: /usr/bin/picom --config ~/.config/picom/picom.conf'
  printf '%s\n' 'No compila, no instala paquetes, no usa sudo y no reemplaza /usr/bin/picom.'
}

show_status() {
  printf '═══ Estado Picom Debian + Rafex ═══\n'
  printf 'binario: %s — ' "$SYSTEM_PICOM_BIN"
  show_version
  if [[ -f "$CONFIG_TARGET" ]]; then
    ok "configuración instalada: $CONFIG_TARGET"
  else
    warn "configuración ausente: $CONFIG_TARGET"
  fi
  if [[ -f "$MANIFEST_TARGET" ]] && grep -Fqx "$MANIFEST_MARKER" "$MANIFEST_TARGET"; then
    ok 'manifest de configuración administrada presente'
  else
    warn 'manifest de configuración administrada ausente'
  fi
  local shader_file
  for shader_file in "${SHADER_FILES[@]}"; do
    if [[ -f "$SHADER_TARGET_DIR/$shader_file" ]]; then
      ok "shader presente: $shader_file"
    else
      warn "shader ausente: $shader_file"
    fi
  done
  if running; then
    ok 'picom está ejecutándose'
    ps -o args= -p "$(pgrep -x picom | head -n 1)" 2>/dev/null || true
  else
    info 'picom está detenido'
  fi
}

managed_target_allowed() {
  local source="$1" target="$2"
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -f "$target" && ! -L "$target" ]] || die "el destino no es un archivo regular: $target"
  cmp -s "$source" "$target" && return 0
  if [[ "$target" == "$CONFIG_TARGET" ]] && grep -Fq "$CONFIG_MARKER" "$target"; then
    return 0
  fi
  if [[ -f "$MANIFEST_TARGET" ]] && grep -Fqx "$MANIFEST_MARKER" "$MANIFEST_TARGET"; then
    return 0
  fi
  die "se rehúsa sobrescribir una configuración no administrada: $target"
}

declare -a REPLACED_TARGETS=()
declare -a REPLACED_BACKUPS=()

rollback_replacements() {
  local index target backup
  set +e
  for index in "${!REPLACED_TARGETS[@]}"; do
    target="${REPLACED_TARGETS[$index]}"
    backup="${REPLACED_BACKUPS[$index]}"
    if [[ -n "$backup" && -e "$backup" ]]; then
      mv -f -- "$backup" "$target"
    else
      rm -f -- "$target"
    fi
  done
  warn 'la instalación de Picom se revirtió; no se iniciaron procesos'
}

atomic_install() {
  local source="$1" target="$2" mode="$3" temporary backup=''
  if [[ -e "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  install -m "$mode" -- "$source" "$temporary"
  if [[ -e "$target" ]]; then
    backup="$target.bak.$STAMP"
    cp -a -- "$target" "$backup"
    info "respaldo: $backup"
  fi
  REPLACED_TARGETS+=("$target")
  REPLACED_BACKUPS+=("$backup")
  mv -f -- "$temporary" "$target"
}

apply_configuration() {
  local shader_file
  managed_target_allowed "$CONFIG_SOURCE" "$CONFIG_TARGET"
  for shader_file in "${SHADER_FILES[@]}"; do
    managed_target_allowed "$SHADER_SOURCE_DIR/$shader_file" "$SHADER_TARGET_DIR/$shader_file"
  done

  mkdir -p -- "$CONFIG_DIR" "$SHADER_TARGET_DIR"
  trap 'rollback_replacements' ERR
  atomic_install "$CONFIG_SOURCE" "$CONFIG_TARGET" 0644
  for shader_file in "${SHADER_FILES[@]}"; do
    atomic_install "$SHADER_SOURCE_DIR/$shader_file" "$SHADER_TARGET_DIR/$shader_file" 0644
  done
  local manifest_temporary
  manifest_temporary="$(mktemp "${MANIFEST_TARGET}.tmp.XXXXXX")"
  printf '%s\n' "$MANIFEST_MARKER" > "$manifest_temporary"
  atomic_install "$manifest_temporary" "$MANIFEST_TARGET" 0600
  rm -f -- "$manifest_temporary"
  trap - ERR
  ok 'configuración y shaders de Picom instalados'
  info 'Picom no se reinició automáticamente; usa --reload cuando estés listo'
}

require_active_configuration() {
  [[ -f "$CONFIG_TARGET" ]] || die "falta $CONFIG_TARGET; ejecuta --apply"
  [[ -f "$SHADER_TARGET_DIR/nord.glsl" ]] || die "falta el shader activo; ejecuta --apply"
}

control_picom() {
  local action="$1"
  require_active_configuration
  PICOM_BIN="$SYSTEM_PICOM_BIN" PICOM_CONFIG="$CONFIG_TARGET" \
    bash "$TOGGLE_SOURCE" "--$action"
}

main() {
  parse_args "$@"
  require_base
  case "$ACTION" in
    check)
      show_plan
      ok 'Picom de Debian disponible; no se compilará upstream'
      ;;
    plan) show_plan ;;
    status) show_status ;;
    apply) apply_configuration ;;
    enable|disable|toggle) control_picom "$ACTION" ;;
    reload)
      control_picom disable
      control_picom enable
      ;;
  esac
}

main "$@"
