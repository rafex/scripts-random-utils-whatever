#!/usr/bin/env bash
# shellcheck shell=bash
# Cambia el tema del perfil ThinkPad para i3 u Openbox sin sudo.
set -Eeuo pipefail
umask 077

ACTION='check'
PLAN_ONLY=0
REQUESTED_MODE=''
TOGGLE_REQUESTED=0
CYCLE_REQUESTED=0
STAMP="$(date +%Y%m%d_%H%M%S)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_HOME="$CONFIG_HOME/rafex/themes"
CURRENT_LINK="$THEME_HOME/current"
STATE_FILE="$CONFIG_HOME/rafex/theme"
I3_CONFIG="$CONFIG_HOME/i3/config"
I3STATUS_CONFIG="$CONFIG_HOME/i3status/config"
OPENBOX_CONFIG="$CONFIG_HOME/openbox/rc.xml"
TINT2_CONFIG="$CONFIG_HOME/tint2/tint2rc"
CONKY_CONFIG="$CONFIG_HOME/conky/conky.conf"
XRESOURCES="$HOME/.Xresources"
I3_THEME_BEGIN='# BEGIN rafex theme'
I3_THEME_END='# END rafex theme'
I3_THEME_LEGACY='include ~/.config/rafex/themes/current/i3.conf'
XRES_THEME_BEGIN='! BEGIN rafex theme'
XRES_THEME_END='! END rafex theme'
OPENBOX_THEME_BEGIN='    <!-- BEGIN rafex theme -->'
OPENBOX_THEME_END='    <!-- END rafex theme -->'
TINT2_THEME_BEGIN='# BEGIN rafex theme'
TINT2_THEME_END='# END rafex theme'
CONKY_THEME_BEGIN='    -- BEGIN rafex theme'
CONKY_THEME_END='    -- END rafex theme'
THEME_NAMES=(paper nord everforest dracula)

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
  theme_toggle_linux.sh --plan [--set TEMA]
  theme_toggle_linux.sh --list
  theme_toggle_linux.sh --set paper|nord|everforest|dracula
  theme_toggle_linux.sh --cycle
  theme_toggle_linux.sh --toggle

Opciones:
  --check             Mostrar el estado sin modificar archivos
  --plan              Mostrar la acción prevista sin aplicarla
  --list              Listar las paletas disponibles y la activa
  --set <tema>        Activar paper, nord, everforest o dracula
  --cycle             Activar la siguiente de las cuatro paletas
  --toggle            Alternar entre Nord y Dracula
  -h, --help          Mostrar esta ayuda
EOF
}

canonical_theme() {
  case "$1" in
    light) printf '%s\n' nord ;;
    dark) printf '%s\n' dracula ;;
    paper|nord|everforest|dracula) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; PLAN_ONLY=0; shift ;;
      --plan|--dry-run) ACTION='plan'; PLAN_ONLY=1; shift ;;
      --list) ACTION='list'; PLAN_ONLY=0; shift ;;
      --set)
        [[ $# -ge 2 ]] || die '--set requiere un tema'
        REQUESTED_MODE="$2"
        [[ "$PLAN_ONLY" -eq 1 ]] || ACTION='set'
        shift 2
        ;;
      --cycle)
        CYCLE_REQUESTED=1
        [[ "$PLAN_ONLY" -eq 1 ]] || ACTION='cycle'
        shift
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
  if [[ -n "$REQUESTED_MODE" ]] && ! canonical_theme "$REQUESTED_MODE" >/dev/null; then
    die "tema desconocido: $REQUESTED_MODE (usa paper, nord, everforest o dracula)"
  fi
}

current_mode() {
  local mode='nord'
  if [[ -f "$STATE_FILE" ]]; then
    mode="$(head -n 1 "$STATE_FILE")"
  elif [[ -L "$CURRENT_LINK" ]]; then
    mode="$(readlink "$CURRENT_LINK")"
  fi
  canonical_theme "$mode" 2>/dev/null || printf '%s\n' nord
}

