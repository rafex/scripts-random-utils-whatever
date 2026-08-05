#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# podman_overlay_watch_linux.sh  v1.0.0
# Monitor del tamano del overlay de Podman. Cuando supera un threshold (150GB
# por defecto) o el disco esta > 85%, ejecuta podman builder prune -af
# automaticamente. Soporta modo watch continuo, oneshot (systemd timer) y
# auto-instalacion de timer systemd --user.
# ─────────────────────────────────────────────────────────────────────────────

THRESHOLD_GB="${PODMAN_OVERLAY_THRESHOLD:-150}"
INTERVAL="${PODMAN_OVERLAY_INTERVAL:-300}"
DISK_THRESHOLD_PCT="${PODMAN_OVERLAY_DISK_PCT:-85}"
PRUNE_CMD="${PODMAN_OVERLAY_PRUNE_CMD:-podman builder prune -af}"
LOG_FILE="${PODMAN_OVERLAY_LOG:-${HOME}/.local/share/podman-overlay-watch.log}"
OUTDIR="${PODMAN_OVERLAY_OUTPUT:-}"
DRY_RUN="${PODMAN_OVERLAY_DRY_RUN:-0}"
MODE_WATCH=0
MODE_ONESHOT=0
MODE_INSTALL=0
MODE_UNINSTALL=0
THRESHOLD_BYTES=""

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

log_msg() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level} $*" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────
OVERLAY_DIR="${HOME}/.local/share/containers/storage/overlay"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SYSTEMD_SERVICE="${SYSTEMD_USER_DIR}/podman-overlay-watch.service"
SYSTEMD_TIMER="${SYSTEMD_USER_DIR}/podman-overlay-watch.timer"
SCRIPT_TARGET="${HOME}/.local/bin/podman_overlay_watch_linux.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Modos:${RESET}"
    echo -e "  ${CYAN}--watch${RESET}           Monitor continuo (default)"
    echo -e "  ${CYAN}--oneshot${RESET}        Check unico, sale (para systemd timer / cron)"
    echo -e "  ${CYAN}--install-timer${RESET}  Instala timer systemd --user (cada 30 min)"
    echo -e "  ${CYAN}--uninstall-timer${RESET} Desinstala timer systemd"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}-t, --threshold${RESET} <GB>     Umbral overlay en GB (default: ${THRESHOLD_GB})"
    echo -e "  ${CYAN}-d, --disk-pct${RESET} <%>       Trigger secundario: disco > P% (default: ${DISK_THRESHOLD_PCT})"
    echo -e "  ${CYAN}-i, --interval${RESET} <seg>     Intervalo check modo watch (default: ${INTERVAL})"
    echo -e "  ${CYAN}    --prune-cmd${RESET} <cmd>     Comando prune custom (default: ${PRUNE_CMD})"
    echo -e "  ${CYAN}    --dry-run${RESET}            Reportar pero no ejecutar prune"
    echo -e "  ${CYAN}    --log${RESET} <archivo>       Log persistente (default: ${LOG_FILE})"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>        Evidencia en /tmp cuando cleanup corre"
    echo -e "  ${CYAN}-h, --help${RESET}               Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}PODMAN_OVERLAY_THRESHOLD${RESET}   Umbral GB"
    echo -e "  ${CYAN}PODMAN_OVERLAY_DISK_PCT${RESET}    Trigger disco %"
    echo -e "  ${CYAN}PODMAN_OVERLAY_INTERVAL${RESET}    Intervalo seg (watch)"
    echo -e "  ${CYAN}PODMAN_OVERLAY_PRUNE_CMD${RESET}   Comando prune"
    echo -e "  ${CYAN}PODMAN_OVERLAY_LOG${RESET}         Archivo de log"
    echo -e "  ${CYAN}PODMAN_OVERLAY_DRY_RUN${RESET}     Dry run (1=on)"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0                                        # watch continuo (default)"
    echo "  $0 --oneshot                              # check unico"
    echo "  $0 --install-timer                        # instalar timer systemd"
    echo "  $0 -t 100 --dry-run --oneshot             # dry-run con threshold 100GB"
    echo "  $0 --watch -i 600                         # watch cada 10 min"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)           MODE_WATCH=1;       shift ;;
        --oneshot)         MODE_ONESHOT=1;      shift ;;
        --install-timer)   MODE_INSTALL=1;      shift ;;
        --uninstall-timer) MODE_UNINSTALL=1;    shift ;;
        -t|--threshold)    THRESHOLD_GB="$2";   shift 2 ;;
        -d|--disk-pct)     DISK_THRESHOLD_PCT="$2"; shift 2 ;;
        -i|--interval)     INTERVAL="$2";        shift 2 ;;
        --prune-cmd)       PRUNE_CMD="$2";       shift 2 ;;
        --dry-run)         DRY_RUN=1;            shift ;;
        --log)             LOG_FILE="$2";        shift 2 ;;
        -o|--output)       OUTDIR="$2";          shift 2 ;;
        -h|--help)         usage; exit 0 ;;
        *)
            error "argumento desconocido: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

