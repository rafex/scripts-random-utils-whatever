#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# wifi_scan_linux.sh
# Escanea y muestra las redes WiFi disponibles usando NetworkManager.
# ─────────────────────────────────────────────────────────────────────────────

MAX_RESULTS="${WIFI_SCAN_MAX:-50}"

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [--help]"
    echo
    echo -e "${BOLD}Descripción:${RESET}"
    echo "  Realiza un re-scan y lista las redes WiFi en rango."
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}WIFI_SCAN_MAX${RESET}   Máximo de redes a mostrar (default: 50)"
    echo
    echo -e "${BOLD}Ejemplo:${RESET}"
    echo "  $0"
    echo "  WIFI_SCAN_MAX=10 $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if ! command -v nmcli &>/dev/null; then
    echo -e "${RED}  ✗ ERROR:${RESET} nmcli no está instalado. Requiere NetworkManager." >&2
    exit 1
fi

info "Escaneando redes WiFi..."
nmcli device wifi rescan 2>/dev/null || true
sleep 2

echo
nmcli -t -f SSID,SECURITY,SIGNAL,BARS,CHAN device wifi list 2>/dev/null \
    | head -n "$MAX_RESULTS" \
    | column -t -s ":" -N "${BOLD}SSID${RESET},SEGURIDAD,SEÑAL%,BARRAS,CANAL"

total=$(nmcli -t -f SSID device wifi list 2>/dev/null | wc -l)
echo
echo -e "${GREEN}${BOLD}  ✓${RESET} Total: ${BOLD}${total}${RESET} redes detectadas."