validate_mode() {
  local mode
  local file
  mode="$(canonical_theme "$1")" || die "tema inválido: $1"
  [[ -d "$THEME_HOME/$mode" ]] || die "no existe la paleta: $THEME_HOME/$mode"
  for file in i3.conf tmux.conf alacritty.toml rofi.rasi dunst.conf xresources i3status.conf conky.conf; do
    [[ -f "$THEME_HOME/$mode/$file" ]] || die "falta $THEME_HOME/$mode/$file"
  done
  if [[ -f "$OPENBOX_CONFIG" ]]; then
    [[ -f "$THEME_HOME/$mode/openbox.themerc" ]] || die "falta $THEME_HOME/$mode/openbox.themerc"
  fi
  if [[ -f "$TINT2_CONFIG" ]]; then
    [[ -f "$THEME_HOME/$mode/tint2.conf" ]] || die "falta $THEME_HOME/$mode/tint2.conf"
  fi
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
  printf 'available=%s\n' "${THEME_NAMES[*]}"
  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_THEME_BEGIN" "$I3_CONFIG"; then
    printf 'i3-theme-block=present\n'
  else
    printf 'i3-theme-block=missing\n'
  fi
  if [[ -f "$OPENBOX_CONFIG" ]] && grep -Fq 'Rafex-' "$OPENBOX_CONFIG"; then
    printf 'openbox-theme-block=present\n'
  else
    printf 'openbox-theme-block=missing-or-inactive\n'
  fi
  if [[ -f "$TINT2_CONFIG" ]]; then
    printf 'tint2-config=present\n'
  else
    printf 'tint2-config=missing-or-inactive\n'
  fi
  if [[ -f "$CONKY_CONFIG" ]] && grep -Fq "$CONKY_THEME_BEGIN" "$CONKY_CONFIG"; then
    printf 'conky-theme-block=present\n'
  else
    printf 'conky-theme-block=missing-or-inactive\n'
  fi
  for command_name in i3-msg tmux dunstctl; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=available\n' "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
}

sync_i3_theme() {
  local block_file temporary mode
  [[ -f "$I3_CONFIG" ]] || {
    warn "no existe $I3_CONFIG; se actualizó el tema, pero i3 deberá configurarse manualmente"
    return 0
  }
  block_file="$(mktemp)"
  cat "$CURRENT_LINK/i3.conf" > "$block_file"
  temporary="$(mktemp)"
  awk -v begin="$I3_THEME_BEGIN" -v end="$I3_THEME_END" \
      -v legacy="$I3_THEME_LEGACY" -v block_file="$block_file" '
    function emit_block( line) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }
    $0 == begin {
      print begin
      emit_block()
      in_block = 1
      found = 1
      next
    }
    in_block && $0 == end {
      print end
      in_block = 0
      next
    }
    $0 == legacy {
      print begin
      emit_block()
      print end
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print ""
        print begin
        emit_block()
        print end
      }
    }
  ' "$I3_CONFIG" > "$temporary"
  rm -f -- "$block_file"
  if cmp -s "$I3_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  backup_file "$I3_CONFIG"
  if mode="$(stat -c '%a' "$I3_CONFIG" 2>/dev/null)"; then
    chmod "$mode" "$temporary"
  elif mode="$(stat -f '%Lp' "$I3_CONFIG" 2>/dev/null)"; then
    chmod "$mode" "$temporary"
  fi
  mv -- "$temporary" "$I3_CONFIG"
}

sync_xresources() {
  local block_file temporary mode
  [[ -f "$XRESOURCES" ]] || {
    warn "no existe $XRESOURCES; rxvt usará sus valores predeterminados"
    return 0
  }
  block_file="$(mktemp)"
  cat "$CURRENT_LINK/xresources" > "$block_file"
  temporary="$(mktemp)"
  awk -v begin="$XRES_THEME_BEGIN" -v end="$XRES_THEME_END" \
      -v block_file="$block_file" '
    function emit_block(line) {
      print begin
      while ((getline line < block_file) > 0) print line
      close(block_file)
      print end
    }
    $0 == begin { emit_block(); inside=1; found=1; next }
    inside && $0 == end { inside=0; next }
    !inside { print }
    END { if (!found) { print ""; emit_block() } }
  ' "$XRESOURCES" > "$temporary"
  rm -f -- "$block_file"
  if cmp -s "$XRESOURCES" "$temporary"; then
    rm -f -- "$temporary"
  else
    backup_file "$XRESOURCES"
    if mode="$(stat -c '%a' "$XRESOURCES" 2>/dev/null)"; then
      chmod "$mode" "$temporary"
    fi
    mv -- "$temporary" "$XRESOURCES"
  fi
  if command -v xrdb >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xrdb -merge "$XRESOURCES" || warn 'xrdb no pudo recargar ~/.Xresources'
  fi
}

