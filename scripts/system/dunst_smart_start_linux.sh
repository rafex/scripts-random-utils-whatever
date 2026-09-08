#!/usr/bin/env bash
# shellcheck shell=bash
# Inicia o recarga Dunst justo debajo de la barra activa.
set -Eeuo pipefail
umask 077

ACTION="check"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_CONFIG="${DUNST_THEME_CONFIG:-$CONFIG_HOME/rafex/themes/current/dunst.conf}"
RUNTIME_CONFIG="${DUNST_SMART_CONFIG:-$CONFIG_HOME/rafex/dunst.conf}"
ACTIVE_PROFILE_FILE="$CONFIG_HOME/rafex/i3-bar-profile"
BAR_CONFIG_DIR="$CONFIG_HOME/rafex/i3-bars"
BAR_PROFILE=''
BAR_HEIGHT=''
BAR_HEIGHT_SOURCE=''
DUNST_ORIGIN='top-right'
DUNST_OFFSET=''
STAMP="$(date +%Y%m%d_%H%M%S)"

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
  dunst_smart_start_linux.sh --check
  dunst_smart_start_linux.sh --plan
  dunst_smart_start_linux.sh --apply
  dunst_smart_start_linux.sh --start
  dunst_smart_start_linux.sh --reload

Opciones:
  --check       Detecta la barra activa y su altura sin modificar archivos.
  --plan        Muestra la configuración Dunst que se generaría.
  --apply       Genera la configuración estable sin iniciar Dunst.
  --start       Genera la configuración y arranca o recarga Dunst.
  --reload      Regenera y recarga Dunst si ya está ejecutándose.
  --help        Muestra esta ayuda.

La notificación siempre usa top-right y su offset vertical es la altura
efectiva de la barra activa. No requiere sudo.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --start) ACTION="start"; shift ;;
      --reload) ACTION="reload"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_commands() {
  [[ "$(uname -s)" == Linux ]] || die "este script solo funciona en Linux"
  local command_name
  for command_name in awk cmp cp date grep head mkdir mktemp mv; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
  if [[ "$ACTION" == start || "$ACTION" == reload ]]; then
    command -v pgrep >/dev/null 2>&1 || die "falta la herramienta: pgrep"
  fi
}

active_profile() {
  local profile=''
  [[ -r "$ACTIVE_PROFILE_FILE" ]] && profile="$(head -n 1 "$ACTIVE_PROFILE_FILE")"
  case "$profile" in
    i3bar|tint2|polybar) printf '%s\n' "$profile"; return 0 ;;
    *) return 1 ;;
  esac
}

parse_integer_extent() {
  local raw="${1//[[:space:]]/}"
  [[ "$raw" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$raw"
}

x11_dpi() {
  local dpi=''
  if command -v xdpyinfo >/dev/null 2>&1; then
    dpi="$(xdpyinfo 2>/dev/null | awk '/resolution:/ { split($2, values, "x"); print values[1]; exit }')"
  fi
  if [[ ! "$dpi" =~ ^[0-9]+$ ]] && command -v xrdb >/dev/null 2>&1; then
    dpi="$(xrdb -query 2>/dev/null | awk '$1 == "Xft.dpi:" { print int($2); exit }')"
  fi
  [[ "$dpi" =~ ^[0-9]+$ && "$dpi" -gt 0 ]] || return 1
  printf '%s\n' "$dpi"
}

x11_screen_height() {
  local height=''
  if command -v xdpyinfo >/dev/null 2>&1; then
    height="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ { split($2, values, "x"); print values[2]; exit }')"
  fi
  [[ "$height" =~ ^[0-9]+$ && "$height" -gt 0 ]] || return 1
  printf '%s\n' "$height"
}

polybar_extent() {
  local raw="${1//[[:space:]]/}" number unit dpi screen_height
  if [[ "$raw" =~ ^([0-9]+)(pt|px|%)?$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]:-px}"
  else
    return 1
  fi
  case "$unit" in
    px) printf '%s\n' "$number" ;;
    pt)
      dpi="$(x11_dpi 2>/dev/null)" || return 1
      awk -v points="$number" -v dpi="$dpi" 'BEGIN { printf "%d\n", (points * dpi / 72) + 0.5 }'
      ;;
    %)
      screen_height="$(x11_screen_height 2>/dev/null)" || return 1
      awk -v percent="$number" -v height="$screen_height" 'BEGIN { printf "%d\n", (percent * height / 100) + 0.5 }'
      ;;
  esac
}

