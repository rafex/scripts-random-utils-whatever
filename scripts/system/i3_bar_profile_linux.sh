#!/usr/bin/env bash
# shellcheck shell=bash
# Selecciona el único perfil de barra administrado para i3.
set -Eeuo pipefail
umask 077

ACTION=check
REQUESTED_MODE=''
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BAR_SOURCE_DIR="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/i3-bars"
BAR_TARGET_DIR="$CONFIG_HOME/rafex/i3-bars"
I3_CONFIG="$CONFIG_HOME/i3/config"
ACTIVE_CONFIG="$CONFIG_HOME/i3/rafex-bar-active.conf"
STATE_FILE="$CONFIG_HOME/rafex/i3-bar-profile"
RUNTIME_SOURCE="$REPO_ROOT/scripts/system/rafex_i3_bar_runtime_linux.sh"
RUNTIME_TARGET="$HOME/.local/bin/rafex-i3-bar-runtime.sh"
SELECTOR_SOURCE="$REPO_ROOT/scripts/system/i3_bar_profile_linux.sh"
SELECTOR_TARGET="$HOME/.local/bin/i3-bar-profile.sh"
MODES=(i3bar tint2 polybar)

if [[ ! -d "$BAR_SOURCE_DIR" && -d "$BAR_TARGET_DIR" ]]; then
  BAR_SOURCE_DIR="$BAR_TARGET_DIR"
fi
if [[ ! -f "$RUNTIME_SOURCE" && -f "$RUNTIME_TARGET" ]]; then
  RUNTIME_SOURCE="$RUNTIME_TARGET"
fi
if [[ ! -f "$SELECTOR_SOURCE" && -f "$SELECTOR_TARGET" ]]; then
  SELECTOR_SOURCE="$SELECTOR_TARGET"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  i3_bar_profile_linux.sh --check
  i3_bar_profile_linux.sh --plan [--set i3bar|tint2|polybar]
  i3_bar_profile_linux.sh --status
  i3_bar_profile_linux.sh --set i3bar|tint2|polybar
  i3_bar_profile_linux.sh --reload
  i3_bar_profile_linux.sh --rollback
EOF
}

parse_args() {
  local chosen=0
  while (($#)); do
    case "$1" in
      --check|--plan|--status|--reload|--rollback)
        (( chosen == 0 )) || die 'selecciona una sola acción'
        ACTION="${1#--}"; chosen=1; shift ;;
      --set)
        [[ $# -ge 2 ]] || die '--set requiere i3bar, tint2 o polybar'
        REQUESTED_MODE="$2"
        if [[ "${ACTION}" != plan ]]; then
          ACTION='set'
        fi
        chosen=1; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
  [[ -n "$REQUESTED_MODE" ]] || return 0
  case " ${MODES[*]} " in *" $REQUESTED_MODE "*) ;; *) die "perfil inválido: $REQUESTED_MODE" ;; esac
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este selector requiere Linux'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

mode_from_state() {
  local mode='i3bar'
  [[ -f "$STATE_FILE" ]] && mode="$(head -n 1 "$STATE_FILE")"
  case " ${MODES[*]} " in *" $mode "*) printf '%s\n' "$mode" ;; *) printf '%s\n' i3bar ;; esac
}

validate_sources() {
  local file
  [[ -d "$BAR_SOURCE_DIR" ]] || die "falta la fuente de barras: $BAR_SOURCE_DIR"
  for file in i3bar.conf tint2.conf polybar.conf tint2rc polybar.ini; do
    [[ -f "$BAR_SOURCE_DIR/$file" ]] || die "falta $BAR_SOURCE_DIR/$file"
  done
  [[ -f "$RUNTIME_SOURCE" ]] || die "falta el runtime: $RUNTIME_SOURCE"
  [[ -f "$SELECTOR_SOURCE" ]] || die "falta el selector: $SELECTOR_SOURCE"
}

