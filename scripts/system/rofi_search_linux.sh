#!/usr/bin/env bash
# shellcheck shell=bash
# Lanzador/buscador de aplicaciones para i3 mediante Rofi.
set -Eeuo pipefail

command -v rofi >/dev/null 2>&1 || {
  echo "No se encontró rofi." >&2
  exit 1
}

kill_stale_rofi() {
  # Mata cualquier instancia previa de rofi -incluida una colgada e
  # invisible que bloquea nuevos lanzamientos por el mecanismo de
  # instancia única de rofi- antes de abrir una nueva. -x coincide solo
  # con el nombre exacto de proceso "rofi", nunca con otro binario.
  pkill -x rofi 2>/dev/null || true
}

case "${1:-apps}" in
  apps) kill_stale_rofi; exec rofi -show drun -show-icons ;;
  combi) kill_stale_rofi; exec rofi -show combi -show-icons ;;
  run) kill_stale_rofi; exec rofi -show run ;;
  browser)
    if command -v xdg-open >/dev/null 2>&1; then
      exec xdg-open "${BROWSER_START_URL:-https://www.google.com}"
    fi
    echo "No se encontró xdg-open." >&2
    exit 1
    ;;
  -h|--help)
    echo "Uso: $0 [apps|combi|run|browser]"
    ;;
  *) echo "Uso: $0 [apps|combi|run|browser]" >&2; exit 1 ;;
esac
