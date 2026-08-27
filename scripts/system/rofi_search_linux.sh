#!/usr/bin/env bash
# shellcheck shell=bash
# Lanzador/buscador de aplicaciones para i3 mediante Rofi.
set -Eeuo pipefail

command -v rofi >/dev/null 2>&1 || {
  echo "No se encontró rofi." >&2
  exit 1
}

case "${1:-apps}" in
  apps) exec rofi -show drun -show-icons ;;
  combi) exec rofi -show combi -show-icons ;;
  run) exec rofi -show run ;;
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
