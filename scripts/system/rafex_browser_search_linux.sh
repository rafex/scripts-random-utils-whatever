#!/usr/bin/env bash
# rafex_browser_search_linux.sh v1.0.0
# Abre una búsqueda del perfil ThinkPad en DuckDuckGo con el navegador disponible.
set -Eeuo pipefail

url='https://duckduckgo.com/'
if command -v firefox >/dev/null 2>&1; then
  exec firefox --new-tab "$url"
fi
if command -v firefox-esr >/dev/null 2>&1; then
  exec firefox-esr --new-tab "$url"
fi
if command -v notify-send >/dev/null 2>&1; then
  notify-send 'Búsqueda' 'Firefox no está instalado'
fi
printf '%s\n' 'Firefox no está instalado.' >&2
exit 1
