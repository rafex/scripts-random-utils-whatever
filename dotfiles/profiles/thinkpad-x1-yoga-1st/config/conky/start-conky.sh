#!/usr/bin/env bash
# Lanzador común: controla únicamente la instancia Conky administrada por Rafex.
set -Eeuo pipefail
umask 077

ACTION="start"
CONFIG_FILE="${CONKY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/conky/conky.conf}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/rafex"
PID_FILE="$RUNTIME_DIR/conky-rafex.pid"
PANEL_LEFT=18
PANEL_TOP=34
PANEL_WIDTH=320
PANEL_BOTTOM=10

pid_is_ours() {
  local pid cmdline
  [[ -r "$PID_FILE" ]] || return 1
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ -r "/proc/$pid/cmdline" ]] || return 1
  cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  [[ "$cmdline" == *"$CONFIG_FILE"* ]]
}

stop_ours() {
  local pid still_running=0
  if pid_is_ours; then
    pid="$(cat "$PID_FILE")"
    kill -TERM "$pid" 2>/dev/null || true
    still_running=1
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then
        still_running=0
        break
      fi
      sleep 0.2
    done
    if [[ "$still_running" -eq 1 ]]; then
      echo 'Conky no terminó a tiempo; no se iniciará una segunda instancia.' >&2
      return 1
    fi
  fi
  rm -f -- "$PID_FILE"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reload) ACTION=reload; shift ;;
      --stop) ACTION=stop; shift ;;
      -h|--help)
        printf '%s\n' 'Uso: start-conky.sh [--reload|--stop]'
        exit 0
        ;;
      *) echo "argumento desconocido: $1" >&2; exit 2 ;;
    esac
  done
}

apply_window_layout() {
  local window_id screen_height panel_height
  command -v wmctrl >/dev/null 2>&1 || return 0
  command -v xwininfo >/dev/null 2>&1 || return 0

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    window_id="$(LC_ALL=C xwininfo -root -tree 2>/dev/null |
      awk '$0 ~ /\("RafexConky" "RafexConky"\)/ {print $1; exit}')"
    [[ -n "$window_id" ]] && break
    sleep 0.2
  done
  [[ -n "${window_id:-}" ]] || return 0

  read -r _ screen_height < <(
    LC_ALL=C wmctrl -d 2>/dev/null |
      awk '$3 == "DG:" {split($4, size, "x"); print size[1], size[2]; exit}'
  )
  if [[ -z "${screen_height:-}" ]] && command -v xwininfo >/dev/null 2>&1; then
    read -r _ screen_height < <(
      LC_ALL=C xwininfo -root 2>/dev/null |
        awk '/Width:/ {width=$2} /Height:/ {height=$2} END {print width, height}'
    )
  fi
  [[ "${screen_height:-}" =~ ^[0-9]+$ ]] || screen_height=1080
  panel_height=$((screen_height - PANEL_TOP - PANEL_BOTTOM))
  (( panel_height > 300 )) || panel_height=300

  LC_ALL=C wmctrl -i -r "$window_id" -b add,below,sticky,skip_taskbar,skip_pager >/dev/null 2>&1 || true
  LC_ALL=C wmctrl -i -r "$window_id" -e "0,$PANEL_LEFT,$PANEL_TOP,$PANEL_WIDTH,$panel_height" >/dev/null 2>&1 || true
}

main() {
  parse_args "$@"
  if [[ "$ACTION" == stop ]]; then stop_ours; exit 0; fi
  [[ -n "${DISPLAY:-}" ]] || { echo 'Conky no se inicia: no existe DISPLAY.' >&2; exit 0; }
  [[ -f "$CONFIG_FILE" ]] || { echo "falta $CONFIG_FILE" >&2; exit 1; }
  command -v conky >/dev/null 2>&1 || { echo 'conky no está instalado' >&2; exit 1; }
  if [[ "$ACTION" == reload ]]; then stop_ours; fi
  if pid_is_ours; then exit 0; fi
  if pgrep -u "$(id -u)" -x conky >/dev/null 2>&1; then
    echo 'Aviso: existe otra instancia Conky del usuario; no se detendrá.' >&2
  fi
  mkdir -p "$RUNTIME_DIR"
  conky -c "$CONFIG_FILE" >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$PID_FILE"
  chmod 600 "$PID_FILE"
  apply_window_layout &
}

main "$@"
