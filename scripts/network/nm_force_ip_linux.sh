#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# nm_force_ip_linux.sh
# Diagnostica y fuerza la obtención de IP en una interfaz de red.
# Detecta el stack de red activo (NetworkManager, systemd-networkd, dhcpcd,
# ifupdown, dhclient) y usa las herramientas adecuadas sin conflictos.
# ─────────────────────────────────────────────────────────────────────────────

IFACE=""
MODE="check"
STATIC_IP=""
STATIC_GW=""
STATIC_DNS=""
AUTO_NEG=""
DRY_RUN=0

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗${RESET} $*"; }
fatal()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 <iface> [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--check${RESET}                 Diagnostica la interfaz sin modificar (default)"
    echo -e "  ${CYAN}--dhcp${RESET}                  Fuerza la renovación DHCP de la interfaz"
    echo -e "  ${CYAN}--release${RESET}               Libera lease DHCP y renueva"
    echo -e "  ${CYAN}--static <IP/CIDR>${RESET}       Configura IP estática"
    echo -e "  ${CYAN}--gateway <GW>${RESET}           Gateway (usar con --static)"
    echo -e "  ${CYAN}--dns <DNS>${RESET}              Servidores DNS (usar con --static)"
    echo -e "  ${CYAN}--auto-neg <on|off>${RESET}      Activa/desactiva auto-negociación (ethtool)"
    echo -e "  ${CYAN}--show-stack${RESET}             Solo mostrar el stack de red detectado"
    echo -e "  ${CYAN}--dry-run${RESET}                Simular sin ejecutar comandos de modificación"
    echo -e "  ${CYAN}-h, --help${RESET}               Mostrar esta ayuda"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 enp1s0f0 --check"
    echo "  $0 enp1s0f0 --dhcp"
    echo "  $0 enp1s0f0 --static 192.168.3.50/24 --gateway 192.168.3.1 --dns 192.168.3.1"
    echo "  $0 enp1s0f0 --auto-neg on"
    echo "  $0 enp1s0f0 --release"
    echo "  sudo $0 enp1s0f0 --dhcp"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers para comandos con sudo
# ─────────────────────────────────────────────────────────────────────────────
need_sudo() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] requeriría sudo: $*"
        return 0
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return $?
    fi
    if sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        warn "Se requiere sudo para ejecutar:"
        warn "  ${BOLD}$*${RESET}"
        warn "Ejecuta el script con: ${CYAN}sudo $0 $IFACE --${MODE}${RESET}"
        return 1
    fi
}

run_cmd() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] $*"
        return 0
    fi
    "$@"
}

run_sudo() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] sudo $*"
        return 0
    fi
    need_sudo "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then
        fatal "faltan argumentos."; echo; usage; exit 1
    fi

    IFACE="$1"; shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)       MODE="check"; shift ;;
            --dhcp)        MODE="dhcp"; shift ;;
            --release)     MODE="release"; shift ;;
            --static)      MODE="static"; STATIC_IP="$2"; shift 2 ;;
            --gateway)     STATIC_GW="$2"; shift 2 ;;
            --dns)         STATIC_DNS="$2"; shift 2 ;;
            --auto-neg)    MODE="autoneg"; AUTO_NEG="$2"; shift 2 ;;
            --show-stack)  MODE="show-stack"; shift ;;
            --dry-run)     DRY_RUN=1; shift ;;
            -h|--help)     usage; exit 0 ;;
            *) fatal "argumento desconocido: $1"; echo; usage; exit 1 ;;
        esac
    done

    if [[ ! -d "/sys/class/net/$IFACE" ]]; then
        fatal "interfaz ${BOLD}$IFACE${RESET} no existe."
        echo; echo "Interfaces disponibles:"
        ip -br link 2>/dev/null | awk '{print "  " $1}' || ls /sys/class/net/
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Detectar stack de red
# ─────────────────────────────────────────────────────────────────────────────
detect_network_stack() {
    NET_STACK=""
    NM_ACTIVE=0
    NETWORKD_ACTIVE=0
    DHCPCD_ACTIVE=0
    IFUPDOWN_ACTIVE=0
    NETPLAN_ACTIVE=0

    if systemctl is-active --quiet NetworkManager 2>/dev/null && command -v nmcli &>/dev/null; then
        NET_STACK="NetworkManager"
        NM_ACTIVE=1
    elif systemctl is-active --quiet systemd-networkd 2>/dev/null && command -v networkctl &>/dev/null; then
        NET_STACK="systemd-networkd"
        NETWORKD_ACTIVE=1
    elif systemctl is-active --quiet dhcpcd 2>/dev/null && command -v dhcpcd &>/dev/null; then
        NET_STACK="dhcpcd (standalone)"
        DHCPCD_ACTIVE=1
    elif command -v dhclient &>/dev/null; then
        NET_STACK="dhclient (standalone)"
    elif [[ -f /etc/network/interfaces ]] && grep -q "iface $IFACE" /etc/network/interfaces 2>/dev/null; then
        NET_STACK="ifupdown"
        IFUPDOWN_ACTIVE=1
    else
        NET_STACK="desconocido"
    fi

    if command -v netplan &>/dev/null && netplan get 2>/dev/null | grep -q "$IFACE"; then
        NETPLAN_ACTIVE=1
    fi
}

