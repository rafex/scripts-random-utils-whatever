#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# wifi_connect_linux.sh
# Conecta a una red WiFi usando NetworkManager (nmcli).
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 <SSID> [password]"
    echo
    echo -e "${BOLD}Argumentos:${RESET}"
    echo -e "  ${CYAN}SSID${RESET}       Nombre de la red WiFi a la que conectarse"
    echo -e "  ${CYAN}password${RESET}   Contraseña de la red (si se omite, se solicita interactivamente)"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}WIFI_PASSWORD${RESET}   Contraseña (alternativa al argumento o prompt)"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 MiRed miPassword123"
    echo "  $0 MiRed                 # pedirá la contraseña"
    echo "  WIFI_PASSWORD=securePass $0 MiRed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones previas
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    if ! command -v nmcli &>/dev/null; then
        error "nmcli no está instalado. Requiere NetworkManager."
        exit 1
    fi

    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        error "NetworkManager no está activo."
        exit 1
    fi

    if ! nmcli radio wifi 2>/dev/null | grep -q enabled; then
        warn "WiFi está desactivado. Activando..."
        nmcli radio wifi on
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    error "debes especificar un SSID."
    echo
    usage
    exit 1
fi

SSID="$1"
PASSWORD="${2:-${WIFI_PASSWORD:-}}"

preflight

if [[ -z "$PASSWORD" ]]; then
    read -rsp "Contraseña para ${SSID}: " PASSWORD
    echo
fi

if [[ -z "$PASSWORD" ]]; then
    error "la contraseña no puede estar vacía."
    exit 1
fi

info "Conectando a ${BOLD}${SSID}${RESET}..."
if nmcli device wifi connect "$SSID" password "$PASSWORD" 2>&1; then
    success "Conectado a ${BOLD}${SSID}${RESET}."
else
    error "no se pudo conectar a ${BOLD}${SSID}${RESET}."
    exit 1
fi
