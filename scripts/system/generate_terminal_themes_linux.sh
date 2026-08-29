#!/usr/bin/env bash
# shellcheck shell=bash
# Materializa las paletas del perfil ThinkPad en la configuración del usuario.
set -Eeuo pipefail
umask 077

ACTION="check"
THEME="all"
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET_ROOT="$CONFIG_HOME/rafex/themes"
THEMES=(paper nord everforest dracula)

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
  generate_terminal_themes_linux.sh --check
  generate_terminal_themes_linux.sh --plan [--theme all|paper|nord|everforest|dracula]
  generate_terminal_themes_linux.sh --apply [--theme all|paper|nord|everforest|dracula]

Opciones:
  --check          Verifica plantillas y destino sin modificar archivos.
  --plan           Muestra las paletas que se materializarían.
  --dry-run        Alias de --plan.
  --apply          Instala las paletas en ~/.config/rafex/themes.
  --theme <tema>   Selecciona una paleta o todas (default: all).
  -h, --help       Muestra esta ayuda.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --theme)
        [[ $# -ge 2 ]] || die "--theme requiere un nombre"
        THEME="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  if [[ "$THEME" != all ]]; then
    case " ${THEMES[*]} " in
      *" $THEME "*) ;;
      *) die "tema inválido: $THEME" ;;
    esac
  fi
}

require_commands() {
  [[ "$(uname -s)" == Linux ]] || die "este script requiere Linux"
  local command_name
  for command_name in basename cmp cp date dirname mkdir mktemp mv; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

selected_themes() {
  if [[ "$THEME" == all ]]; then
    printf '%s\n' "${THEMES[@]}"
  else
    printf '%s\n' "$THEME"
  fi
}

validate_sources() {
  local theme file
  while IFS= read -r theme; do
    [[ -d "$SOURCE_ROOT/$theme" ]] || die "falta la plantilla de tema: $SOURCE_ROOT/$theme"
    for file in i3.conf tmux.conf alacritty.toml rofi.rasi dunst.conf xresources; do
      [[ -f "$SOURCE_ROOT/$theme/$file" ]] || die "falta $SOURCE_ROOT/$theme/$file"
    done
  done < <(selected_themes)
}

backup_path() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  cp -a -- "$path" "${path}.bak.${STAMP}"
  info "respaldo creado: ${path}.bak.${STAMP}"
}

install_theme_file() {
  local source="$1" target="$2" temporary
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  backup_path "$target"
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  cp -- "$source" "$temporary"
  chmod 644 "$temporary"
  mv -f -- "$temporary" "$target"
}

show_status() {
  local theme file
  printf 'source=%s\n' "$SOURCE_ROOT"
  printf 'target=%s\n' "$TARGET_ROOT"
  while IFS= read -r theme; do
    printf '%s=' "$theme"
    if [[ -d "$TARGET_ROOT/$theme" ]]; then
      for file in i3.conf tmux.conf alacritty.toml rofi.rasi dunst.conf xresources; do
        [[ -f "$TARGET_ROOT/$theme/$file" ]] || {
          printf 'incomplete\n'
          continue 2
        }
      done
      printf 'available\n'
    else
      printf 'missing\n'
    fi
  done < <(selected_themes)
}

main() {
  parse_args "$@"
  require_commands
  validate_sources

  case "$ACTION" in
    check)
      echo '═══ Paletas de terminal e i3 ═══'
      show_status
      ;;
    plan)
      echo '═══ Plan de paletas de terminal e i3 ═══'
      while IFS= read -r theme; do
        info "[plan] materializar $theme en $TARGET_ROOT/$theme"
      done < <(selected_themes)
      info '[plan] conservar el tema actual; usa theme-toggle.sh --set <tema> para seleccionarlo'
      ;;
    apply)
      echo '═══ Generación de paletas de terminal e i3 ═══'
      local theme file
      while IFS= read -r theme; do
        for file in i3.conf tmux.conf alacritty.toml rofi.rasi dunst.conf xresources; do
          install_theme_file "$SOURCE_ROOT/$theme/$file" "$TARGET_ROOT/$theme/$file"
        done
        ok "paleta instalada: $theme"
      done < <(selected_themes)
      ;;
  esac
}

main "$@"