extract_bar_block() {
  awk '
    BEGIN { inside=0; depth=0 }
    !inside && $0 ~ /^[[:space:]]*bar[[:space:]]*\{/ { inside=1 }
    inside {
      line=$0
      opens=gsub(/\{/, "", line)
      closes=gsub(/\}/, "", line)
      depth += opens - closes
      print
      if (depth == 0) exit
    }
  ' "$I3_CONFIG"
}

has_core_bar_block() {
  grep -Eq '^[[:space:]]*bar[[:space:]]*\{' "$I3_CONFIG"
}

validate_i3_layout() {
  local includes block
  [[ -f "$I3_CONFIG" ]] || die "falta la configuración i3: $I3_CONFIG"
  includes="$(grep -Ec '^[[:space:]]*include[[:space:]]+~/.config/i3/rafex-bar-active\.conf[[:space:]]*$' "$I3_CONFIG" || true)"
  (( includes <= 1 )) || die 'i3 contiene inclusiones duplicadas de rafex-bar-active.conf'
  if has_core_bar_block; then
    block="$(extract_bar_block)"
    grep -Fq 'status_command i3status' <<<"$block" || die 'i3 contiene un bloque bar manual/conflictivo'
    grep -Fq 'tray_output primary' <<<"$block" || die 'i3 contiene un bloque bar manual/conflictivo'
    grep -Fq 'theme_bar_bg' <<<"$block" || die 'i3 contiene un bloque bar manual/conflictivo'
    [[ "$includes" -eq 0 ]] || die 'i3 conserva un bar embebido además del include administrado'
    info 'se puede migrar el bloque bar actual administrado al include único'
  fi
}

backup_file() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "${target}.bak.${STAMP}"
  info "respaldo: ${target}.bak.${STAMP}"
}

