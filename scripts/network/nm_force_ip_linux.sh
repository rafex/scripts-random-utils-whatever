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
    echo -e "${YELLOW}${BOLD}  ⚡ Se requiere sudo para: $*${RESET}"
    sudo "$@"
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
    CONFLICTS=()

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

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        CONFLICTS=("${conflicts[@]}")
    fi
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
            "desconectado"|"disconnected")
                error "  $dev ($type): ${BOLD}$state${RESET}"
                if [[ -z "$con" ]]; then
                    error "  ${BOLD}La conexión NM no está asociada a este dispositivo${RESET}"
                fi
                ;;
            "connecting (getting IP configuration)"|"connecting*")
                warn "  $dev ($type): ${BOLD}$state${RESET} — intentando DHCP..."
                ;;
            "connecting (configuring)"|"configuring")
                warn "  $dev ($type): ${BOLD}$state${RESET} (configurando...)"
                ;;
            *)                            warn "  $dev ($type): ${BOLD}$state${RESET}" ;;
        esac
    done

    if ! nmcli connection show "$IFACE" &>/dev/null; then
        warn "No hay conexión NM definida para ${BOLD}$IFACE${RESET}."
        return
    fi

    echo
    info "Perfil NM (configuración de la conexión):"
    local profile_data
    profile_data="$(LC_ALL=C nmcli connection show "$IFACE" 2>/dev/null)"

    echo "$profile_data" | grep -iE "ipv4\.method|ipv4\.addresses|ipv4\.gateway|ipv4\.dns|autoconnect" | sed 's/^/  /'

    echo
    info "Link NM (ethernet):"
    echo "$profile_data" | grep -iE "802-3-ethernet\.auto-negotiate|802-3-ethernet\.speed|802-3-ethernet\.duplex" | sed 's/^/  /'
    local autoneg
    autoneg="$(echo "$profile_data" | grep "802-3-ethernet.auto-negotiate:" | awk '{$1=""; print $0}' | xargs)"
    if [[ "$autoneg" == "no" ]]; then
        error "  ${BOLD}Auto-negociación DESACTIVADA en perfil NM${RESET}"
        error "  ${BOLD}→ Esto causa que DHCP falle aunque el cable esté conectado${RESET}"
    elif [[ "$autoneg" == "yes" ]]; then
        success "  Auto-negociación activada en perfil NM"
    fi

    echo
    info "Timeout y tolerancia a fallos:"
    echo "$profile_data" | grep -iE "ipv4\.may-fail|ipv4\.dhcp-timeout|ipv4\.required-timeout" | sed 's/^/  /'

    local ts
    ts="$(echo "$profile_data" | grep "connection.timestamp:" | awk '{$1=""; print $0}' | xargs)"
    if [[ -n "$ts" && "$ts" != "0" ]]; then
        local ts_date
        ts_date="$(date -d "@$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "epoch $ts")"
        info "Última conexión exitosa: ${BOLD}$ts_date${RESET}"
    fi

    echo
    if [[ -f "/etc/network/interfaces" ]]; then
        if grep -qE "^[^#]*iface $IFACE" /etc/network/interfaces 2>/dev/null; then
            error "  ${BOLD}/etc/network/interfaces tiene una entrada ACTIVA para $IFACE${RESET}"
            error "  ${BOLD}→ Esto bloquea a NetworkManager. Coméntala con '#' al inicio.${RESET}"
        fi
        if grep -qE "^#.*iface $IFACE" /etc/network/interfaces 2>/dev/null; then
            info "  /etc/network/interfaces: entrada comentada (OK para NM)"
        fi
    fi

    echo
    info "DHCP leases (sin leer — requiere sudo):"
    local found=0
    for f in /var/lib/NetworkManager/*.lease /var/lib/dhcp/dhclient*"$IFACE"*.leases; do
        [[ -f "$f" ]] || continue
        info "  $f"
        found=1
    done 2>/dev/null
    [[ "$found" -eq 0 ]] && info "  (sin leases para $IFACE)"
    [[ "$found" -eq 1 ]] && info "  ${YELLOW}Usa sudo para ver el contenido: sudo cat <file>${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnóstico automático (solo modo check)
# ─────────────────────────────────────────────────────────────────────────────
do_autodiagnosis() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Diagnóstico automático — recomendaciones${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    local carrier operstate autoneg_nm nm_state nm_con
    carrier="$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo "0")"
    operstate="$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null || echo "?")"

    if [[ "$NM_ACTIVE" -eq 1 ]]; then
        autoneg_nm="$(LC_ALL=C nmcli connection show "$IFACE" 2>/dev/null | grep "802-3-ethernet.auto-negotiate:" | awk '{$1=""; print $0}' | xargs)"
        nm_state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)"
        nm_con="$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)"
    fi

    local issues=0
    local cmds=()

    # 1. Carrier check
    if [[ "$carrier" != "1" ]]; then
        error "No hay cable conectado (carrier=0)."
        cmds+=("Conecta un cable Ethernet al puerto.")
        issues=$((issues+1))
    else
        success "Cable conectado (carrier=1)"
    fi

    # 2. Auto-neg check
    if [[ "$autoneg_nm" == "no" ]]; then
        error "Auto-negociación DESACTIVADA en el perfil NM."
        error "  → Esto impide que el enlace negocie velocidad/duplex correctamente."
        cmds+=("sudo ~/.local/bin/nm-force-ip $IFACE --auto-neg on")
        issues=$((issues+1))
    elif [[ "$autoneg_nm" == "yes" ]]; then
        success "Auto-negociación activada en perfil NM"
    fi

    # 3. Connection association
    if [[ -z "$nm_con" && "$NM_ACTIVE" -eq 1 ]]; then
        error "Conexión NM no asociada al dispositivo (GENERAL.CONNECTION vacío)."
        cmds+=("sudo ~/.local/bin/nm-force-ip $IFACE --dhcp")
        issues=$((issues+1))
    elif [[ "$NM_ACTIVE" -eq 1 ]]; then
        success "Conexión NM asociada: $nm_con"
    fi

    # 4. NM state check
    case "$nm_state" in
        "connected"|"conectado")
            success "NM state: $nm_state — debería tener IP" ;;
        "disconnected"|"desconectado"|"unmanaged")
            if [[ "$carrier" == "1" ]]; then
                error "NM state: $nm_state pero carrier=1 — algo bloquea la activación."
                cmds+=("sudo ~/.local/bin/nm-force-ip $IFACE --dhcp")
                issues=$((issues+1))
            fi
            ;;
        *"configur"*|*"connect"*)
            warn "NM state: $nm_state — está intentando conectar (posible DHCP timeout)" ;;
    esac

    # 5. iface in /etc/network/interfaces (active)
    if [[ -f /etc/network/interfaces ]] && grep -qE "^[^#]*iface $IFACE" /etc/network/interfaces 2>/dev/null; then
        error "/etc/network/interfaces tiene entrada ACTIVA para $IFACE — bloquea a NM."
        cmds+=("Edita /etc/network/interfaces y comenta (añade #) las líneas de $IFACE")
        issues=$((issues+1))
    fi

    # 6. Old lease info (solo si se puede leer)
    local lease_file="/var/lib/dhcp/dhclient.${IFACE}.leases"
    if [[ -f "$lease_file" ]]; then
        local old_ip old_gw
        old_ip="$(sudo -n cat "$lease_file" 2>/dev/null | grep "fixed-address" | tail -1 | awk '{print $2}' | tr -d ';' || true)"
        old_gw="$(sudo -n cat "$lease_file" 2>/dev/null | grep "routers" | tail -1 | awk '{print $3}' | tr -d ';' || true)"
        if [[ -n "$old_ip" ]]; then
            info "Último lease exitoso: ${BOLD}${old_ip}${RESET} (gateway: ${old_gw:-?})"
            if [[ -n "$old_gw" && "$nm_state" != "connected" && "$nm_state" != "conectado" ]]; then
                cmds+=("sudo ~/.local/bin/nm-force-ip $IFACE --static ${old_ip}/24 --gateway ${old_gw}")
            fi
        else
            info "Último lease: ${BOLD}$lease_file${RESET} existe pero no se puede leer (sin sudo)"
        fi
    fi

    echo
    if [[ "$issues" -gt 0 ]]; then
        error "Se encontraron ${BOLD}$issues${RESET} problema(s)."
        if [[ ${#cmds[@]} -gt 0 ]]; then
            local seen=()
            local uniq_cmds=()
            for cmd in "${cmds[@]}"; do
                local found_dup=0
                for seen_cmd in "${seen[@]}"; do
                    [[ "$cmd" == "$seen_cmd" ]] && found_dup=1 && break
                done
                if [[ "$found_dup" -eq 0 ]]; then
                    seen+=("$cmd")
                    uniq_cmds+=("$cmd")
                fi
            done
            echo
            echo -e "${BOLD}${CYAN}  Comandos recomendados (en orden):${RESET}"
            for cmd in "${uniq_cmds[@]}"; do
                echo -e "  ${GREEN}\$ ${cmd}${RESET}"
            done
        fi
    else
        success "No se detectaron problemas evidentes."
        success "Si la interfaz no tiene IP, puede ser que no haya servidor DHCP en la red."
        echo
        info "Prueba con IP estática:"
        echo -e "  ${GREEN}\$ sudo ~/.local/bin/nm-force-ip $IFACE --static <IP/CIDR> --gateway <GW>${RESET}"
    fi
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

    do_autodiagnosis
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
