#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# wifi_off_linux.sh
# Apaga interfaces WiFi (interna, USB o ambas) usando NetworkManager.
# Si no se pasa argumento, muestra un menú interactivo con el estado actual.
# ─────────────────────────────────────────────────────────────────────────────

INTERNAL="${WIFI_OFF_INTERNAL:-wlp2s0}"
USB="${WIFI_OFF_USB:-wlxa047d76360c5}"

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
# Mostrar estado actual de las interfaces WiFi
# ─────────────────────────────────────────────────────────────────────────────
show_status() {
    echo -e "\n${BOLD}Estado actual de interfaces WiFi:${RESET}\n"
    while IFS=: read -r dev type state conn; do
        if [[ "$type" == "wifi" ]]; then
            local icon="  "
            case "$state" in
                connected)          icon="${GREEN}●${RESET}" ;;
                disconnected)       icon="${YELLOW}○${RESET}" ;;
                unavailable)        icon="${RED}✕${RESET}" ;;
                "connecting (configuring)"|"connecting (getting IP configuration)"|connecting)
                                    icon="${CYAN}◌${RESET}" ;;
                *)                  icon="  " ;;
            esac
            local conn_str="${conn:-—}"
            echo -e "  ${icon} ${BOLD}${dev}${RESET} — ${conn_str} (${state})"
        fi
    done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null)
    echo
}

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
    echo -e "  ${CYAN}all${RESET}        Apaga ambas interfaces (pide confirmación)"
    echo
    echo "  Sin argumentos → menú interactivo con estado actual"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}WIFI_OFF_INTERNAL${RESET}   Nombre de la interfaz interna (default: ${INTERNAL})"
    echo -e "  ${CYAN}WIFI_OFF_USB${RESET}        Nombre de la interfaz USB (default: ${USB})"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0                   # menú interactivo"
    echo "  $0 internal"
    echo "  $0 usb"
    echo "  $0 all               # apaga ambas (con confirmación)"
    echo "  WIFI_OFF_INTERNAL=wlan0 $0 internal"
}

# ─────────────────────────────────────────────────────────────────────────────
# Menú interactivo
# ─────────────────────────────────────────────────────────────────────────────
interactive_menu() {
    show_status
    echo -e "${BOLD}¿Qué WiFi querés apagar?${RESET}"
    echo -e "  ${CYAN}1)${RESET} Solo interna (${BOLD}${INTERNAL}${RESET})"
    echo -e "  ${CYAN}2)${RESET} Solo USB (${BOLD}${USB}${RESET})"
    echo -e "  ${CYAN}3)${RESET} Ambas"
    echo -e "  ${CYAN}q)${RESET} Cancelar"
    echo
    read -rp "Opción [q]: " OPT
    case "${OPT:-q}" in
        1) wifi_off_nmcli "$INTERNAL" ;;
        2) wifi_off_nmcli "$USB" ;;
        3)
            echo -e "\n${YELLOW}${BOLD}  ⚠  ATENCIÓN: vas a apagar TODAS las interfaces WiFi.${RESET}"
            read -rp "  ¿Confirmás? [s/N]: " CONFIRM
            if [[ "${CONFIRM,,}" == "s" || "${CONFIRM,,}" == "si" || "${CONFIRM,,}" == "sí" ]]; then
                wifi_off_nmcli "$INTERNAL"
                wifi_off_nmcli "$USB"
            else
                echo "  Cancelado."
                exit 0
            fi
            ;;
        *) echo "  Cancelado." ; exit 0 ;;
    esac
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
# Principal
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in
    internal)
        wifi_off_nmcli "$INTERNAL"
        ;;
    usb)
        wifi_off_nmcli "$USB"
        ;;
    all)
        show_status
        echo -e "${YELLOW}${BOLD}  ⚠  ATENCIÓN: vas a apagar TODAS las interfaces WiFi.${RESET}"
        read -rp "  ¿Confirmás? [s/N]: " CONFIRM
        if [[ "${CONFIRM,,}" == "s" || "${CONFIRM,,}" == "si" || "${CONFIRM,,}" == "sí" ]]; then
            wifi_off_nmcli "$INTERNAL"
            wifi_off_nmcli "$USB"
        else
            echo "  Cancelado."
            exit 0
        fi
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    "")
        interactive_menu
        ;;
    *)
        error "opción no reconocida: ${BOLD}${1:-}${RESET}"
        echo
        usage
        exit 1
        ;;
esac
