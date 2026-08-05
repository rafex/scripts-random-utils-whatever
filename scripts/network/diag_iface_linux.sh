#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# diag_iface_linux.sh  v1.0.0
# Diagnostico de interfaz de red. Recolecta evidencia con sudo: WiFi, driver,
# fail2ban, firewall, kernel, ARP, conntrack, MTU, captura y hardware.
# Genera evidencia en /tmp y REPORTE.md con analisis automatico.
# ─────────────────────────────────────────────────────────────────────────────

IFACE="${DIAG_IFACE:-}"
OUTDIR="/tmp/diag-iface-$(date +%Y%m%d-%H%M%S)"
CAPTURE_PACKETS="${DIAG_CAPTURE:-50}"
MTU_TEST_TARGET="${DIAG_MTU_TARGET:-}"

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

run() {
    local name="$1"; shift
    local outfile="$OUTDIR/${name}.txt"
    echo "=== $(date) === $* ===" >> "$outfile"
    if "$@" >> "$outfile" 2>&1; then
        return 0
    else
        echo "[FALLÓ con código $?]" >> "$outfile"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  sudo $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}-i, --iface${RESET} <nombre>      Interfaz a diagnosticar (obligatoria si no hay --auto)"
    echo -e "  ${CYAN}    --auto${RESET}               Auto-detectar interfaz con mas RX drops"
    echo -e "  ${CYAN}-c, --capture${RESET} <N>         Paquetes a capturar con tcpdump (default: ${CAPTURE_PACKETS})"
    echo -e "  ${CYAN}    --no-capture${RESET}         Omitir captura tcpdump"
    echo -e "  ${CYAN}    --mtu-target${RESET} <ip>     IP para test de MTU con ping DF (ej: 192.168.3.1)"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>        Directorio de salida (default: autogenerado en /tmp)"
    echo -e "  ${CYAN}-h, --help${RESET}               Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}DIAG_IFACE${RESET}        Interfaz a diagnosticar"
    echo -e "  ${CYAN}DIAG_CAPTURE${RESET}      Paquetes a capturar (0 = no capturar)"
    echo -e "  ${CYAN}DIAG_MTU_TARGET${RESET}   IP para test MTU (default: gateway de la interfaz)"
    echo
    echo -e "${BOLD}Ejemplo:${RESET}"
    echo "  sudo $0 -i wlxa047d76360c5"
    echo "  sudo $0 --auto"
    echo "  sudo $0 -i enp1s0f0 --mtu-target 192.168.1.1 --no-capture"
    echo "  DIAG_IFACE=wlxa047d76360c5 sudo $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