detect_dhcp_client() {
    DHCP_CLIENT=""

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        local nm_dhcp
        nm_dhcp="$(grep -E '^\s*\[main\]' -A 50 /etc/NetworkManager/NetworkManager.conf 2>/dev/null | grep -i "dhcp=" | awk -F= '{print $2}' | tr -d ' ')" || true
        nm_dhcp="${nm_dhcp:-internal}"
        DHCP_CLIENT="NM-${nm_dhcp}"
    elif [[ "$DHCPCD_ACTIVE" -eq 1 ]]; then
        DHCP_CLIENT="dhcpcd"
    elif command -v dhclient &>/dev/null; then
        DHCP_CLIENT="dhclient"
    fi
}

detect_conflicts() {
    local conflicts=()

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        if systemctl is-active --quiet dhcpcd 2>/dev/null; then
            conflicts+=("NetworkManager y dhcpcd están activos simultáneamente")
        fi
        if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
            conflicts+=("NetworkManager y systemd-networkd están activos simultáneamente")
        fi
    elif [[ "$NETWORKD_ACTIVE" -eq 1 ]]; then
        if systemctl is-active --quiet dhcpcd 2>/dev/null; then
            conflicts+=("systemd-networkd y dhcpcd están activos simultáneamente")
        fi
    fi

    if dpkg -l 2>/dev/null | grep -qE '^ii.*isc-dhcp-client' && dpkg -l 2>/dev/null | grep -qE '^ii.*dhcpcd-base'; then
        conflicts+=("isc-dhcp-client y dhcpcd-base ambos instalados (posible conflicto)")
    fi

    CONFLICTS=("${conflicts[@]:-}")
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar interfaz
# ─────────────────────────────────────────────────────────────────────────────
check_iface() {
    echo -e "\n${BOLD}${CYAN}═══ Estado de interfaz: ${IFACE} ═══${RESET}"

    local carrier operstate driver mac mtu
    carrier="$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo "?")"
    operstate="$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null || echo "?")"
    driver="$(basename "$(readlink "/sys/class/net/$IFACE/device/driver" 2>/dev/null)" 2>/dev/null || echo "?")"
    mac="$(cat "/sys/class/net/$IFACE/address" 2>/dev/null || echo "?")"
    mtu="$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null || echo "?")"

    if [[ "$carrier" == "1" ]]; then
        success "Carrier: ${BOLD}conectado${RESET} (cable detectado)"
    else
        error "Carrier: ${BOLD}desconectado${RESET} (sin cable / enlace físico)"
    fi
    info "Operstate: ${BOLD}$operstate${RESET}"
    info "Driver: ${BOLD}$driver${RESET}"
    info "MAC: ${BOLD}$mac${RESET}"
    info "MTU: ${BOLD}$mtu${RESET}"

    echo
    info "Direcciones IP actuales:"
    ip -br addr show "$IFACE" 2>/dev/null | awk '{print "  " $0}' || true

    if command -v ethtool &>/dev/null; then
        echo
        info "Link ethtool:"
        ethtool "$IFACE" 2>/dev/null | grep -iE "Speed|Duplex|Auto|Link detected" | sed 's/^/  /' || info "  (no disponible)"
    fi
}

check_nm_iface() {
    if [[ "$NM_ACTIVE" -ne 1 ]]; then
        return
    fi

    echo -e "\n${BOLD}${CYAN}═══ NetworkManager: ${IFACE} ═══${RESET}"

    info "Estado NM del dispositivo:"
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | grep "^${IFACE}:" | while IFS=: read -r dev type state con; do
        case "$state" in
            "conectado"|"connected")    success "  $dev ($type): ${BOLD}$state${RESET} (con: $con)" ;;
            "desconectado"|"disconnected") error "  $dev ($type): ${BOLD}$state${RESET}" ;;
            *)                            warn "  $dev ($type): ${BOLD}$state${RESET}" ;;
        esac
    done

    if nmcli connection show "$IFACE" &>/dev/null; then
        echo
        info "Configuración de la conexión NM:"
        nmcli connection show "$IFACE" 2>/dev/null | grep -iE "ipv4\.method|ipv4\.addresses|ipv4\.gateway|ipv4\.dns|autoconnect|802-3-ethernet\.auto-negotiate" | sed 's/^/  /'
    else
        warn "No hay conexión NM definida para ${BOLD}$IFACE${RESET}."
    fi

    echo
    info "DHCP leases:"
    local found=0
    for f in /var/lib/NetworkManager/*.lease /var/lib/dhcp/*; do
        [[ -f "$f" ]] || continue
        if [[ "$f" == *"$IFACE"* ]]; then
            info "  $f"
            found=1
        fi
    done 2>/dev/null
    [[ "$found" -eq 0 ]] && info "  (sin leases para $IFACE)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --check (diagnóstico completo sin modificar)
# ─────────────────────────────────────────────────────────────────────────────
do_check() {
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Diagnóstico de red: ${IFACE}${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    detect_network_stack
    detect_dhcp_client
    detect_conflicts

    echo -e "\n${BOLD}${CYAN}═══ Stack de red detectado ═══${RESET}"
    if [[ -n "$NET_STACK" ]]; then
        success "Stack: ${BOLD}$NET_STACK${RESET}"
    fi
    if [[ -n "$DHCP_CLIENT" ]]; then
        success "DHCP client: ${BOLD}$DHCP_CLIENT${RESET}"
    fi
    if [[ "$NETPLAN_ACTIVE" -eq 1 ]]; then
        warn "netplan detectado — puede interferir con NM/networkd."
    fi

    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        echo
        warn "${BOLD}Conflictos detectados:${RESET}"
        for c in "${CONFLICTS[@]}"; do
            warn "  - $c"
        done
    fi

    check_iface
    check_nm_iface

    echo
    local hw
    hw="$(lspci 2>/dev/null | grep -i ethernet | head -1)" || hw="$(lsusb 2>/dev/null | grep -i ethernet | head -1)" || true
    if [[ -n "$hw" ]]; then
        info "Hardware: ${BOLD}$hw${RESET}"
    fi

    echo
    info "DHCP leases stale:"
    find /var/lib/dhcp /var/lib/NetworkManager /var/lib/dhcpcd -name "*${IFACE}*" -type f 2>/dev/null | while read -r f; do
        info "  $f"
    done || info "  (ninguno)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --dhcp (forzar renovación DHCP)
# ─────────────────────────────────────────────────────────────────────────────
do_dhcp() {
    detect_network_stack
    echo -e "\n${BOLD}${CYAN}═══ Forzando DHCP en ${IFACE} ═══${RESET}"

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        do_dhcp_nm
    elif [[ "$NETWORKD_ACTIVE" -eq 1 ]]; then
        do_dhcp_networkd
    elif [[ "$DHCPCD_ACTIVE" -eq 1 ]]; then
        do_dhcp_dhcpcd
    elif [[ "$IFUPDOWN_ACTIVE" -eq 1 ]]; then
        do_dhcp_ifupdown
    elif command -v dhclient &>/dev/null; then
        do_dhcp_dhclient
    else
        fatal "No se detectó ningún stack de red compatible con DHCP."
        fatal "Instala NetworkManager, systemd-networkd, dhcpcd o dhclient."
        exit 1
    fi
}

do_dhcp_nm() {
    info "Usando ${BOLD}NetworkManager${RESET} para forzar DHCP..."

    local con_name
    con_name="$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)" || true
    if [[ -z "$con_name" ]]; then
        con_name="$IFACE"
    fi

    info "Desconectando ${BOLD}$IFACE${RESET}..."
    run_sudo nmcli device disconnect "$IFACE" 2>/dev/null || true

    info "Asegurando método DHCP en conexión ${BOLD}$con_name${RESET}..."
    if run_sudo nmcli connection modify "$con_name" ipv4.method auto 2>/dev/null; then
        success "método ipv4.method = auto"
    else
        warn "No se pudo modificar la conexión (puede no existir)."
    fi

    info "Limpiando leases DHCP stale..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] rm -f /var/lib/dhcp/dhclient*${IFACE}*.leases /var/lib/NetworkManager/*.lease"
    else
        sudo rm -f "/var/lib/dhcp/dhclient"*"${IFACE}"*".leases" 2>/dev/null || true
        sudo rm -f "/var/lib/NetworkManager/"*".lease" 2>/dev/null || true
        success "leases limpiados"
    fi

    info "Conectando ${BOLD}$IFACE${RESET}..."
    if run_sudo nmcli device connect "$IFACE" 2>/dev/null; then
        success "${BOLD}$IFACE${RESET} conectado vía DHCP."
        sleep 2
        ip -br addr show "$IFACE" 2>/dev/null
        return
    fi

    warn "nmcli device connect falló. Intentando por connection ${BOLD}$con_name${RESET}..."
    if run_sudo nmcli connection up "$con_name" 2>/dev/null; then
        success "${BOLD}$IFACE${RESET} activado vía connection."
        sleep 2
        ip -br addr show "$IFACE" 2>/dev/null
        return
    fi

    warn "nmcli connection up falló. Intentando reapply..."
    if run_sudo nmcli device reapply "$IFACE" 2>/dev/null; then
        success "${BOLD}$IFACE${RESET} reaplicado."
        return
    fi

    fatal "DHCP falló en todos los intentos para ${BOLD}$IFACE${RESET}."
    echo
    warn "Posibles causas:"
    warn "  - No hay servidor DHCP en la red."
    warn "  - Auto-negociación fallida (prueba: $0 $IFACE --auto-neg on)"
    warn "  - La interfaz está en un segmento aislado."
    warn "  - Prueba con IP estática: $0 $IFACE --static <IP/CIDR> --gateway <GW>"
    return 1
}

do_dhcp_networkd() {
    info "Usando ${BOLD}systemd-networkd${RESET} para forzar DHCP..."
    run_sudo networkctl reconfigure "$IFACE"
    success "${BOLD}$IFACE${RESET} reconfigurado."
}

do_dhcp_dhcpcd() {
    info "Usando ${BOLD}dhcpcd${RESET} standalone para renovar lease..."
    run_sudo dhcpcd -n "$IFACE"
    success "DHCP renovado en ${BOLD}$IFACE${RESET}."
}

do_dhcp_ifupdown() {
    info "Usando ${BOLD}ifupdown${RESET}..."
    run_sudo ifdown "$IFACE" 2>/dev/null || true
    run_sudo ifup "$IFACE"
    success "${BOLD}$IFACE${RESET} reiniciado vía ifupdown."
}

do_dhcp_dhclient() {
    info "Usando ${BOLD}dhclient${RESET} standalone..."
    run_sudo dhclient -r "$IFACE" 2>/dev/null || true
    run_sudo dhclient -v "$IFACE"
    success "DHCP adquirido en ${BOLD}$IFACE${RESET}."
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --release (liberar y renovar DHCP)
# ─────────────────────────────────────────────────────────────────────────────
do_release() {
    detect_network_stack
    echo -e "\n${BOLD}${CYAN}═══ Liberando y renovando DHCP en ${IFACE} ═══${RESET}"

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        local con_name
        con_name="$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)" || true
        con_name="${con_name:-$IFACE}"

        info "Liberando lease vía NM..."
        run_sudo nmcli device disconnect "$IFACE" 2>/dev/null || true
        sleep 2
        info "Renovando..."
        run_sudo nmcli device connect "$IFACE" 2>/dev/null || run_sudo nmcli connection up "$con_name" 2>/dev/null
        success "Lease renovado."
    elif [[ "$DHCPCD_ACTIVE" -eq 1 ]]; then
        run_sudo dhcpcd -k "$IFACE" 2>/dev/null || true
        sleep 2
        run_sudo dhcpcd -n "$IFACE"
        success "Lease renovado."
    elif command -v dhclient &>/dev/null; then
        run_sudo dhclient -r "$IFACE" 2>/dev/null || true
        sleep 2
        run_sudo dhclient -v "$IFACE"
        success "Lease renovado."
    else
        fatal "No se detectó stack compatible con DHCP."
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --static (configurar IP estática)
# ─────────────────────────────────────────────────────────────────────────────
do_static() {
    if [[ -z "$STATIC_IP" ]]; then
        fatal "--static requiere una IP/CIDR. Ej: --static 192.168.3.50/24"
        exit 1
    fi

    detect_network_stack

    echo -e "\n${BOLD}${CYAN}═══ Configurando IP estática en ${IFACE} ═══${RESET}"
    info "IP: ${BOLD}$STATIC_IP${RESET}"
    [[ -n "$STATIC_GW" ]] && info "Gateway: ${BOLD}$STATIC_GW${RESET}"
    [[ -n "$STATIC_DNS" ]] && info "DNS: ${BOLD}$STATIC_DNS${RESET}"

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        do_static_nm
    elif [[ "$NETWORKD_ACTIVE" -eq 1 ]]; then
        do_static_networkd
    else
        do_static_iproute
    fi
}

do_static_nm() {
    local con_name
    con_name="$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)" || true
    con_name="${con_name:-$IFACE}"

    run_sudo nmcli connection modify "$con_name" ipv4.method manual ipv4.addresses "$STATIC_IP" 2>/dev/null || {
        info "Creando nueva conexión NM ${BOLD}$con_name${RESET}..."
        run_sudo nmcli connection add type ethernet ifname "$IFACE" con-name "$con_name" ipv4.method manual ipv4.addresses "$STATIC_IP"
    }

    [[ -n "$STATIC_GW" ]] && run_sudo nmcli connection modify "$con_name" ipv4.gateway "$STATIC_GW"
    [[ -n "$STATIC_DNS" ]] && run_sudo nmcli connection modify "$con_name" ipv4.dns "$STATIC_DNS"

    run_sudo nmcli connection down "$con_name" 2>/dev/null || true
    run_sudo nmcli connection up "$con_name"
    success "IP estática configurada: ${BOLD}$STATIC_IP${RESET}"
    sleep 1
    ip -br addr show "$IFACE" 2>/dev/null
}

do_static_networkd() {
    local netdev="/etc/systemd/network/${IFACE}.network"
    local content
    content="[Match]\nName=${IFACE}\n\n[Network]\nAddress=${STATIC_IP}"
    [[ -n "$STATIC_GW" ]] && content="${content}\nGateway=${STATIC_GW}"
    [[ -n "$STATIC_DNS" ]] && content="${content}\nDNS=${STATIC_DNS}"
    warn "Se necesita crear/modificar ${BOLD}$netdev${RESET} para systemd-networkd."
    info "Contenido sugerido:"
    echo -e "$content"
}

do_static_iproute() {
    run_sudo ip addr flush dev "$IFACE" 2>/dev/null || true
    run_sudo ip addr add "$STATIC_IP" dev "$IFACE"
    run_sudo ip link set "$IFACE" up
    [[ -n "$STATIC_GW" ]] && run_sudo ip route replace default via "$STATIC_GW" dev "$IFACE"
    success "IP estática configurada con iproute2."
    ip -br addr show "$IFACE" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --auto-neg (activar/desactivar auto-negociación)
# ─────────────────────────────────────────────────────────────────────────────
do_autoneg() {
    if [[ -z "$AUTO_NEG" || "$AUTO_NEG" != "on" && "$AUTO_NEG" != "off" ]]; then
        fatal "--auto-neg requiere 'on' o 'off'"
        exit 1
    fi

    if ! command -v ethtool &>/dev/null; then
        fatal "ethtool no está instalado. Instala: ${BOLD}sudo apt install ethtool${RESET}"
        exit 1
    fi

    echo -e "\n${BOLD}${CYAN}═══ Auto-negociación: ${AUTO_NEG} (${IFACE}) ═══${RESET}"

    if [[ "$AUTO_NEG" == "on" ]]; then
        run_sudo ethtool -s "$IFACE" autoneg on
        success "Auto-negociación activada."
    else
        run_sudo ethtool -s "$IFACE" autoneg off
        success "Auto-negociación desactivada."
    fi

    sleep 2
    info "Verificando link:"
    ethtool "$IFACE" 2>/dev/null | grep -iE "Speed|Duplex|Auto|Link detected" | sed 's/^/  /'
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo --show-stack (solo mostrar stack)
# ─────────────────────────────────────────────────────────────────────────────
do_show_stack() {
    detect_network_stack
    detect_dhcp_client
    detect_conflicts

    echo
    echo -e "  Stack:     ${BOLD}${NET_STACK:-ninguno}${RESET}"
    echo -e "  DHCP:      ${BOLD}${DHCP_CLIENT:-ninguno}${RESET}"
    echo -e "  Netplan:   ${BOLD}$([[ "$NETPLAN_ACTIVE" -eq 1 ]] && echo "sí" || echo "no")${RESET}"
    echo -e "  Interfaz:  ${BOLD}$IFACE${RESET} ($(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo "?"))"
    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        warn "Conflictos:"
        for c in "${CONFLICTS[@]}"; do
            warn "  - $c"
        done
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "\n${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
        echo -e "${YELLOW}${BOLD}│  DRY-RUN: no se aplicarán cambios reales           │${RESET}"
        echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
    fi

    case "$MODE" in
        check)       do_check ;;
        dhcp)        do_dhcp ;;
        release)     do_release ;;
        static)      do_static ;;
        autoneg)     do_autoneg ;;
        show-stack)  do_show_stack ;;
        *)           fatal "modo desconocido: $MODE"; usage; exit 1 ;;
    esac

    echo
}

main "$@"
