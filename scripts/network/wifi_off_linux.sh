#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# wifi_off_linux.sh
# Apaga interfaces WiFi (interna, USB o ambas) usando NetworkManager / rfkill.
# ─────────────────────────────────────────────────────────────────────────────

INTERNAL="${WIFI_OFF_INTERNAL:-wlp2s0}"
USB="${WIFI_OFF_USB:-wlxa047d76360c5}"
USE_RFKILL="${WIFI_OFF_RFKILL:-0}"

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
    echo "  $0 [internal|usb|all|--help]"
    echo
    echo -e "${BOLD}Modos:${RESET}"
    echo -e "  ${CYAN}internal${RESET}  Apaga solo la interfaz WiFi interna (${BOLD}${INTERNAL}${RESET})"
    echo -e "  ${CYAN}usb${RESET}       Apaga solo la interfaz WiFi USB (${BOLD}${USB}${RESET})"
    echo -e "  ${CYAN}all${RESET}        Apaga ambas interfaces"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}WIFI_OFF_INTERNAL${RESET}   Nombre de la interfaz interna (default: ${INTERNAL})"
    echo -e "  ${CYAN}WIFI_OFF_USB${RESET}        Nombre de la interfaz USB (default: ${USB})"
    echo -e "  ${CYAN}WIFI_OFF_RFKILL${RESET}     Usar rfkill en lugar de nmcli (0|1, default: 0)"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 internal"
    echo "  $0 usb"
    echo "  $0 all"
    echo "  WIFI_OFF_INTERNAL=wlan0 $0 internal"
}

# ─────────────────────────────────────────────────────────────────────────────
# Apagar interfaz con nmcli
# ─────────────────────────────────────────────────────────────────────────────
wifi_off_nmcli() {
    local iface="$1"

    if ! nmcli device status 2>/dev/null | grep -q "^${iface}"; then
        warn "Interfaz ${BOLD}${iface}${RESET} no encontrada en NetworkManager. Se omite."
        return 0
    fi

    info "Desconectando ${BOLD}${iface}${RESET}..."
    nmcli device disconnect "${iface}" 2>/dev/null || true

    info "Poniendo ${BOLD}${iface}${RESET} en modo no gestionado..."
    nmcli device set "${iface}" managed false 2>/dev/null || true

    success "${BOLD}${iface}${RESET} apagada."
}

# ─────────────────────────────────────────────────────────────────────────────
# Apagar con rfkill (hard-block)
# ─────────────────────────────────────────────────────────────────────────────
wifi_off_rfkill() {
    if ! command -v rfkill &>/dev/null; then
        error "rfkill no está instalado."
        exit 1
    fi
    info "Bloqueando todas las radios WiFi con ${BOLD}rfkill${RESET}..."
    rfkill block wifi
    success "WiFi bloqueado (rfkill)."
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-all}" in
    internal)
        wifi_off_nmcli "$INTERNAL"
        ;;
    usb)
        wifi_off_nmcli "$USB"
        ;;
    all)
        if [[ "$USE_RFKILL" == "1" ]] && command -v rfkill &>/dev/null; then
            wifi_off_rfkill
        else
            wifi_off_nmcli "$INTERNAL"
            wifi_off_nmcli "$USB"
        fi
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        error "opción no reconocida: ${BOLD}${1:-}${RESET}"
        echo
        usage
        exit 1
        ;;
esac