NO_CAPTURE=0
AUTO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--iface)       IFACE="$2";           shift 2 ;;
        --auto)           AUTO=1;               shift ;;
        -c|--capture)     CAPTURE_PACKETS="$2"; shift 2 ;;
        --no-capture)     NO_CAPTURE=1;          shift ;;
        --mtu-target)     MTU_TEST_TARGET="$2"; shift 2 ;;
        -o|--output)      OUTDIR="$2";           shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)
            error "argumento desconocido: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Verificar sudo
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    error "este script requiere sudo para recolectar evidencia del sistema."
    echo "  Ejecutalo con: sudo $0"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detectar interfaz
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$AUTO" -eq 1 ]] && [[ -z "$IFACE" ]]; then
    info "Auto-detectando interfaz con mas RX drops..."
    IFACE=$(for f in /sys/class/net/*/statistics/rx_dropped; do
        [[ -f "$f" ]] || continue
        dropped=$(cat "$f")
        iface=$(echo "$f" | cut -d/ -f5)
        echo "$dropped $iface"
    done | sort -rn | head -1 | awk '{print $2}')
    if [[ -z "$IFACE" ]]; then
        error "no se pudo auto-detectar ninguna interfaz."
        echo "  Especifica una con: --iface <nombre>"
        exit 1
    fi
    info "Detectada: ${BOLD}${IFACE}${RESET}"
fi

if [[ -z "$IFACE" ]]; then
    error "debes especificar una interfaz con --iface o usar --auto."
    echo
    usage
    exit 1
fi

if [[ ! -d "/sys/class/net/${IFACE}" ]]; then
    error "interfaz '${BOLD}${IFACE}${RESET}' no existe."
    echo
    echo "Interfaces disponibles:"
    ls /sys/class/net/
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resolver gateway para MTU test si no se especifico
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$MTU_TEST_TARGET" ]]; then
    MTU_TEST_TARGET=$(ip route show dev "$IFACE" default 2>/dev/null | awk '{print $3}' | head -1 || true)
fi

# ─────────────────────────────────────────────────────────────────────────────
# Inicializar directorio de salida
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"
report="$OUTDIR/REPORTE.md"

info "Interfaz:     ${BOLD}${IFACE}${RESET}"
info "Evidencia en: ${BOLD}${OUTDIR}${RESET}"
echo

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 1: Red general${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "ip -br addr"
run 01-ip-addr ip -br addr

info "ip route"
run 02-ip-route ip route

info "ip -s link (estadisticas)"
run 03-ip-link ip -s link show "$IFACE"

info "ip neigh (ARP)"
run 04-ip-neigh ip neigh show dev "$IFACE"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 2: Sockets${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "ss -tlnp"
run 05-ss-listen ss -tlnp

info "ss -tn state established"
run 06-ss-established ss -tn state established

info "ss -s"
run 07-ss-summary ss -s

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 3: WiFi${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "iw dev"
iw dev > "$OUTDIR/08-iw-dev.txt" 2>&1 || echo "[iw no disponible]" >> "$OUTDIR/08-iw-dev.txt"

info "iw dev ${IFACE} link"
iw dev "$IFACE" link >> "$OUTDIR/08-iw-dev.txt" 2>&1 || echo "[no es WiFi o iw sin soporte]" >> "$OUTDIR/08-iw-dev.txt"

info "iw dev ${IFACE} station dump"
iw dev "$IFACE" station dump > "$OUTDIR/09-iw-station.txt" 2>&1 || echo "[no disponible]" >> "$OUTDIR/09-iw-station.txt"

info "iw dev ${IFACE} info"
iw dev "$IFACE" info > "$OUTDIR/10-iw-info.txt" 2>&1 || echo "[no disponible]" >> "$OUTDIR/10-iw-info.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 4: Driver y USB${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "lsmod (drivers red/wifi)"
lsmod | grep -iE "rtw|8821|ath|iwl|cfg80211|mac80211|r8169|e1000" > "$OUTDIR/11-lsmod.txt" 2>&1 || true

info "ethtool -i ${IFACE}"
ethtool -i "$IFACE" > "$OUTDIR/12-ethtool.txt" 2>&1 || echo "[no soportado]" >> "$OUTDIR/12-ethtool.txt"

info "ethtool -S ${IFACE}"
ethtool -S "$IFACE" > "$OUTDIR/13-ethtool-stats.txt" 2>&1 || echo "[no soportado]" >> "$OUTDIR/13-ethtool-stats.txt"

info "lsusb"
lsusb > "$OUTDIR/14-lsusb.txt" 2>&1

# Identificar bus USB de la interfaz
USB_DEVPATH=$(readlink -f "/sys/class/net/${IFACE}/device" 2>/dev/null || true)
if [[ -n "$USB_DEVPATH" ]] && echo "$USB_DEVPATH" | grep -q usb; then
    USB_DEV=$(echo "$USB_DEVPATH" | grep -oP 'usb\d+.*' | head -1)
    info "Dispositivo USB: ${BOLD}${USB_DEV}${RESET}"

    {
        echo "=== USB power management ==="
        for f in control autosuspend_delay_ms runtime_status; do
            p="$(find /sys/bus/usb/devices/ -name "$f" -path "*${USB_DEV}*" 2>/dev/null | head -1)"
            echo "${f}=$(cat "$p" 2>/dev/null || echo N/D)"
        done
        echo
        echo "=== USB descriptor ==="
        lsusb -v 2>/dev/null | grep -A50 "Device.*${IFACE}" || true
    } > "$OUTDIR/15-usb-power.txt" 2>&1
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 5: fail2ban${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

if systemctl is-active --quiet fail2ban 2>/dev/null; then
    fail2ban-client status > "$OUTDIR/16-fail2ban-status.txt" 2>&1 || echo "[falló]" >> "$OUTDIR/16-fail2ban-status.txt"
    fail2ban-client banned-ip >> "$OUTDIR/16-fail2ban-status.txt" 2>&1 || true

    JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | cut -d: -f2 | tr -d ' ,' || true)
    for jail in $JAILS; do
        {
            echo
            echo "=== Jail: $jail ==="
            fail2ban-client status "$jail" 2>/dev/null
        } >> "$OUTDIR/17-fail2ban-jails.txt" 2>&1
    done

    tail -100 /var/log/fail2ban.log > "$OUTDIR/18-fail2ban-log.txt" 2>&1 || true
else
    echo "fail2ban no esta activo" > "$OUTDIR/16-fail2ban-status.txt"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 6: Firewall${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

if command -v nft &>/dev/null; then
    info "nft list ruleset"
    nft list ruleset > "$OUTDIR/19-nft-ruleset.txt" 2>&1 || echo "[falló]" >> "$OUTDIR/19-nft-ruleset.txt"
else
    echo "nft no disponible" > "$OUTDIR/19-nft-ruleset.txt"
fi

if command -v iptables &>/dev/null; then
    info "iptables -L -n -v"
    iptables -L -n -v > "$OUTDIR/20-iptables.txt" 2>&1 || true
    iptables -t nat -L -n -v >> "$OUTDIR/20-iptables.txt" 2>&1 || true
else
    echo "iptables no disponible" > "$OUTDIR/20-iptables.txt"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 7: Kernel y journal${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "dmesg (filtrado rtw/usb/wifi/deauth/disconnect/mtu/drops)"
dmesg | grep -iE "rtw|8821|usb.*discon|wlxa|deauth|disconnect|mtu|dropped|error|fail" 2>/dev/null > "$OUTDIR/21-dmesg.txt" || echo "[nada]" >> "$OUTDIR/21-dmesg.txt"

info "journalctl -k (kernel boot)"
journalctl -k --no-pager -n 200 2>/dev/null > "$OUTDIR/22-journal-kernel.txt" || echo "[no disponible]" >> "$OUTDIR/22-journal-kernel.txt"

info "journalctl -u fail2ban"
journalctl -u fail2ban --no-pager -n 100 2>/dev/null > "$OUTDIR/23-journal-fail2ban.txt" || echo "[no disponible]" >> "$OUTDIR/23-journal-fail2ban.txt"

info "journalctl -u NetworkManager"
journalctl -u NetworkManager --no-pager -n 100 2>/dev/null > "$OUTDIR/24-journal-nm.txt" || echo "[no disponible]" >> "$OUTDIR/24-journal-nm.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 8: sysctl y conntrack${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

{
    echo "=== rp_filter ==="
    for f in all default "$IFACE"; do
        echo "$f: $(cat "/proc/sys/net/ipv4/conf/$f/rp_filter" 2>/dev/null || echo N/D)"
    done
    echo
    echo "=== ip_forward ==="
    echo "all: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo N/D)"
    echo
    echo "=== conntrack ==="
    echo "count: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo N/D)"
    echo "max:   $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo N/D)"
    echo
    echo "=== TCP tuning ==="
    sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.rmem_max net.core.wmem_max 2>/dev/null
} > "$OUTDIR/25-sysctl.txt" 2>&1

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 9: MTU test${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

MTU_FILE="$OUTDIR/26-mtu-test.txt"
{
    echo "=== MTU test ==="
    echo "Interfaz: ${IFACE}"
    echo "Gateway:  ${MTU_TEST_TARGET}"
    echo

    IFACE_MTU=$(cat "/sys/class/net/${IFACE}/mtu" 2>/dev/null || echo "N/D")
    echo "MTU configurado: ${IFACE_MTU}"
} > "$MTU_FILE"

if [[ -n "$MTU_TEST_TARGET" ]]; then
    {
        echo
        echo "=== Path MTU Discovery (ping con DF) ==="
        echo "Nota: size > MTU-28 con DF debe fallar si hay problema de MTU."
        for size in 1472 1400 1000; do
            echo -n "  size=${size}B: "
            if ping -c 2 -M 'do' -s "$size" -W 3 "$MTU_TEST_TARGET" >/dev/null 2>&1; then
                echo "OK"
            else
                echo "FAIL (PMTU menor a $((size+28)))"
            fi
        done
    } >> "$MTU_FILE" 2>&1
else
    echo "Gateway no detectado — omite test MTU" >> "$MTU_FILE"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 10: Hardware${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

{
    echo "=== RAM ==="
    free -h
    echo
    echo "=== CPUs ==="
    nproc
    echo
    echo "=== Load ==="
    cat /proc/loadavg
    echo
    echo "=== Interrupts (primeras 30 lineas) ==="
    head -30 /proc/interrupts
    echo
    echo "=== Top 10 procesos por CPU ==="
    ps aux --sort=-%cpu | head -11
    echo
    echo "=== Top 10 procesos por MEM ==="
    ps aux --sort=-%mem | head -11
} > "$OUTDIR/27-hardware.txt" 2>&1

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 11: Captura tcpdump${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

if [[ "$NO_CAPTURE" -eq 1 || "$CAPTURE_PACKETS" -eq 0 ]]; then
    info "Captura omitida (--no-capture o DIAG_CAPTURE=0)"
else
    if command -v tcpdump &>/dev/null; then
        info "Capturando ${CAPTURE_PACKETS} paquetes en ${IFACE}..."
        if timeout 30 tcpdump -i "$IFACE" -c "$CAPTURE_PACKETS" -w "$OUTDIR/28-capture.pcap" 2>/dev/null; then
            success "Captura guardada: ${OUTDIR}/28-capture.pcap"
        else
            warn "Captura finalizo con timeout o pocos paquetes (normal en trafico bajo)"
        fi
    else
        warn "tcpdump no disponible — omitiendo captura"
        echo "tcpdump no instalado" > "$OUTDIR/28-capture-skip.txt"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 12: Generando REPORTE.md${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Funciones de analisis
# ─────────────────────────────────────────────────────────────────────────────
get_iface_stat() {
    local stat="$1"
    cat "/sys/class/net/${IFACE}/statistics/${stat}" 2>/dev/null || echo "0"
}

get_iface_driver() {
    grep "driver:" "$OUTDIR/12-ethtool.txt" 2>/dev/null | awk '{print $2}' || echo "N/D"
}

get_fail2ban_bans() {
    grep -c "Ban " "$OUTDIR/18-fail2ban-log.txt" 2>/dev/null || echo "0"
}

get_rp_filter() {
    cat /proc/sys/net/ipv4/conf/"$IFACE"/rp_filter 2>/dev/null || echo "N/D"
}

# ─────────────────────────────────────────────────────────────────────────────
# Generar REPORTE.md
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "# Reporte de diagnostico de red — $(hostname)"
    echo
    echo "**Fecha:** $(date)"
    echo "**Interfaz analizada:** ${IFACE}"
    echo "**Directorio de evidencia:** ${OUTDIR}"
    echo

    RX_PACKETS=$(get_iface_stat rx_packets)
    TX_PACKETS=$(get_iface_stat tx_packets)
    RX_DROPPED=$(get_iface_stat rx_dropped)
    TX_DROPPED=$(get_iface_stat tx_dropped)
    IFACE_MTU=$(cat "/sys/class/net/${IFACE}/mtu" 2>/dev/null || echo "N/D")

    echo "## Estadisticas de la interfaz"
    echo
    echo "| Metrica | Valor |"
    echo "|---------|-------|"
    echo "| RX packets | $(printf "%'\''d" "$RX_PACKETS") |"
    echo "| TX packets | $(printf "%'\''d" "$TX_PACKETS") |"
    echo "| RX dropped | $(printf "%'\''d" "$RX_DROPPED") |"
    echo "| TX dropped | $(printf "%'\''d" "$TX_DROPPED") |"
    echo "| RX errors  | $(printf "%'\''d" "$RX_ERRORS") |"
    echo "| MTU        | ${IFACE_MTU} |"
    echo

    echo "## Hallazgos"
    echo
    echo "| Check | Estado | Detalle |"
    echo "|-------|--------|---------|"

    # TX/RX asymmetry
    ratio=0
    if [[ "$RX_PACKETS" -gt 0 ]]; then
        ratio=$(echo "scale=4; $TX_PACKETS / $RX_PACKETS" | bc -l 2>/dev/null || echo "0")
    fi
    local_emoji="🟢"
    if (( $(echo "$ratio < 0.01" | bc -l 2>/dev/null || echo 0) )); then
        local_emoji="🔴"
    elif (( $(echo "$ratio < 0.1" | bc -l 2>/dev/null || echo 0) )); then
        local_emoji="🟡"
    fi
    echo "| TX/RX asymmetry | ${local_emoji} | TX=${TX_PACKETS}, RX=${RX_PACKETS} (ratio: ${ratio}) |"

    # RX drops
    local_emoji="🟢"; if [[ "$RX_DROPPED" -gt 500 ]]; then local_emoji="🔴"; elif [[ "$RX_DROPPED" -gt 100 ]]; then local_emoji="🟡"; fi
    echo "| RX drops | ${local_emoji} | ${RX_DROPPED} paquetes |"

    # USB autosuspend
    USB_CONTROL=$(grep "control=" "$OUTDIR/15-usb-power.txt" 2>/dev/null | head -1 | cut -d= -f2 || echo "N/D")
    USB_SUSPEND=$(grep "autosuspend_delay_ms=" "$OUTDIR/15-usb-power.txt" 2>/dev/null | head -1 | cut -d= -f2 || echo "N/D")
    USB_RUNTIME=$(grep "runtime_status=" "$OUTDIR/15-usb-power.txt" 2>/dev/null | head -1 | cut -d= -f2 || echo "N/D")

    local_emoji="🟢"
    if [[ "$USB_CONTROL" == "on" ]] && [[ "$USB_SUSPEND" != "N/D" ]] && [[ "$USB_SUSPEND" -lt 5000 ]]; then
        local_emoji="🔴"
    elif [[ "$USB_CONTROL" == "on" ]]; then
        local_emoji="🟡"
    fi
    echo "| USB autosuspend | ${local_emoji} | control=${USB_CONTROL}, delay=${USB_SUSPEND}ms, runtime=${USB_RUNTIME} |"

    # fail2ban
    FAIL2BAN_BANS=$(get_fail2ban_bans)
    local_emoji="🟢"; if [[ "$FAIL2BAN_BANS" -gt 0 ]]; then local_emoji="🟡"; fi
    echo "| fail2ban bans recientes | ${local_emoji} | ~${FAIL2BAN_BANS} bans en log reciente |"

    # rp_filter
    RP_FILTER=$(get_rp_filter)
    local_emoji="🟢"; if [[ "$RP_FILTER" == "1" ]]; then local_emoji="🟡"; fi
    echo "| rp_filter ${IFACE} | ${local_emoji} | ${RP_FILTER} (0=off, 1=estricto, 2=loose) |"

    # conntrack
    CT_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
    CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "1")
    CT_PCT=$((100 * CT_COUNT / CT_MAX))
    local_emoji="🟢"; if [[ "$CT_PCT" -gt 80 ]]; then local_emoji="🔴"; elif [[ "$CT_PCT" -gt 50 ]]; then local_emoji="🟡"; fi
    echo "| conntrack | ${local_emoji} | ${CT_COUNT}/${CT_MAX} (${CT_PCT}%) |"

    # dmesg
    DMESG_LINES=$(wc -l < "$OUTDIR/21-dmesg.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$DMESG_LINES" -gt 10 ]]; then local_emoji="🟡"; fi
    echo "| dmesg errores/warnings | ${local_emoji} | ${DMESG_LINES} lineas relevantes |"

    # MTU
    MTU_OK=$(grep -c "FAIL" "$OUTDIR/26-mtu-test.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$MTU_OK" -gt 0 ]]; then local_emoji="🟡"; fi
    echo "| MTU path (ping DF) | ${local_emoji} | $(grep "FAIL" "$OUTDIR/26-mtu-test.txt" 2>/dev/null | head -1 || echo "OK") |"

    # ARP STALE
    STALE_COUNT=$(grep -ci "STALE" "$OUTDIR/04-ip-neigh.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$STALE_COUNT" -gt 2 ]]; then local_emoji="🟡"; fi
    echo "| ARP entries STALE | ${local_emoji} | ${STALE_COUNT} entradas |"

    # Driver
    DRIVER=$(get_iface_driver)
    echo "| Driver | 🟢 | ${DRIVER} |"

    echo
    echo "## Recomendaciones"
    echo
    echo '```bash'

    if [[ "$USB_CONTROL" == "on" ]] && [[ "$USB_SUSPEND" != "N/D" ]] && [[ "$USB_SUSPEND" -lt 5000 ]]; then
        echo "# Desactivar autosuspend del USB Wi-Fi"
        echo "# Busca el path en /sys/bus/usb/devices/... y ejecuta:"
        echo "echo 'on' | sudo tee /sys/bus/usb/devices/<DEV>/power/control"
        echo "echo '-1' | sudo tee /sys/bus/usb/devices/<DEV>/power/autosuspend_delay_ms"
        echo
    fi

    if [[ "$(get_fail2ban_bans)" -gt 0 ]]; then
        echo "# Desbanear una IP de fail2ban"
        echo "sudo fail2ban-client set sshd unbanip <IP>"
        echo
    fi

    if [[ "$STALE_COUNT" -gt 2 ]]; then
        echo "# Limpiar cache ARP"
        echo "sudo ip neigh flush dev ${IFACE}"
        echo
    fi

    if [[ "$CT_PCT" -gt 80 ]]; then
        echo "# Conntrack casi lleno — liberar manualmente"
        echo "sudo conntrack -D --src <IP>"
        echo
    fi

    echo "# Reiniciar NetworkManager (si la interfaz esta zombie)"
    echo "sudo systemctl restart NetworkManager"
    echo
    echo "# Reiniciar fail2ban (si hay falsos positivos)"
    echo "sudo systemctl restart fail2ban"
    echo '```'
    echo
    echo "---"
    echo "*Reporte generado por diag_iface_linux.sh v1.0.0*"

} > "$report"

success "REPORTE.md generado: ${BOLD}${report}${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 13: Empaquetando${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

TARNAME="$(basename "$OUTDIR").tar.gz"
info "Creando ${TARNAME}..."

tar czf "/tmp/${TARNAME}" -C /tmp "$(basename "$OUTDIR")"

echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Diagnostico completado${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo
echo -e "  Evidencia: ${BOLD}${OUTDIR}/${RESET}"
echo -e "  Reporte:   ${BOLD}${report}${RESET}"
echo -e "  Tarball:   ${BOLD}/tmp/${TARNAME}${RESET}"
echo
echo -e "  Para traer a tu maquina local:"
echo -e "  ${CYAN}scp $(hostname):/tmp/${TARNAME} .${RESET}"
echo
