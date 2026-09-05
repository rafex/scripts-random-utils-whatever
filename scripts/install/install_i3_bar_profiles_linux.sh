#!/usr/bin/env bash
# shellcheck shell=bash
# Instala los tres perfiles de barra i3 y migra el bloque bar administrado.
set -Eeuo pipefail
umask 077

ACTION=check
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE_DIR="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BAR_SOURCE_DIR="$PROFILE_DIR/config/rafex/i3-bars"
BAR_TARGET_DIR="$CONFIG_HOME/rafex/i3-bars"
I3_CONFIG="$CONFIG_HOME/i3/config"
ACTIVE_CONFIG="$CONFIG_HOME/i3/rafex-bar-active.conf"
STATE_FILE="$CONFIG_HOME/rafex/i3-bar-profile"
RUNTIME_SOURCE="$REPO_ROOT/scripts/system/rafex_i3_bar_runtime_linux.sh"
SELECTOR_SOURCE="$REPO_ROOT/scripts/system/i3_bar_profile_linux.sh"
WINDOW_TASKS_SOURCE="$REPO_ROOT/scripts/system/i3_window_tasks_polybar_linux.sh"
RUNTIME_TARGET="$HOME/.local/bin/rafex-i3-bar-runtime.sh"
SELECTOR_TARGET="$HOME/.local/bin/i3-bar-profile.sh"
WINDOW_TASKS_TARGET="$HOME/.local/bin/i3-window-tasks-polybar.sh"
STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_i3_bar_profiles_linux.sh --check
  install_i3_bar_profiles_linux.sh --plan
  install_i3_bar_profiles_linux.sh --apply
  install_i3_bar_profiles_linux.sh --status
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--apply|--status) ACTION="${1#--}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  (( EUID != 0 )) || die 'ejecuta como usuario normal'
  [[ -d "$PROFILE_DIR" ]] || die "falta el perfil: $PROFILE_DIR"
  for command_name in cmp cp date find grep install mktemp mv sort awk; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

validate_sources() {
  local file
  for file in i3bar.conf tint2.conf polybar.conf tint2rc polybar.ini; do
    [[ -f "$BAR_SOURCE_DIR/$file" ]] || die "falta fuente: $BAR_SOURCE_DIR/$file"
  done
  [[ -f "$RUNTIME_SOURCE" ]] || die "falta runtime: $RUNTIME_SOURCE"
  [[ -f "$SELECTOR_SOURCE" ]] || die "falta selector: $SELECTOR_SOURCE"
  [[ -f "$WINDOW_TASKS_SOURCE" ]] || die "falta helper de ventanas: $WINDOW_TASKS_SOURCE"
}

