#!/usr/bin/env bash
# eww_widgets_linux.sh v1.0.0
# Abre/cierra los widgets opcionales EWW del perfil ThinkPad.
set -Eeuo pipefail
umask 077

ACTION=status
WINDOW=status

usage() { printf 'Uso: eww_widgets_linux.sh --open|--close [ventana] | --status\n'; }
while (($#)); do
  case "$1" in
    --open) ACTION=open;;
    --close) ACTION=close;;
    --status) ACTION=status;;
    --help|-h) usage; exit 0;;
    status) WINDOW=status;;
    *) WINDOW="$1";;
  esac
  shift
done

command -v eww >/dev/null 2>&1 || { printf '✗ ERROR: eww no está instalado\n' >&2; exit 1; }

case "$ACTION" in
  open)
    [[ -n "${DISPLAY:-}" ]] || { printf '✗ ERROR: DISPLAY ausente\n' >&2; exit 1; }
    if ! eww ping >/dev/null 2>&1; then
      eww daemon >/dev/null 2>&1 &
      sleep 1
    fi
    exec eww open "$WINDOW" --screen 0
    ;;
  close) exec eww close "$WINDOW";;
  status)
    eww ping >/dev/null 2>&1 && printf 'EWW daemon: activo\n' || printf 'EWW daemon: detenido\n'
    eww windows 2>/dev/null || true
    ;;
esac
