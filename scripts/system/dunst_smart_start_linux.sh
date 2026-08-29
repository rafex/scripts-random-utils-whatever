#!/usr/bin/env bash
# shellcheck shell=bash
# Inicia o recarga Dunst dejando libre el espacio ocupado por i3bar.
set -Eeuo pipefail
umask 077

ACTION="check"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
I3_CONFIG="${I3_CONFIG:-$CONFIG_HOME/i3/config}"
THEME_CONFIG="${DUNST_THEME_CONFIG:-$CONFIG_HOME/rafex/themes/current/dunst.conf}"
RUNTIME_CONFIG="${DUNST_SMART_CONFIG:-$CONFIG_HOME/rafex/dunst.conf}"
BAR_MARGIN="${DUNST_BAR_MARGIN:-36}"
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
  --check       Detecta la posición de i3bar sin modificar archivos.
  --plan        Muestra la configuración Dunst que se generaría.
  --apply       Genera la configuración estable sin iniciar Dunst.
  --start       Genera la configuración y arranca o recarga Dunst.
  --reload      Regenera y recarga Dunst si ya está ejecutándose.
  --help        Muestra esta ayuda.

El margen vertical predeterminado es 36 píxeles. Puede cambiarse con
DUNST_BAR_MARGIN. No requiere sudo.
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
  [[ "$BAR_MARGIN" =~ ^[0-9]+$ ]] || die "DUNST_BAR_MARGIN debe ser un entero no negativo"
}

require_commands() {
  [[ "$(uname -s)" == Linux ]] || die "este script solo funciona en Linux"
  local command_name
  for command_name in awk cmp cp date grep mkdir mktemp mv; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
  if [[ "$ACTION" == start || "$ACTION" == reload ]]; then
    command -v pgrep >/dev/null 2>&1 || die "falta la herramienta: pgrep"
  fi
}

bar_position() {
  local detected
  if [[ -n "${DUNST_BAR_POSITION:-}" ]]; then
    case "$DUNST_BAR_POSITION" in
      top|bottom) printf '%s\n' "$DUNST_BAR_POSITION"; return 0 ;;
      *) die "DUNST_BAR_POSITION debe ser top o bottom" ;;
    esac
  fi
  if [[ -f "$I3_CONFIG" ]]; then
    detected="$(awk '
      /^[[:space:]]*bar[[:space:]]*\{/ { in_bar=1; next }
      in_bar && /^[[:space:]]*position[[:space:]]+(top|bottom)([[:space:]]|$)/ { print $2; exit }
      in_bar && /^[[:space:]]*}/ { in_bar=0 }
    ' "$I3_CONFIG")"
    [[ "$detected" == top || "$detected" == bottom ]] && {
      printf '%s\n' "$detected"
      return 0
    }
  fi
  printf '%s\n' bottom
}

set_placement() {
  local position="$1"
  case "$position" in
    top)
      DUNST_ORIGIN="top-right"
      ;;
    bottom)
      DUNST_ORIGIN="bottom-right"
      ;;
    *) die "posición de i3bar inválida: $position" ;;
  esac
  DUNST_OFFSET="(10, $BAR_MARGIN)"
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
  local position="$1"
  printf 'i3bar_position=%s\n' "$position"
  printf 'dunst_origin=%s\n' "$DUNST_ORIGIN"
  printf 'dunst_offset=%s\n' "$DUNST_OFFSET"
  printf 'theme_config=%s\n' "$THEME_CONFIG"
  printf 'runtime_config=%s\n' "$RUNTIME_CONFIG"
  if [[ -f "$RUNTIME_CONFIG" ]] && grep -Fq "origin = $DUNST_ORIGIN" "$RUNTIME_CONFIG" \
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
  local position
  position="$(bar_position)"
  set_placement "$position"

  case "$ACTION" in
    check)
      echo '═══ Dunst adaptado a i3bar ═══'
      show_status "$position"
      ;;
    plan)
      echo '═══ Plan Dunst adaptado a i3bar ═══'
      info "i3bar detectado en: $position"
      info "usar origin=$DUNST_ORIGIN y offset=$DUNST_OFFSET"
      info "generar $RUNTIME_CONFIG desde $THEME_CONFIG"
      info 'no se iniciará ni recargará Dunst'
      ;;
    apply)
      prepare_config
      ok "configuración Dunst lista: $RUNTIME_CONFIG"
      ;;
    start)
      prepare_config
      if pgrep -x dunst >/dev/null 2>&1; then
        reload_dunst
      else
        command -v dunst >/dev/null 2>&1 || die 'dunst no está instalado'
        exec dunst --config "$RUNTIME_CONFIG"
      fi
      ;;
    reload)
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
