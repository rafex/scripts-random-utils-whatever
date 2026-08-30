#!/usr/bin/env bash
# shellcheck shell=bash
# Activa o desactiva picom sin sudo y conserva la preferencia de Openbox.
set -Eeuo pipefail

ACTION="toggle"
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/openbox-picom-enabled"
CONFIG_FILE="${PICOM_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/picom/picom.conf}"

usage() {
  cat <<'EOF'
Uso:
  picom_toggle_linux.sh --check
  picom_toggle_linux.sh --enable
  picom_toggle_linux.sh --disable
  picom_toggle_linux.sh --toggle
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --enable) ACTION="enable"; shift ;;
      --disable) ACTION="disable"; shift ;;
      --toggle) ACTION="toggle"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

running() { pgrep -x picom >/dev/null 2>&1; }

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -t 1500 "Picom" "$1" || true
}

set_state() {
  local enabled="$1"
  mkdir -p "$(dirname "$STATE_FILE")"
  if [[ "$enabled" == yes ]]; then
    printf '%s\n' enabled > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
  else
    rm -f -- "$STATE_FILE"
  fi
}

start_picom() {
  command -v picom >/dev/null 2>&1 || { echo "picom no está instalado." >&2; return 1; }
  if running; then return 0; fi
  if [[ -f "$CONFIG_FILE" ]]; then
    picom --config "$CONFIG_FILE" >/dev/null 2>&1 &
  else
    picom >/dev/null 2>&1 &
  fi
}

main() {
  parse_args "$@"
  command -v pgrep >/dev/null 2>&1 || { echo "pgrep no está disponible." >&2; exit 1; }
  if [[ "$ACTION" == check ]]; then
    if running; then echo "picom=running"; else echo "picom=stopped"; fi
    if [[ -f "$STATE_FILE" ]]; then echo "autostart=enabled"; else echo "autostart=disabled"; fi
    echo "config=$CONFIG_FILE"
    return 0
  fi
  case "$ACTION" in
    enable)
      set_state yes
      start_picom
      notify "Activado"
      ;;
    disable)
      set_state no
      pkill -TERM -x picom 2>/dev/null || true
      notify "Desactivado"
      ;;
    toggle)
      if running; then
        set_state no
        pkill -TERM -x picom 2>/dev/null || true
        notify "Desactivado"
      else
        set_state yes
        start_picom
        notify "Activado"
      fi
      ;;
  esac
}

main "$@"