tint2_height() {
  local config="$BAR_CONFIG_DIR/tint2rc" raw height
  [[ -r "$config" ]] || return 1
  raw="$(awk '/^[[:space:]]*panel_size[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }' "$config")"
  height="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }' <<<"$raw")"
  parse_integer_extent "$height"
}

polybar_height() {
  local config="$BAR_CONFIG_DIR/polybar.ini" raw height border top bottom
  [[ -r "$config" ]] || return 1
  raw="$(awk '
    /^\[bar\/rafex\][[:space:]]*$/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && /^[[:space:]]*height[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$config")"
  height="$(polybar_extent "$raw")" || return 1
  border="$(awk '
    /^\[bar\/rafex\][[:space:]]*$/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && /^[[:space:]]*border-size[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$config")"
  top="$(awk '
    /^\[bar\/rafex\][[:space:]]*$/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && /^[[:space:]]*border-top-size[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$config")"
  bottom="$(awk '
    /^\[bar\/rafex\][[:space:]]*$/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && /^[[:space:]]*border-bottom-size[[:space:]]=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$config")"
  [[ -n "$top" ]] || top="$border"
  [[ -n "$bottom" ]] || bottom="$border"
  top="$(polybar_extent "$top")" || return 1
  bottom="$(polybar_extent "$bottom")" || return 1
  printf '%s\n' "$((height + top + bottom))"
}

i3bar_height() {
  local ids_json id config_json height first='' count=0
  local -a ids=()
  command -v i3-msg >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  ids_json="$(i3-msg -t get_bar_config 2>/dev/null)" || return 1
  mapfile -t ids < <(python3 -c 'import json, sys; data=json.load(sys.stdin); print("\n".join(data if isinstance(data, list) else []))' <<<"$ids_json")
  for id in "${ids[@]}"; do
    [[ -n "$id" ]] || continue
    config_json="$(i3-msg -t get_bar_config "$id" 2>/dev/null)" || continue
    height="$(python3 -c 'import json, sys; value=json.load(sys.stdin).get("bar_height"); print(value if isinstance(value, int) else "")' <<<"$config_json")"
    [[ "$height" =~ ^[0-9]+$ && "$height" -gt 0 ]] || continue
    if [[ -z "$first" ]]; then
      first="$height"
    elif [[ "$first" != "$height" ]]; then
      return 1
    fi
    count=$((count + 1))
  done
  ((count > 0)) || return 1
  printf '%s\n' "$first"
}

resolve_bar_height() {
  BAR_PROFILE="$(active_profile 2>/dev/null || true)"
  BAR_HEIGHT=''
  BAR_HEIGHT_SOURCE=''
  case "$BAR_PROFILE" in
    i3bar)
      BAR_HEIGHT="$(i3bar_height 2>/dev/null || true)"
      BAR_HEIGHT_SOURCE='i3 IPC get_bar_config'
      ;;
    tint2)
      BAR_HEIGHT="$(tint2_height 2>/dev/null || true)"
      BAR_HEIGHT_SOURCE="$BAR_CONFIG_DIR/tint2rc:panel_size"
      ;;
    polybar)
      BAR_HEIGHT="$(polybar_height 2>/dev/null || true)"
      BAR_HEIGHT_SOURCE="$BAR_CONFIG_DIR/polybar.ini:[bar/rafex] height"
      ;;
    *)
      BAR_HEIGHT_SOURCE="$ACTIVE_PROFILE_FILE"
      ;;
  esac
  if [[ "$BAR_HEIGHT" =~ ^[0-9]+$ && "$BAR_HEIGHT" -gt 0 ]]; then
    DUNST_OFFSET="(10, $BAR_HEIGHT)"
  else
    BAR_HEIGHT=''
    DUNST_OFFSET='(10, unknown)'
  fi
}

require_bar_height() {
  [[ "$BAR_HEIGHT" =~ ^[0-9]+$ && "$BAR_HEIGHT" -gt 0 ]] ||
    die "no se pudo determinar la altura de la barra activa (${BAR_PROFILE:-perfil desconocido}); no se modificará Dunst"
}