sync_openbox_theme() {
  local block_file temporary theme_name mode theme_label
  [[ -f "$OPENBOX_CONFIG" ]] || return 0
  mode="$(current_mode)"
  block_file="$CURRENT_LINK/openbox.themerc"
  [[ -f "$block_file" ]] || {
    warn "no existe la plantilla Openbox del tema: $block_file"
    return 0
  }
  case "$mode" in
    paper) theme_label='Paper' ;;
    nord) theme_label='Nord' ;;
    everforest) theme_label='Everforest' ;;
    dracula) theme_label='Dracula' ;;
    *) die "tema inválido: $mode" ;;
  esac
  theme_name="Rafex-$theme_label"
  mkdir -p "$HOME/.themes/$theme_name/openbox-3"
  if [[ ! -f "$HOME/.themes/$theme_name/openbox-3/themerc" ]] || \
      ! cmp -s "$block_file" "$HOME/.themes/$theme_name/openbox-3/themerc"; then
    backup_file "$HOME/.themes/$theme_name/openbox-3/themerc"
    install -m 0644 "$block_file" "$HOME/.themes/$theme_name/openbox-3/themerc"
  fi
  temporary="$(mktemp)"
  awk -v begin="$OPENBOX_THEME_BEGIN" -v end="$OPENBOX_THEME_END" \
      -v theme_name="$theme_name" '
    $0 == begin { print; print "    <name>" theme_name "</name>"; inside=1; found=1; next }
    inside && $0 == end { print; inside=0; next }
    !inside { print }
    END {
      if (!found) {
        print "    <!-- BEGIN rafex theme -->"
        print "    <name>" theme_name "</name>"
        print "    <!-- END rafex theme -->"
      }
    }
  ' "$OPENBOX_CONFIG" > "$temporary"
  if cmp -s "$OPENBOX_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
  else
    backup_file "$OPENBOX_CONFIG"
    chmod --reference="$OPENBOX_CONFIG" "$temporary" 2>/dev/null || true
    mv -- "$temporary" "$OPENBOX_CONFIG"
  fi
}

sync_tint2_theme() {
  local temporary source_file
  [[ -f "$TINT2_CONFIG" ]] || return 0
  source_file="$CURRENT_LINK/tint2.conf"
  [[ -f "$source_file" ]] || {
    warn "no existe la plantilla tint2 del tema: $source_file"
    return 0
  }
  temporary="$(mktemp)"
  awk -v begin="$TINT2_THEME_BEGIN" -v end="$TINT2_THEME_END" -v source_file="$source_file" '
    function emit_theme(line) {
      while ((getline line < source_file) > 0) print line
      close(source_file)
    }
    $0 == begin { emit_theme(); inside=1; found=1; next }
    inside && $0 == end { inside=0; next }
    !inside { print }
    END { if (!found) { print ""; emit_theme() } }
  ' "$TINT2_CONFIG" > "$temporary"
  if cmp -s "$TINT2_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
  else
    backup_file "$TINT2_CONFIG"
    chmod --reference="$TINT2_CONFIG" "$temporary" 2>/dev/null || true
    mv -- "$temporary" "$TINT2_CONFIG"
  fi
  if command -v pkill >/dev/null 2>&1 && pgrep -x tint2 >/dev/null 2>&1; then
    pkill -USR1 -x tint2 2>/dev/null || warn 'tint2 no pudo recargar el tema'
  fi
}