extract_bar_block() {
  awk '
    BEGIN { inside=0; depth=0 }
    !inside && $0 ~ /^[[:space:]]*bar[[:space:]]*\{/ { inside=1 }
    inside {
      line=$0; opens=gsub(/\{/, "", line); closes=gsub(/\}/, "", line)
      depth += opens - closes; print
      if (depth == 0) exit
    }
  ' "$I3_CONFIG"
}

validate_i3() {
  local includes block
  [[ -f "$I3_CONFIG" ]] || die "falta i3/config: $I3_CONFIG"
  includes="$(grep -Ec '^[[:space:]]*include[[:space:]]+~/.config/i3/rafex-bar-active\.conf[[:space:]]*$' "$I3_CONFIG" || true)"
  (( includes <= 1 )) || die 'hay inclusiones activas duplicadas'
  if grep -Eq '^[[:space:]]*bar[[:space:]]*\{' "$I3_CONFIG"; then
    block="$(extract_bar_block)"
    grep -Fq 'status_command i3status' <<<"$block" || die 'se detectó un bloque bar manual; no se sobrescribe'
    grep -Fq 'tray_output primary' <<<"$block" || die 'se detectó un bloque bar manual; no se sobrescribe'
    grep -Fq 'theme_bar_bg' <<<"$block" || die 'se detectó un bloque bar manual; no se sobrescribe'
    (( includes == 0 )) || die 'bar embebido e include activo; resuélvelo manualmente'
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
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-bars.XXXXXX")"
  install -m 0644 -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

migrate_i3() {
  local includes temporary block_file
  validate_i3
  includes="$(grep -Ec '^[[:space:]]*include[[:space:]]+~/.config/i3/rafex-bar-active\.conf[[:space:]]*$' "$I3_CONFIG" || true)"
  (( includes == 0 )) || return 0
  temporary="$(mktemp "$(dirname -- "$I3_CONFIG")/.rafex-i3-bars.XXXXXX")"
  if grep -Eq '^[[:space:]]*bar[[:space:]]*\{' "$I3_CONFIG"; then
    block_file="$(mktemp)"
    extract_bar_block > "$block_file"
    awk -v block_file="$block_file" '
      BEGIN { inside=0; depth=0; inserted=0 }
      !inside && $0 ~ /^[[:space:]]*bar[[:space:]]*\{/ {
        inside=1
        if (!inserted) { print "include ~/.config/i3/rafex-bar-active.conf"; inserted=1 }
      }
      inside {
        line=$0; opens=gsub(/\{/, "", line); closes=gsub(/\}/, "", line)
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

install_files() {
  local file mode='i3bar'
  [[ -f "$STATE_FILE" ]] && mode="$(head -n 1 "$STATE_FILE")"
  case "$mode" in i3bar|tint2|polybar) ;; *) mode=i3bar ;; esac
  for file in i3bar.conf tint2.conf polybar.conf tint2rc polybar.ini; do
    if [[ "$ACTION" == plan ]]; then
      info "[plan] copiar $BAR_SOURCE_DIR/$file → $BAR_TARGET_DIR/$file"
    else
      if [[ -f "$BAR_TARGET_DIR/$file" ]] && cmp -s "$BAR_SOURCE_DIR/$file" "$BAR_TARGET_DIR/$file"; then continue; fi
      backup_file "$BAR_TARGET_DIR/$file"
      replace_file "$BAR_SOURCE_DIR/$file" "$BAR_TARGET_DIR/$file"
    fi
  done
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $RUNTIME_TARGET, $SELECTOR_TARGET y $WINDOW_TASKS_TARGET"
    info "[plan] activar el perfil $mode"
  else
    mkdir -p -- "$HOME/.local/bin"
    backup_file "$RUNTIME_TARGET"; install -m 0755 -- "$RUNTIME_SOURCE" "$RUNTIME_TARGET"
    backup_file "$SELECTOR_TARGET"; install -m 0755 -- "$SELECTOR_SOURCE" "$SELECTOR_TARGET"
    backup_file "$WINDOW_TASKS_TARGET"; install -m 0755 -- "$WINDOW_TASKS_SOURCE" "$WINDOW_TASKS_TARGET"
    printf '%s\n' "$mode" > "$STATE_FILE"
    chmod 0644 "$STATE_FILE"
    backup_file "$ACTIVE_CONFIG"
    replace_file "$BAR_TARGET_DIR/$mode.conf" "$ACTIVE_CONFIG"
  fi
}

show_status() {
  printf 'source=%s\n' "$BAR_SOURCE_DIR"
  printf 'target=%s\n' "$BAR_TARGET_DIR"
  printf 'i3-config=%s\n' "$I3_CONFIG"
  printf 'active=%s\n' "$ACTIVE_CONFIG"
  if [[ -f "$ACTIVE_CONFIG" ]] && grep -Fq '# Managed by rafex i3 bar profiles' "$ACTIVE_CONFIG"; then printf 'active-managed=yes\n'; else printf 'active-managed=no-or-missing\n'; fi
  if [[ -f "$STATE_FILE" ]]; then printf 'selected=%s\n' "$(head -n 1 "$STATE_FILE")"; else printf 'selected=i3bar-default\n'; fi
  validate_i3
  for file in i3bar.conf tint2.conf polybar.conf tint2rc polybar.ini; do
    [[ -f "$BAR_TARGET_DIR/$file" ]] && printf '%s=present\n' "$file" || printf '%s=missing\n' "$file"
  done
}

main() {
  parse_args "$@"
  require_linux
  validate_sources
  case "$ACTION" in
    check) echo '═══ Instalador de perfiles de barras i3 ═══'; validate_i3; show_status ;;
    plan) echo '═══ Plan de perfiles de barras i3 ═══'; validate_i3; install_files ;;
    apply) echo '═══ Instalación de perfiles de barras i3 ═══'; validate_i3; migrate_i3; install_files; ok 'perfiles i3bar, Tint2 y Polybar preparados; i3bar queda como predeterminado' ;;
    status) show_status ;;
  esac
}

main "$@"