render_config() {
  local destination="$1"
  awk -v origin="$DUNST_ORIGIN" -v offset="$DUNST_OFFSET" '
    /^\[global\][[:space:]]*$/ {
      in_global=1
      found_global=1
      print
      next
    }
    in_global && /^[[:space:]]*\[/ {
      if (!found_origin) print "origin = " origin
      if (!found_offset) print "offset = " offset
      in_global=0
      print
      next
    }
    in_global && /^[[:space:]]*origin[[:space:]]*=/ {
      if (!found_origin) print "origin = " origin
      found_origin=1
      next
    }
    in_global && /^[[:space:]]*offset[[:space:]]*=/ {
      if (!found_offset) print "offset = " offset
      found_offset=1
      next
    }
    { print }
    END {
      if (in_global) {
        if (!found_origin) print "origin = " origin
        if (!found_offset) print "offset = " offset
      } else if (!found_global) {
        print ""
        print "[global]"
        print "origin = " origin
        print "offset = " offset
      }
    }
  ' "$THEME_CONFIG" > "$destination"
}

prepare_config() {
  local temporary
  [[ -f "$THEME_CONFIG" ]] || die "no existe la configuración activa de Dunst: $THEME_CONFIG"
  mkdir -p "$(dirname "$RUNTIME_CONFIG")"
  temporary="$(mktemp "${RUNTIME_CONFIG}.tmp.XXXXXX")"
  render_config "$temporary"
  if [[ -f "$RUNTIME_CONFIG" ]] && cmp -s "$RUNTIME_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  if [[ -e "$RUNTIME_CONFIG" ]]; then
    cp -a -- "$RUNTIME_CONFIG" "${RUNTIME_CONFIG}.bak.${STAMP}"
    info "respaldo creado: ${RUNTIME_CONFIG}.bak.${STAMP}"
  fi
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$RUNTIME_CONFIG"
}

reload_dunst() {
  if command -v dunstctl >/dev/null 2>&1 && dunstctl reload >/dev/null 2>&1; then
    ok "Dunst recargado"
  elif command -v pkill >/dev/null 2>&1 && pkill -HUP -x dunst 2>/dev/null; then
    ok "Dunst recargado mediante HUP"
  else
    warn "Dunst no pudo recargarse; comprueba la sesión gráfica"
  fi
}

show_status() {
  printf 'bar_profile=%s\n' "${BAR_PROFILE:-unknown}"
  printf 'bar_height=%s\n' "${BAR_HEIGHT:-unknown}"
  printf 'bar_height_source=%s\n' "$BAR_HEIGHT_SOURCE"
  printf 'dunst_origin=%s\n' "$DUNST_ORIGIN"
  printf 'dunst_offset=%s\n' "$DUNST_OFFSET"
  printf 'theme_config=%s\n' "$THEME_CONFIG"
  printf 'runtime_config=%s\n' "$RUNTIME_CONFIG"
  if [[ -n "$BAR_HEIGHT" && -f "$RUNTIME_CONFIG" ]] && grep -Fq "origin = $DUNST_ORIGIN" "$RUNTIME_CONFIG" \
      && grep -Fq "offset = $DUNST_OFFSET" "$RUNTIME_CONFIG"; then
    printf 'placement=ready\n'
  else
    printf 'placement=pending\n'
  fi
  if command -v pgrep >/dev/null 2>&1 && pgrep -x dunst >/dev/null 2>&1; then
    printf 'dunst=running\n'
  else
    printf 'dunst=stopped\n'
  fi
}

main() {
  parse_args "$@"
  require_commands
  resolve_bar_height

  case "$ACTION" in
    check)
      echo '═══ Dunst debajo de la barra activa ═══'
      show_status
      ;;
    plan)
      echo '═══ Plan Dunst debajo de la barra activa ═══'
      info "perfil de barra: ${BAR_PROFILE:-desconocido}"
      info "usar origin=$DUNST_ORIGIN y offset=$DUNST_OFFSET"
      info "generar $RUNTIME_CONFIG desde $THEME_CONFIG"
      [[ -n "$BAR_HEIGHT" ]] || warn 'altura desconocida: apply/start/reload quedarán bloqueados'
      info 'no se iniciará ni recargará Dunst'
      ;;
    apply)
      require_bar_height
      prepare_config
      ok "configuración Dunst lista: $RUNTIME_CONFIG"
      ;;
    start)
      require_bar_height
      prepare_config
      if pgrep -x dunst >/dev/null 2>&1; then
        reload_dunst
      else
        command -v dunst >/dev/null 2>&1 || die 'dunst no está instalado'
        exec dunst --config "$RUNTIME_CONFIG"
      fi
      ;;
    reload)
      require_bar_height
      prepare_config
      if pgrep -x dunst >/dev/null 2>&1; then
        reload_dunst
      else
        warn 'Dunst no está ejecutándose; usa --start para iniciarlo'
      fi
      ;;
  esac
}

main "$@"