sync_conky_theme() {
  local source_file temporary
  [[ -f "$CONKY_CONFIG" ]] || return 0
  if ! grep -Fq "$CONKY_THEME_BEGIN" "$CONKY_CONFIG"; then
    warn "la configuración Conky no está administrada por Rafex; no se modifica: $CONKY_CONFIG"
    return 0
  fi
  source_file="$CURRENT_LINK/conky.conf"
  [[ -f "$source_file" ]] || {
    warn "no existe la plantilla Conky del tema: $source_file"
    return 0
  }
  temporary="$(mktemp)"
  awk -v begin="$CONKY_THEME_BEGIN" -v end="$CONKY_THEME_END" -v source_file="$source_file" '
    function emit_theme(line) {
      while ((getline line < source_file) > 0) {
        if (line == begin) inside_source=1
        if (inside_source) print line
        if (line == end) break
      }
      close(source_file)
    }
    $0 == begin { emit_theme(); inside=1; found=1; next }
    inside && $0 == end { inside=0; next }
    !inside { print }
    END { if (!found) { print ""; emit_theme() } }
  ' "$CONKY_CONFIG" > "$temporary"
  if cmp -s "$CONKY_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
  else
    backup_file "$CONKY_CONFIG"
    chmod --reference="$CONKY_CONFIG" "$temporary" 2>/dev/null || true
    mv -- "$temporary" "$CONKY_CONFIG"
  fi
  if [[ -x "$HOME/.local/bin/conky-launch.sh" ]] && [[ -n "${DISPLAY:-}" ]]; then
    "$HOME/.local/bin/conky-launch.sh" --reload >/dev/null 2>&1 ||
      warn 'Conky no pudo recargar el tema'
  fi
}

sync_i3status_theme() {
  local block_file temporary
  [[ -f "$I3STATUS_CONFIG" ]] || {
    warn "no existe $I3STATUS_CONFIG; se conservaron los colores actuales de i3status"
    return 0
  }
  if ! grep -Eq '^[[:space:]]*general[[:space:]]*\{' "$I3STATUS_CONFIG"; then
    warn "no se encontró el bloque general de i3status; se conservaron los colores actuales"
    return 0
  fi
  block_file="$(mktemp)"
  cat "$CURRENT_LINK/i3status.conf" > "$block_file"
  temporary="$(mktemp)"
  awk -v begin="$I3_THEME_BEGIN" -v end="$I3_THEME_END" \
      -v block_file="$block_file" '
    function emit_block(line) {
      print begin
      while ((getline line < block_file) > 0) print line
      close(block_file)
      print end
    }
    {
      if ($0 == begin) { emit_block(); inside=1; found=1; next }
      if (inside && $0 == end) { inside=0; next }
      if (in_general && !found && $0 ~ /^[[:space:]]*}/) {
        emit_block()
        found=1
        in_general=0
      }
      if ($0 ~ /^[[:space:]]*general[[:space:]]*\{/) in_general=1
      print
    }
    END { if (!found) { print ""; emit_block() } }
  ' "$I3STATUS_CONFIG" > "$temporary"
  rm -f -- "$block_file"
  if cmp -s "$I3STATUS_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
  else
    backup_file "$I3STATUS_CONFIG"
    chmod --reference="$I3STATUS_CONFIG" "$temporary" 2>/dev/null || true
    mv -- "$temporary" "$I3STATUS_CONFIG"
  fi
  if command -v pkill >/dev/null 2>&1; then
    pkill -USR1 -x i3status 2>/dev/null || true
  fi
}

backup_file() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 0
  cp -a -- "$file" "${file}.bak.${STAMP}"
  info "respaldo creado: ${file}.bak.${STAMP}"
}

