#!/usr/bin/env bash
# shellcheck shell=bash
#
# Fija el brillo por software de xrandr (--brightness) al iniciar/recargar
# i3, y lo vuelve a aplicar tras suspender/despertar mediante un hook de
# systemd-sleep (X11 resetea este valor a 1.0 en cada suspensión/reanudación
# o al reconectar el panel).
set -Eeuo pipefail
umask 077

# Si se ejecuta desde una shell no gráfica (tmux/SSH) que no exportó
# DISPLAY, se asume :0 -la sesión Xorg real de un laptop de un solo
# monitor-. Si no hay servidor X ahí, xrandr simplemente falla en
# silencio (2>/dev/null) y las funciones de abajo devuelven vacío, igual
# que si DISPLAY nunca hubiera estado definida.
export DISPLAY="${DISPLAY:-:0}"

ACTION='check'
OUTPUT="${XRANDR_BRIGHTNESS_OUTPUT:-}"
BRIGHTNESS="${XRANDR_BRIGHTNESS_VALUE:-1.1}"
TARGET_USER="$(id -un)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR='/var/backups/rafex-xrandr-brightness'
SLEEP_HOOK='/lib/systemd/system-sleep/rafex-xrandr-brightness.sh'
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
I3_BEGIN='# BEGIN rafex xrandr-brightness'
I3_END='# END rafex xrandr-brightness'

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
  configure_xrandr_brightness_linux.sh --check
  configure_xrandr_brightness_linux.sh --plan
  configure_xrandr_brightness_linux.sh --apply [--output SALIDA] [--brightness VALOR]

Opciones:
  --check              Diagnosticar sin modificar nada (default)
  --plan | --dry-run   Mostrar cambios previstos sin modificar nada
  --apply              Escribir el bloque en i3 y el hook de systemd-sleep
  --output SALIDA      Salida xrandr; por defecto detecta eDP/LVDS/DSI
  --brightness VALOR   Multiplicador de brillo (0.1-2.0); por defecto 1.1
  --help, -h           Mostrar esta ayuda

xrandr --brightness es un multiplicador de software (gamma), no controla el
backlight real -para eso usa notify_brightness_linux.sh (brightnessctl)-.
Sirve para compensar paneles con brillo máximo insuficiente.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --output)
        [[ $# -ge 2 ]] || die '--output requiere un valor'
        OUTPUT="$2"; shift 2 ;;
      --brightness)
        [[ $# -ge 2 ]] || die '--brightness requiere un valor'
        BRIGHTNESS="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  [[ "$BRIGHTNESS" =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
    die "valor de brillo inválido: $BRIGHTNESS (debe ser numérico, ej. 1.1)"
  awk -v v="$BRIGHTNESS" 'BEGIN { exit !(v >= 0.1 && v <= 2.0) }' ||
    die "valor de brillo fuera de rango razonable (0.1-2.0): $BRIGHTNESS"
}

require_linux() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script solo funciona en Linux'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"
}

detect_output() {
  [[ -n "$OUTPUT" ]] && { printf '%s\n' "$OUTPUT"; return 0; }
  [[ -n "${DISPLAY:-}" ]] || return 1
  xrandr --query 2>/dev/null |
    awk '$1 ~ /^(eDP|LVDS|DSI)-/ && $2 == "connected" { print $1; exit }'
}

current_brightness() {
  local output="$1"
  [[ -n "${DISPLAY:-}" ]] || return 1
  xrandr --verbose 2>/dev/null | awk -v o="$output" '
    $1 == o { found=1 }
    found && /Brightness:/ { print $2; exit }
  '
}

backup_root_file() {
  local file="$1" relative destination
  [[ -e "$file" ]] || return 0
  relative="${file#/}"
  destination="$BACKUP_DIR/${relative//\//_}.bak.${STAMP}"
  sudo install -d -m 0755 "$BACKUP_DIR"
  sudo cp -a -- "$file" "$destination"
  info "respaldo: $destination"
}

backup_colocated() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 0
  cp -a -- "$file" "$file.bak.$STAMP"
  info "respaldo: $file.bak.$STAMP"
}