# Deducir modo default
if [[ "$MODE_WATCH" -eq 0 ]] && [[ "$MODE_ONESHOT" -eq 0 ]] && [[ "$MODE_INSTALL" -eq 0 ]] && [[ "$MODE_UNINSTALL" -eq 0 ]]; then
    MODE_WATCH=1
fi

# Convertir threshold GB a bytes
THRESHOLD_BYTES=$((THRESHOLD_GB * 1073741824))

# ─────────────────────────────────────────────────────────────────────────────
# Funciones de medicion
# ─────────────────────────────────────────────────────────────────────────────
get_overlay_bytes() {
    du -sb "$OVERLAY_DIR" 2>/dev/null | awk '{print $1}' || echo "0"
}

get_overlay_gb() {
    local bytes
    bytes=$(get_overlay_bytes)
    echo "scale=2; ${bytes} / 1073741824" | bc -l 2>/dev/null || echo "0"
}

get_disk_pct() {
    df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%' || echo "0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Ejecutar prune
# ─────────────────────────────────────────────────────────────────────────────
do_prune() {
    local before_bytes after_bytes freed_gb
    before_bytes=$(get_overlay_bytes)

    if [[ -z "$OUTDIR" ]]; then
        OUTDIR="/tmp/podman-overlay-watch-$(date +%Y%m%d-%H%M%S)"
    fi
    mkdir -p "$OUTDIR"

    {
        echo "=== SNAPSHOT ANTES ==="
        echo "overlay_bytes: ${before_bytes}"
        echo "overlay_gb:    $(echo "scale=2; ${before_bytes} / 1073741824" | bc -l)"
        echo "disk_pct:      $(get_disk_pct)%"
    } > "$OUTDIR/snapshot-before.txt"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "[dry-run] se ejecutaria: ${PRUNE_CMD}"
        log_msg "PRUNE" "[dry-run] overlay=$(get_overlay_gb)GB"
        return 0
    fi

    info "Ejecutando: ${PRUNE_CMD}"
    if eval "$PRUNE_CMD" > "$OUTDIR/prune-output.txt" 2>&1; then
        success "Prune completado"
    else
        warn "Prune fallo (codigo $?) — ver ${OUTDIR}/prune-output.txt"
    fi

    after_bytes=$(get_overlay_bytes)
    freed_gb=$(echo "scale=2; (${before_bytes} - ${after_bytes}) / 1073741824" | bc -l)

    {
        echo "=== SNAPSHOT DESPUES ==="
        echo "overlay_bytes: ${after_bytes}"
        echo "overlay_gb:    $(echo "scale=2; ${after_bytes} / 1073741824" | bc -l)"
        echo "freed_gb:      ${freed_gb}"
        echo "disk_pct:      $(get_disk_pct)%"
    } > "$OUTDIR/snapshot-after.txt"

    log_msg "PRUNE" "before=$(get_overlay_gb)GB after=$(echo "scale=2; ${after_bytes} / 1073741824" | bc -l)GB freed=${freed_gb}GB"

    # Generar REPORTE.md
    {
        echo "# Reporte de limpieza automatica — $(hostname)"
        echo
        echo "**Fecha:** $(date)"
        echo "**Trigger:** overlay > ${THRESHOLD_GB}GB o disco > ${DISK_THRESHOLD_PCT}%"
        echo "**Overlay antes:** $(get_overlay_gb) GB"
        echo "**Overlay despues:** $(echo "scale=2; ${after_bytes} / 1073741824" | bc -l) GB"
        echo "**Liberado:** ${freed_gb} GB"
        echo "**Disco:** $(get_disk_pct)%"
        echo
        echo "## Output del prune"
        echo
        echo '```'
        cat "$OUTDIR/prune-output.txt" 2>/dev/null || echo "(vacio)"
        echo '```'
        echo
        echo "---"
        echo "*Reporte generado por podman_overlay_watch_linux.sh v1.0.0*"
    } > "$OUTDIR/REPORTE.md"

    # Empaquetar
    TARNAME="$(basename "$OUTDIR").tar.gz"
    tar czf "/tmp/${TARNAME}" -C /tmp "$(basename "$OUTDIR")" 2>/dev/null || true
    info "Evidencia guardada: ${OUTDIR}/"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check: overlay size + disk pct
# ─────────────────────────────────────────────────────────────────────────────
check_and_prune() {
    local overlay_bytes overlay_gb disk_pct triggered=0 reason=""

    overlay_bytes=$(get_overlay_bytes)
    overlay_gb=$(get_overlay_gb)
    disk_pct=$(get_disk_pct)

    # Trigger primario: overlay > threshold
    if [[ "$overlay_bytes" -gt "$THRESHOLD_BYTES" ]]; then
        triggered=1
        reason="overlay ${overlay_gb}GB > threshold ${THRESHOLD_GB}GB"
    fi

    # Trigger secundario: disco > %
    if [[ "$disk_pct" -ge "$DISK_THRESHOLD_PCT" ]]; then
        triggered=1
        reason="disco ${disk_pct}% > threshold ${DISK_THRESHOLD_PCT}%"
    fi

    if [[ "$triggered" -eq 1 ]]; then
        warn "ALERTA: ${reason}"
        log_msg "ALERT" "${reason} — ejecutando prune..."
        do_prune
    else
        # Solo loguear en modo verbose (cada 10 checks en watch, o siempre en oneshot)
        if [[ "$MODE_ONESHOT" -eq 1 ]]; then
            log_msg "CHECK" "overlay=${overlay_gb}GB disk=${disk_pct}% status=OK"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo: oneshot (para systemd timer / cron)
# ─────────────────────────────────────────────────────────────────────────────
run_oneshot() {
    local overlay_gb disk_pct
    overlay_gb=$(get_overlay_gb)
    disk_pct=$(get_disk_pct)

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Podman Overlay Watch — Oneshot${RESET}"
    echo -e "  Overlay:   ${overlay_gb} GB"
    echo -e "  Threshold: ${THRESHOLD_GB} GB"
    echo -e "  Disco:     ${disk_pct}%"
    echo -e "  Dry-run:   $([[ "$DRY_RUN" -eq 1 ]] && echo "SI" || echo "NO")"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    check_and_prune
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo: watch (monitor continuo)
# ─────────────────────────────────────────────────────────────────────────────
run_watch() {
    local overlay_gb disk_pct
    overlay_gb=$(get_overlay_gb)
    disk_pct=$(get_disk_pct)

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Podman Overlay Watch — Modo continuo${RESET}"
    echo -e "  Overlay:      ${overlay_gb} GB"
    echo -e "  Threshold:    ${THRESHOLD_GB} GB"
    echo -e "  Disk trigger: ${DISK_THRESHOLD_PCT}%"
    echo -e "  Interval:     ${INTERVAL}s"
    echo -e "  Log:          ${LOG_FILE}"
    echo -e "  Dry-run:      $([[ "$DRY_RUN" -eq 1 ]] && echo "SI" || echo "NO")"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
    echo "Presiona Ctrl+C para detener."
    echo

    mkdir -p "$(dirname "$LOG_FILE")"

    local check_count=0
    while true; do
        check_count=$((check_count + 1))

        # Check rapido: df (instantaneo). Solo du si disco cerca del threshold
        local disk_pct_now
        disk_pct_now=$(get_disk_pct)

        if [[ "$disk_pct_now" -ge "$DISK_THRESHOLD_PCT" ]]; then
            # Disco lleno — verificar overlay completo
            check_and_prune
        elif [[ "$((check_count % 10))" -eq 0 ]]; then
            # Cada 10 checks, hacer du completo
            check_and_prune
        else
            # Check rapido: solo loguear si verbose
            if [[ "$((check_count % 10))" -eq 5 ]]; then
                local overlay_quick
                overlay_quick=$(get_overlay_gb)
                log_msg "CHECK" "overlay=${overlay_quick}GB disk=${disk_pct_now}% status=OK"
            fi
        fi

        sleep "$INTERVAL"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo: install timer
# ─────────────────────────────────────────────────────────────────────────────
install_timer() {
    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Instalando timer systemd --user${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    # Copiar script
    mkdir -p "$(dirname "$SCRIPT_TARGET")"
    cp "$0" "$SCRIPT_TARGET"
    chmod +x "$SCRIPT_TARGET"
    success "Script copiado a ${SCRIPT_TARGET}"

    # Crear service unit
    mkdir -p "$SYSTEMD_USER_DIR"
    cat > "$SYSTEMD_SERVICE" << 'UNITEOF'
[Unit]
Description=Podman overlay size monitor — auto-prune build cache
After=network-online.target
Documentation=https://github.com/rafex/scripts-random-utils-whatever

[Service]
Type=oneshot
ExecStart=%h/.local/bin/podman_overlay_watch_linux.sh --oneshot
StandardOutput=journal
StandardError=journal
UNITEOF
    success "Service unit creado: ${SYSTEMD_SERVICE}"

    # Crear timer unit
    cat > "$SYSTEMD_TIMER" << TIMEREOF
[Unit]
Description=Run podman overlay monitor every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Unit=podman-overlay-watch.service

[Install]
WantedBy=timers.target
TIMEREOF
    success "Timer unit creado: ${SYSTEMD_TIMER}"

    # Recargar y habilitar
    systemctl --user daemon-reload
    systemctl --user enable --now podman-overlay-watch.timer
    success "Timer habilitado e iniciado"

    echo
    echo -e "${BOLD}Timer instalado correctamente.${RESET}"
    echo
    echo "Verificar estado:"
    echo "  ${CYAN}systemctl --user status podman-overlay-watch.timer${RESET}"
    echo "  ${CYAN}systemctl --user list-timers${RESET}"
    echo
    echo "Logs:"
    echo "  ${CYAN}journalctl --user -u podman-overlay-watch${RESET}"
    echo "  ${CYAN}cat ${LOG_FILE}${RESET}"
    echo

    # Ejecutar primer check
    "${SCRIPT_TARGET}" --oneshot
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo: uninstall timer
# ─────────────────────────────────────────────────────────────────────────────
uninstall_timer() {
    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Desinstalando timer systemd --user${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    systemctl --user stop podman-overlay-watch.timer 2>/dev/null || true
    systemctl --user disable podman-overlay-watch.timer 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE" "$SYSTEMD_TIMER"
    systemctl --user daemon-reload
    rm -f "$SCRIPT_TARGET"

    success "Timer desinstalado."
    echo
    echo "Log persistente conservado en: ${LOG_FILE}"
    echo "Para borrarlo: rm ${LOG_FILE}"
    echo
}

# ══════════════════════════════════════════════════════════════════════════════
# EJECUCION PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════

if [[ "$MODE_INSTALL" -eq 1 ]]; then
    install_timer
    exit 0
fi

if [[ "$MODE_UNINSTALL" -eq 1 ]]; then
    uninstall_timer
    exit 0
fi

if [[ "$MODE_ONESHOT" -eq 1 ]]; then
    run_oneshot
fi

if [[ "$MODE_WATCH" -eq 1 ]]; then
    run_watch
fi