replace_file() {
  local source="$1" target="$2" temporary
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-bar.XXXXXX")"
  install -m 0644 -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

migrate_i3_config() {
  local temporary block_file includes
  validate_i3_layout
  includes="$(grep -Ec '^[[:space:]]*include[[:space:]]+~/.config/i3/rafex-bar-active\.conf[[:space:]]*$' "$I3_CONFIG" || true)"
  [[ "$includes" -eq 0 ]] || return 0
  temporary="$(mktemp "$(dirname -- "$I3_CONFIG")/.rafex-i3.XXXXXX")"
  if has_core_bar_block; then
    block_file="$(mktemp)"
    extract_bar_block > "$block_file"
    awk -v block_file="$block_file" '
      BEGIN { inside=0; depth=0; inserted=0 }
      !inside && $0 ~ /^[[:space:]]*bar[[:space:]]*\{/ {
        inside=1
        if (!inserted) { print "include ~/.config/i3/rafex-bar-active.conf"; inserted=1 }
      }
      inside {
        line=$0
        opens=gsub(/\{/, "", line)
        closes=gsub(/\}/, "", line)
        depth += opens - closes
        if (depth == 0) inside=0
        next
      }
      { print }
      END { if (!inserted) print "include ~/.config/i3/rafex-bar-active.conf" }
    ' "$I3_CONFIG" > "$temporary"
    rm -f -- "$block_file"
  else
    { cat "$I3_CONFIG"; printf '\ninclude ~/.config/i3/rafex-bar-active.conf\n'; } > "$temporary"
  fi
  if ! cmp -s "$I3_CONFIG" "$temporary"; then
    backup_file "$I3_CONFIG"
    chmod --reference="$I3_CONFIG" "$temporary" 2>/dev/null || true
    mv -f -- "$temporary" "$I3_CONFIG"
  else
    rm -f -- "$temporary"
  fi
}

install_materialized_files() {
  local file
  for file in i3bar.conf tint2.conf polybar.conf tint2rc polybar.ini; do
    if [[ "$ACTION" == plan ]]; then
      info "[plan] instalar $BAR_TARGET_DIR/$file"
    else
      if [[ -f "$BAR_TARGET_DIR/$file" ]] && cmp -s "$BAR_SOURCE_DIR/$file" "$BAR_TARGET_DIR/$file"; then
        continue
      fi
      backup_file "$BAR_TARGET_DIR/$file"
      replace_file "$BAR_SOURCE_DIR/$file" "$BAR_TARGET_DIR/$file"
    fi
  done
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $RUNTIME_TARGET y $SELECTOR_TARGET"
  else
    mkdir -p -- "$HOME/.local/bin"
    if [[ ! -f "$RUNTIME_TARGET" ]] || ! cmp -s "$RUNTIME_SOURCE" "$RUNTIME_TARGET"; then
      backup_file "$RUNTIME_TARGET"
      install -m 0755 -- "$RUNTIME_SOURCE" "$RUNTIME_TARGET"
    fi
    if [[ ! -f "$SELECTOR_TARGET" ]] || ! cmp -s "$SELECTOR_SOURCE" "$SELECTOR_TARGET"; then
      backup_file "$SELECTOR_TARGET"
      install -m 0755 -- "$SELECTOR_SOURCE" "$SELECTOR_TARGET"
    fi
  fi
}

ensure_active_file() {
  local mode source
  mode="$(mode_from_state)"
  source="$BAR_TARGET_DIR/$mode.conf"
  [[ -f "$source" ]] || die "falta plantilla materializada para $mode: $source"
  if [[ -e "$ACTIVE_CONFIG" ]] && ! grep -Fq '# Managed by rafex i3 bar profiles' "$ACTIVE_CONFIG"; then
    die "se rehúsa sobrescribir un active bar no administrado: $ACTIVE_CONFIG"
  fi
  if [[ "$ACTION" == plan ]]; then
    info "[plan] activar $mode mediante $ACTIVE_CONFIG"
  else
    if [[ -f "$ACTIVE_CONFIG" ]] && cmp -s "$source" "$ACTIVE_CONFIG"; then
      return 0
    fi
    backup_file "$ACTIVE_CONFIG"
    replace_file "$source" "$ACTIVE_CONFIG"
  fi
}

install_polybar_if_needed() {
  [[ "$REQUESTED_MODE" == polybar ]] || return 0
  package_installed polybar && return 0
  if [[ "$ACTION" == plan ]]; then
    info '[plan] sudo apt-get update && sudo apt-get install -y polybar'
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die 'sudo es necesario para instalar Polybar desde Debian'
  sudo -v
  sudo apt-get update
  sudo apt-get install -y polybar
}

show_status() {
  local mode
  printf 'source=%s\n' "$BAR_SOURCE_DIR"
  printf 'target=%s\n' "$BAR_TARGET_DIR"
  printf 'active=%s\n' "$ACTIVE_CONFIG"
  printf 'selected=%s\n' "$(mode_from_state)"
  if [[ -f "$ACTIVE_CONFIG" ]] && grep -Fq '# Managed by rafex i3 bar profiles' "$ACTIVE_CONFIG"; then
    printf 'active-managed=yes\n'
  elif [[ -e "$ACTIVE_CONFIG" ]]; then
    printf 'active-managed=no\n'
  else
    printf 'active-managed=missing\n'
  fi
  for mode in "${MODES[@]}"; do
    [[ -f "$BAR_TARGET_DIR/$mode.conf" ]] && printf '%s-template=present\n' "$mode" || printf '%s-template=missing\n' "$mode"
  done
  package_installed i3-wm && printf 'i3-wm=installed\n' || printf 'i3-wm=missing\n'
  package_installed i3status && printf 'i3status=installed\n' || printf 'i3status=missing\n'
  package_installed tint2 && printf 'tint2=installed\n' || printf 'tint2=missing\n'
  package_installed polybar && printf 'polybar=installed\n' || printf 'polybar=missing\n'
  if [[ -x "$RUNTIME_TARGET" ]]; then
    "$RUNTIME_TARGET" --status 2>/dev/null || printf 'external-runtime=unavailable\n'
  else
    printf 'external-runtime=missing\n'
  fi
}

show_plan() {
  local mode="${REQUESTED_MODE:-$(mode_from_state)}"
  validate_i3_layout
  [[ -n "$REQUESTED_MODE" ]] && validate_active_target
  printf '═══ Plan de barras i3 Rafex ═══\n'
  printf 'perfil=%s\n' "$mode"
  info '[plan] conservar i3bar como perfil predeterminado y fallback'
  info '[plan] mantener una sola inclusión: ~/.config/i3/rafex-bar-active.conf'
  info '[plan] no modificar Conky, EWW, Picom, Openbox ni i3status'
  [[ "$mode" == polybar ]] && info '[plan] Polybar se instalará solo al seleccionar este perfil'
  [[ "$mode" == tint2 ]] && info '[plan] Tint2 se instalará si falta en Debian'
}

ensure_requested_package() {
  local mode="$REQUESTED_MODE"
  if [[ "$mode" == polybar ]] && ! package_installed polybar; then
    install_polybar_if_needed
  elif [[ "$mode" == tint2 ]] && ! package_installed tint2; then
    if [[ "$ACTION" == plan ]]; then
      info '[plan] sudo apt-get update && sudo apt-get install -y tint2'
    else
      command -v sudo >/dev/null 2>&1 || die 'sudo es necesario para instalar Tint2 desde Debian'
      sudo -v
      sudo apt-get update
      sudo apt-get install -y tint2
    fi
  fi
}

validate_active_target() {
  if [[ -e "$ACTIVE_CONFIG" ]] && ! grep -Fq '# Managed by rafex i3 bar profiles' "$ACTIVE_CONFIG"; then
    die "se rehúsa sobrescribir un active bar no administrado: $ACTIVE_CONFIG"
  fi
}

set_mode() {
  local mode="$REQUESTED_MODE" source had_active=false had_state=false old_state='' active_backup=''
  validate_i3_layout
  [[ "$mode" == i3bar ]] || [[ -x "$RUNTIME_TARGET" ]] || die "falta el runtime instalado: $RUNTIME_TARGET"
  [[ -f "$BAR_TARGET_DIR/$mode.conf" ]] || die "falta plantilla: $BAR_TARGET_DIR/$mode.conf"
  validate_active_target
  [[ "$ACTION" == plan ]] && { info "[plan] escribir perfil $mode en $STATE_FILE"; info "[plan] activar $BAR_TARGET_DIR/$mode.conf"; info '[plan] recargar i3'; return 0; }
  mkdir -p -- "$(dirname -- "$STATE_FILE")"
  if [[ -f "$STATE_FILE" ]]; then
    had_state=true
    old_state="$(head -n 1 "$STATE_FILE")"
  fi
  if [[ -f "$ACTIVE_CONFIG" ]]; then
    had_active=true
    backup_file "$ACTIVE_CONFIG"
    active_backup="$ACTIVE_CONFIG.bak.$STAMP"
  fi
  printf '%s\n' "$mode" > "$STATE_FILE"
  chmod 0644 "$STATE_FILE"
  source="$BAR_TARGET_DIR/$mode.conf"
  [[ "$had_active" == true ]] || info 'no existía un archivo activo; se creará el perfil predeterminado'
  replace_file "$source" "$ACTIVE_CONFIG"
  if command -v i3-msg >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    if ! i3-msg reload >/dev/null; then
      if [[ "$had_active" == true && -f "$active_backup" ]]; then
        replace_file "$active_backup" "$ACTIVE_CONFIG"
      else
        rm -f -- "$ACTIVE_CONFIG"
      fi
      if [[ "$had_state" == true ]]; then
        printf '%s\n' "$old_state" > "$STATE_FILE"
      else
        rm -f -- "$STATE_FILE"
      fi
      i3-msg reload >/dev/null 2>&1 || true
      die 'i3 rechazó la recarga; se restauró el perfil anterior'
    fi
  else
    warn 'no hay DISPLAY/i3-msg; el perfil se aplicará en la próxima sesión'
  fi
  ok "perfil activo: $mode"
}

rollback() {
  local latest
  latest="$(find "$(dirname -- "$ACTIVE_CONFIG")" -maxdepth 1 -type f -name 'rafex-bar-active.conf.bak.*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print}')"
  [[ -n "$latest" && -f "$latest" ]] || die 'no existe respaldo del archivo activo para revertir'
  [[ "$ACTION" == rollback ]] || return 0
  backup_file "$ACTIVE_CONFIG"
  replace_file "$latest" "$ACTIVE_CONFIG"
  local mode='i3bar'
  mode="$(awk -F= '/^# profile=/{print $2; exit}' "$latest")"
  case "$mode" in i3bar|tint2|polybar) ;; *) mode=i3bar ;; esac
  mkdir -p -- "$(dirname -- "$STATE_FILE")"
  printf '%s\n' "$mode" > "$STATE_FILE"
  chmod 0644 "$STATE_FILE"
  if command -v i3-msg >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then i3-msg reload >/dev/null || true; fi
  ok "archivo activo restaurado desde $(basename -- "$latest")"
}

main() {
  parse_args "$@"
  require_linux
  validate_sources
  case "$ACTION" in
    check)
      echo '═══ Perfiles de barras i3 Rafex ═══'
      validate_i3_layout
      show_status
      ;;
    plan)
      show_plan
      ;;
    status) show_status ;;
    set)
      validate_i3_layout
      validate_active_target
      ensure_requested_package
      install_materialized_files
      migrate_i3_config
      ensure_active_file
      set_mode
      ;;
    reload)
      command -v i3-msg >/dev/null 2>&1 || die 'falta i3-msg'
      [[ -n "${DISPLAY:-}" ]] || die 'DISPLAY no está disponible'
      i3-msg reload >/dev/null
      ;;
    rollback) rollback ;;
  esac
}

main "$@"
