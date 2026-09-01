#!/usr/bin/env bash
# Lanzador común: controla únicamente la instancia Conky administrada por Rafex.
set -Eeuo pipefail
umask 077

ACTION="start"
CONFIG_FILE="${CONKY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/conky/conky.conf}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/rafex"
PID_FILE="$RUNTIME_DIR/conky-rafex.pid"

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
}

main "$@"