# Parchea (idempotente, con respaldo) un bloque BEGIN/END en un archivo ya
# desplegado -mismo mecanismo que usa install_eww_linux.sh para su propio
# atajo en i3-, sin tocar nada fuera del bloque marcado.
replace_block() {
  local target="$1" begin="$2" end="$3" block_file="$4" temporary backup_fn="$5"
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) }
      $0 == begin { if (!found) emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
      END { if (!found) { print ""; emit() } }
    ' "$target" > "$temporary"
    if cmp -s "$target" "$temporary"; then
      rm -f -- "$temporary"
      return 0
    fi
    "$backup_fn" "$target"
  else
    mkdir -p -- "$(dirname -- "$target")"
    cat "$block_file" > "$temporary"
  fi
  mv -f -- "$temporary" "$target"
}

sleep_hook_content() {
  local output="$1" brightness="$2"
  cat <<EOF
#!/bin/sh
# Gestionado por configure_xrandr_brightness_linux.sh. No editar manualmente.
# X11 resetea xrandr --brightness a 1.0 al suspender/reanudar; este hook lo
# vuelve a aplicar justo después de reanudar.
case "\$1" in
  post)
    export DISPLAY=:0
    export XAUTHORITY="$(eval echo ~"$TARGET_USER")/.Xauthority"
    su "$TARGET_USER" -c "xrandr --output '${output}' --brightness '${brightness}'" || true
    ;;
esac
EOF
}

check_status() {
  local output current
  echo
  echo -e "${BOLD}${CYAN}═══ Brillo xrandr ═══${RESET}"
  output="$(detect_output || true)"
  if [[ -n "$output" ]]; then
    ok "salida detectada: $output"
  else
    warn 'no se detectó una salida interna eDP/LVDS/DSI (o no hay sesión gráfica)'
  fi
  printf 'brillo objetivo=%s\n' "$BRIGHTNESS"
  if [[ -n "$output" ]] && current="$(current_brightness "$output")" && [[ -n "$current" ]]; then
    printf 'brillo actual=%s\n' "$current"
  else
    warn 'no se pudo leer el brillo actual (requiere sesión Xorg activa)'
  fi
  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG"; then
    ok "bloque configurado en i3: $I3_CONFIG"
  else
    warn "sin bloque en i3 (usa --apply para agregarlo): $I3_CONFIG"
  fi
  if [[ -x "$SLEEP_HOOK" ]]; then
    ok "hook de systemd-sleep presente y ejecutable: $SLEEP_HOOK"
  else
    warn "hook de systemd-sleep ausente: $SLEEP_HOOK"
  fi
}

configure_i3() {
  local output="$1" block
  block="$(mktemp)"
  cat > "$block" <<EOF
$I3_BEGIN
exec_always --no-startup-id xrandr --output $output --brightness $BRIGHTNESS
$I3_END
EOF
  replace_block "$I3_CONFIG" "$I3_BEGIN" "$I3_END" "$block" backup_colocated
  rm -f -- "$block"
  ok "bloque de brillo configurado en $I3_CONFIG (recarga i3 con \$mod+Shift+r)"
}

configure_sleep_hook() {
  local output="$1" temporary
  temporary="$(mktemp)"
  sleep_hook_content "$output" "$BRIGHTNESS" > "$temporary"
  if sudo -n test -f "$SLEEP_HOOK" 2>/dev/null && sudo -n cmp -s "$temporary" "$SLEEP_HOOK" 2>/dev/null; then
    rm -f -- "$temporary"
    ok "sin cambios: $SLEEP_HOOK"
    return 0
  fi
  backup_root_file "$SLEEP_HOOK"
  sudo install -D -m 0755 "$temporary" "$SLEEP_HOOK"
  rm -f -- "$temporary"
  ok "hook de systemd-sleep instalado: $SLEEP_HOOK"
}

main() {
  parse_args "$@"
  require_linux
  require_command xrandr

  if [[ "$ACTION" == 'check' ]]; then
    check_status
    exit 0
  fi

  local output
  output="$(detect_output || true)"
  [[ -n "$output" ]] || die 'no se pudo determinar la salida xrandr; usa --output SALIDA'

  if [[ "$ACTION" == 'plan' ]]; then
    echo
    echo -e "${BOLD}${CYAN}═══ Plan brillo xrandr ═══${RESET}"
    info "salida: $output   brillo: $BRIGHTNESS"
    info "[plan] agregar bloque exec_always en $I3_CONFIG"
    info "[plan] escribir $SLEEP_HOOK (sudo)"
    exit 0
  fi

  command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  configure_i3 "$output"
  sudo -v
  configure_sleep_hook "$output"
  ok 'brillo xrandr configurado para i3 y para reanudar de suspensión'
  check_status
}

main "$@"
