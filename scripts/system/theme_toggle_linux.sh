#!/usr/bin/env bash
# shellcheck shell=bash
# Cambia el tema claro/oscuro del perfil i3 ThinkPad sin sudo.
set -Eeuo pipefail
umask 077

ACTION='check'
PLAN_ONLY=0
REQUESTED_MODE=''
TOGGLE_REQUESTED=0
STAMP="$(date +%Y%m%d_%H%M%S)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_HOME="$CONFIG_HOME/rafex/themes"
CURRENT_LINK="$THEME_HOME/current"
STATE_FILE="$CONFIG_HOME/rafex/theme"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  theme_toggle_linux.sh --check
  theme_toggle_linux.sh --plan [--set light|dark]
  theme_toggle_linux.sh --set light|dark
  theme_toggle_linux.sh --toggle

Opciones:
  --check             Mostrar el estado sin modificar archivos
  --plan              Mostrar la acción prevista sin aplicarla
  --set <modo>        Activar light o dark
  --toggle            Alternar entre light y dark
  -h, --help          Mostrar esta ayuda
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; PLAN_ONLY=0; shift ;;
      --plan|--dry-run) ACTION='plan'; PLAN_ONLY=1; shift ;;
      --set)
        [[ $# -ge 2 ]] || die '--set requiere light o dark'
        REQUESTED_MODE="$2"
        [[ "$PLAN_ONLY" -eq 1 ]] || ACTION='set'
        shift 2
        ;;
      --toggle)
        TOGGLE_REQUESTED=1
        [[ "$PLAN_ONLY" -eq 1 ]] || ACTION='toggle'
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  if [[ -n "$REQUESTED_MODE" && "$REQUESTED_MODE" != light && "$REQUESTED_MODE" != dark ]]; then
    die "modo desconocido: $REQUESTED_MODE (usa light o dark)"
  fi
}

current_mode() {
  local mode='light'
  if [[ -f "$STATE_FILE" ]]; then
    mode="$(head -n 1 "$STATE_FILE")"
  elif [[ -L "$CURRENT_LINK" ]]; then
    mode="$(readlink "$CURRENT_LINK")"
  fi
  if [[ "$mode" == light || "$mode" == dark ]]; then
    printf '%s\n' "$mode"
  else
    printf '%s\n' light
  fi
}

validate_mode() {
  local mode="$1"
  local file
  [[ "$mode" == light || "$mode" == dark ]] || die "modo inválido: $mode"
  [[ -d "$THEME_HOME/$mode" ]] || die "no existe la paleta: $THEME_HOME/$mode"
  for file in i3.conf tmux.conf alacritty.toml rofi.rasi dunst.conf; do
    [[ -f "$THEME_HOME/$mode/$file" ]] || die "falta $THEME_HOME/$mode/$file"
  done
}

show_status() {
  local mode
  mode="$(current_mode)"
  printf 'theme=%s\n' "$mode"
  if [[ -L "$CURRENT_LINK" ]]; then
    printf 'current=%s\n' "$(readlink "$CURRENT_LINK")"
  else
    printf 'current=missing\n'
  fi
  for command_name in i3-msg tmux dunstctl; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=available\n' "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
}

backup_file() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 0
  cp -a -- "$file" "${file}.bak.${STAMP}"
  info "respaldo creado: ${file}.bak.${STAMP}"
}

apply_link() {
  local mode="$1"
  local temporary
  mkdir -p "$THEME_HOME"
  if [[ -e "$CURRENT_LINK" && ! -L "$CURRENT_LINK" ]]; then
    backup_file "$CURRENT_LINK"
    rm -rf -- "$CURRENT_LINK"
  fi
  temporary="$THEME_HOME/.current.$$"
  rm -f -- "$temporary"
  ln -s "$mode" "$temporary"
  if [[ -L "$CURRENT_LINK" ]]; then
    rm -- "$CURRENT_LINK"
  fi
  if [[ "$(uname -s)" == Linux ]]; then
    mv -Tf -- "$temporary" "$CURRENT_LINK"
  else
    mv -f -- "$temporary" "$CURRENT_LINK"
  fi
  if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" != "$mode" ]]; then
    backup_file "$STATE_FILE"
  fi
  printf '%s\n' "$mode" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

reload_desktop() {
  if command -v i3-msg >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    i3-msg reload >/dev/null 2>&1 || warn 'i3 no pudo recargar su configuración'
  fi
  if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$CURRENT_LINK/tmux.conf" 2>/dev/null || warn 'tmux no pudo recargar el tema'
  fi
  if command -v dunstctl >/dev/null 2>&1 && dunstctl reload >/dev/null 2>&1; then
    :
  elif pgrep -x dunst >/dev/null 2>&1; then
    pkill -HUP -x dunst || warn 'dunst no pudo recargar el tema'
  fi
}

apply_mode() {
  local mode="$1"
  validate_mode "$mode"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] activar tema $mode mediante $CURRENT_LINK"
    info '[plan] recargar i3, tmux y dunst si están activos'
    return 0
  fi
  apply_link "$mode"
  reload_desktop
  ok "tema activo: $mode"
}

main() {
  parse_args "$@"
  if [[ "$PLAN_ONLY" -eq 1 ]]; then
    ACTION='plan'
  fi
  case "$ACTION" in
    check)
      echo '═══ Tema ThinkPad ═══'
      validate_mode light
      validate_mode dark
      show_status
      ;;
    plan)
      echo '═══ Plan de tema ThinkPad ═══'
      if [[ "$TOGGLE_REQUESTED" -eq 1 ]]; then
        if [[ "$(current_mode)" == light ]]; then
          REQUESTED_MODE=dark
        else
          REQUESTED_MODE=light
        fi
      fi
      apply_mode "${REQUESTED_MODE:-$(current_mode)}"
      ;;
    set) apply_mode "$REQUESTED_MODE" ;;
    toggle)
      if [[ "$(current_mode)" == light ]]; then
        apply_mode dark
      else
        apply_mode light
      fi
      ;;
  esac
}

main "$@"