apply_link() {
  local mode
  local temporary
  mode="$(canonical_theme "$1")" || die "tema inválido: $1"
  mkdir -p "$THEME_HOME"
  if [[ -e "$CURRENT_LINK" && ! -L "$CURRENT_LINK" ]]; then
    backup_file "$CURRENT_LINK"
    rm -rf -- "$CURRENT_LINK"
  fi
  temporary="$THEME_HOME/.current.$$"
  rm -f -- "$temporary"
  ln -s "$mode" "$temporary"
  if [[ "$(uname -s)" == Linux ]]; then
    mv -Tf -- "$temporary" "$CURRENT_LINK"
  else
    rm -f -- "$CURRENT_LINK"
    mv -f -- "$temporary" "$CURRENT_LINK"
  fi
  if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" != "$mode" ]]; then
    backup_file "$STATE_FILE"
  fi
  printf '%s\n' "$mode" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

reload_desktop() {
  if command -v openbox >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]] && pgrep -x openbox >/dev/null 2>&1; then
    openbox --reconfigure >/dev/null 2>&1 || warn 'Openbox no pudo recargar su configuración'
  elif command -v i3-msg >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    i3-msg reload >/dev/null 2>&1 || warn 'i3 no pudo recargar su configuración'
  fi
  if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$CURRENT_LINK/tmux.conf" 2>/dev/null || warn 'tmux no pudo recargar el tema'
  fi
  if command -v dunst-smart.sh >/dev/null 2>&1 \
      && dunst-smart.sh --reload >/dev/null 2>&1; then
    :
  elif command -v dunstctl >/dev/null 2>&1 && dunstctl reload >/dev/null 2>&1; then
    :
  elif pgrep -x dunst >/dev/null 2>&1; then
    pkill -HUP -x dunst || warn 'dunst no pudo recargar el tema'
  else
    warn 'dunst no pudo recargar el tema'
  fi
}

apply_mode() {
  local mode
  mode="$(canonical_theme "$1")" || die "tema inválido: $1"
  validate_mode "$mode"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] activar tema $mode mediante $CURRENT_LINK"
    info "[plan] sincronizar bloque de colores en $I3_CONFIG"
    info "[plan] sincronizar Openbox/tint2 si están instalados"
    info '[plan] recargar i3/Openbox, tmux, tint2 y dunst si están activos'
    return 0
  fi
  apply_link "$mode"
  sync_i3_theme
  sync_i3status_theme
  sync_xresources
  sync_openbox_theme
  sync_tint2_theme
  sync_conky_theme
  reload_desktop
  ok "tema activo: $mode"
}

cycle_mode() {
  local current index next
  current="$(current_mode)"
  for index in "${!THEME_NAMES[@]}"; do
    if [[ "${THEME_NAMES[$index]}" == "$current" ]]; then
      next=$(( (index + 1) % ${#THEME_NAMES[@]} ))
      printf '%s\n' "${THEME_NAMES[$next]}"
      return 0
    fi
  done
  printf '%s\n' "${THEME_NAMES[0]}"
}

list_themes() {
  local theme current
  current="$(current_mode)"
  printf 'paletas=%s\n' "${THEME_NAMES[*]}"
  for theme in "${THEME_NAMES[@]}"; do
    if [[ "$theme" == "$current" ]]; then
      printf '* %s\n' "$theme"
    else
      printf '  %s\n' "$theme"
    fi
  done
  printf 'aliases: light=nord dark=dracula\n'
}

main() {
  parse_args "$@"
  if [[ "$PLAN_ONLY" -eq 1 ]]; then
    ACTION='plan'
  fi
  case "$ACTION" in
    check)
      echo '═══ Tema ThinkPad ═══'
      local theme
      for theme in "${THEME_NAMES[@]}"; do
        validate_mode "$theme"
      done
      show_status
      ;;
    list)
      echo '═══ Paletas ThinkPad ═══'
      list_themes
      ;;
    plan)
      echo '═══ Plan de tema ThinkPad ═══'
      if [[ "$TOGGLE_REQUESTED" -eq 1 ]]; then
        if [[ "$(current_mode)" == dracula ]]; then
          REQUESTED_MODE=nord
        else
          REQUESTED_MODE=dracula
        fi
      fi
      if [[ "$CYCLE_REQUESTED" -eq 1 ]]; then
        REQUESTED_MODE="$(cycle_mode)"
      fi
      apply_mode "${REQUESTED_MODE:-$(current_mode)}"
      ;;
    set) apply_mode "$REQUESTED_MODE" ;;
    cycle) apply_mode "$(cycle_mode)" ;;
    toggle)
      if [[ "$(current_mode)" == dracula ]]; then
        apply_mode nord
      else
        apply_mode dracula
      fi
      ;;
  esac
}

main "$@"
