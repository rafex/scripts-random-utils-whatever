#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# podman_recover_linux.sh  v1.0.0
# Recupera el socket de Podman cuando falla la conexion. Diagnostica, restaura
# systemctl --user podman.socket/podman.service, reintenta y genera REPORTE.md.
# ─────────────────────────────────────────────────────────────────────────────

RETRY="${PODMAN_RECOVER_RETRY:-5}"
INTERVAL="${PODMAN_RECOVER_INTERVAL:-2}"
WATCH="${PODMAN_RECOVER_WATCH:-0}"
OUTDIR="${PODMAN_RECOVER_OUTPUT:-}"
CHECK_ONLY=0
FORCE_RESET=0

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

run_cmd() {
    if "$@" 2>&1 | tee -a "$OUTDIR/cmd-output.txt"; then
        return 0
    else
        echo "[FALLÓ con código $?]" >> "$OUTDIR/cmd-output.txt"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolver UID y socket path
# ─────────────────────────────────────────────────────────────────────────────
UID_CURRENT="${UID:-$(id -u)}"
SOCKET_FILE="/run/user/${UID_CURRENT}/podman/podman.sock"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}-r, --retry${RESET} <N>         Reintentos (default: ${RETRY})"
    echo -e "  ${CYAN}-i, --interval${RESET} <seg>    Intervalo entre reintentos (default: ${INTERVAL})"
    echo -e "  ${CYAN}    --watch${RESET}            Monitor continuo: verifica y recupera si cae"
    echo -e "  ${CYAN}    --check-only${RESET}       Solo diagnosticar, no recuperar"
    echo -e "  ${CYAN}    --force-reset${RESET}      systemctl reset-failed desde el intento 1"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>     Directorio de salida (default: /tmp/podman-recover-<ts>)"
    echo -e "  ${CYAN}-h, --help${RESET}            Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}PODMAN_RECOVER_RETRY${RESET}     Reintentos (default: 5)"
    echo -e "  ${CYAN}PODMAN_RECOVER_INTERVAL${RESET}  Intervalo seg (default: 2)"
    echo -e "  ${CYAN}PODMAN_RECOVER_WATCH${RESET}     Modo watch (1=on)"
    echo -e "  ${CYAN}PODMAN_RECOVER_OUTPUT${RESET}    Directorio de salida"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0                     # diagnosticar y recuperar"
    echo "  $0 --check-only        # solo diagnosticar"
    echo "  $0 --watch             # monitor continuo cada 10s"
    echo "  $0 -r 10 -i 1          # 10 reintentos, 1s cada uno"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--retry)       RETRY="$2";       shift 2 ;;
        -i|--interval)    INTERVAL="$2";    shift 2 ;;
        --watch)          WATCH=1;           shift ;;
        --check-only)     CHECK_ONLY=1;      shift ;;
        --force-reset)    FORCE_RESET=1;     shift ;;
        -o|--output)      OUTDIR="$2";       shift 2 ;;
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
# Inicializar directorio de salida
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$OUTDIR" ]]; then
    OUTDIR="/tmp/podman-recover-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTDIR"
report="$OUTDIR/REPORTE.md"
touch "$OUTDIR/cmd-output.txt"

# ─────────────────────────────────────────────────────────────────────────────
# Funciones de diagnostico
# ─────────────────────────────────────────────────────────────────────────────
check_socket_file() {
    [[ -S "$SOCKET_FILE" ]] && return 0 || return 1
}

check_socket_unit() {
    systemctl --user is-active podman.socket --quiet 2>/dev/null && return 0 || return 1
}

check_service_unit() {
    systemctl --user is-active podman.service --quiet 2>/dev/null && return 0 || return 1
}

check_remote_info() {
    podman --remote info &>/dev/null && return 0 || return 1
}

diagnose() {
    echo
    echo -e "${BOLD}Diagnostico de Podman (UID: ${UID_CURRENT})${RESET}"
    echo

    local status="OK"
    echo "| Componente | Estado | Detalle |"
    echo "|------------|--------|---------|"

    if check_socket_file; then
        local perm
        perm=$(stat -c "%a" "$SOCKET_FILE" 2>/dev/null || echo "N/D")
        echo "| Socket file | 🟢 | ${SOCKET_FILE} (${perm}) |"
    else
        echo "| Socket file | 🔴 | ${SOCKET_FILE} no existe o no es socket |"
        status="FAIL"
    fi

    if check_socket_unit; then
        echo "| podman.socket | 🟢 | active |"
    else
        echo "| podman.socket | 🔴 | $(systemctl --user is-active podman.socket 2>&1 || echo inactive) |"
        status="FAIL"
    fi

    if check_service_unit; then
        echo "| podman.service | 🟢 | active |"
    else
        echo "| podman.service | 🟡 | $(systemctl --user is-active podman.service 2>&1 || echo inactive) |"
    fi

    if check_remote_info; then
        echo "| podman --remote info | 🟢 | responde OK |"
    else
        echo "| podman --remote info | 🔴 | no responde |"
        status="FAIL"
    fi

    echo
    echo "Estado: ${status}"
    echo

    # Guardar en archivo de diagnostico
    {
        echo "=== Diagnostico $(date) ==="
        echo "UID: ${UID_CURRENT}"
        echo "Socket file: ${SOCKET_FILE}"
        ls -l "$SOCKET_FILE" 2>&1 || echo "no existe"
        echo
        echo "--- systemctl --user status ---"
        systemctl --user status podman.socket 2>&1
        systemctl --user status podman.service 2>&1
        echo
        echo "--- podman --remote info ---"
        podman --remote info 2>&1
    } > "$OUTDIR/diagnose.txt" 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# Recuperacion
# ─────────────────────────────────────────────────────────────────────────────
recover() {
    local attempt=1

    while [[ "$attempt" -le "$RETRY" ]]; do
        echo
        echo -e "${BOLD}--- Recuperacion: intento ${attempt}/${RETRY} ---${RESET}"

        if [[ "$FORCE_RESET" -eq 1 ]] || [[ "$attempt" -ge 4 ]]; then
            info "systemctl --user reset-failed podman.socket podman.service"
            systemctl --user reset-failed podman.socket podman.service 2>/dev/null || true
        fi

        info "systemctl --user restart podman.socket"
        if systemctl --user restart podman.socket 2>&1 | tee -a "$OUTDIR/cmd-output.txt"; then
            success "podman.socket reiniciado"
        else
            warn "fallo al reiniciar podman.socket"
        fi

        sleep 1

        info "systemctl --user start podman.service"
        if systemctl --user start podman.service 2>&1 | tee -a "$OUTDIR/cmd-output.txt"; then
            success "podman.service iniciado"
        else
            warn "fallo al iniciar podman.service"
        fi

        info "Esperando ${INTERVAL}s antes de verificar..."
        sleep "$INTERVAL"

        if check_socket_file && check_remote_info; then
            success "Recuperacion exitosa en intento ${attempt}"
            return 0
        fi

        warn "Intento ${attempt}/${RETRY} fallo"
        ((attempt++))
    done

    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Generar REPORTE.md
# ─────────────────────────────────────────────────────────────────────────────
generate_report() {
    local state="$1"

    {
        echo "# Reporte de recuperacion de Podman — $(hostname)"
        echo
        echo "**Fecha:** $(date)"
        echo "**UID:** ${UID_CURRENT}"
        echo "**Socket:** ${SOCKET_FILE}"
        echo "**Modo:** $([ "$CHECK_ONLY" -eq 1 ] && echo "check-only" || echo "recover")"
        echo

        echo "## Estado ${state}"
        echo

        echo "| Componente | Estado |"
        echo "|------------|--------|"
        check_socket_file && echo "| Socket file | 🟢 existe |" || echo "| Socket file | 🔴 no existe |"
        check_socket_unit && echo "| podman.socket | 🟢 active |" || echo "| podman.socket | 🔴 inactive |"
        check_service_unit && echo "| podman.service | 🟢 active |" || echo "| podman.service | 🟡 inactive |"
        check_remote_info && echo "| podman --remote info | 🟢 OK |" || echo "| podman --remote info | 🔴 no responde |"

        echo
        echo "## Log de comandos"
        echo
        echo '```'
        cat "$OUTDIR/cmd-output.txt" 2>/dev/null || echo "(vacio)"
        echo '```'
        echo

        if [[ "$state" == "FAIL" ]]; then
            echo "## Diagnostico adicional (journalctl)"
            echo
            echo '```'
            journalctl --user -u podman --no-pager -n 30 2>/dev/null || echo "(no disponible)"
            echo '```'
            echo
            echo "## Sugerencias"
            echo
            echo "1. Verifica que el usuario tenga linger habilitado:"
            echo '   `loginctl enable-linger`'
            echo
            echo "2. Reinicia el daemon systemd del usuario:"
            echo '   `systemctl --user daemon-reexec`'
            echo
            echo "3. Verifica espacio en /run:"
            echo '   `df -h /run`'
        fi

        echo
        echo "---"
        echo "*Reporte generado por podman_recover_linux.sh v1.0.0*"
    } > "$report"

    success "REPORTE.md generado: ${BOLD}${report}${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Empaquetar resultados
# ─────────────────────────────────────────────────────────────────────────────
package_results() {
    echo
    info "Empaquetando resultados..."
    TARNAME="$(basename "$OUTDIR").tar.gz"
    tar czf "/tmp/${TARNAME}" -C /tmp "$(basename "$OUTDIR")"

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Evidencia en: ${OUTDIR}/${RESET}"
    echo -e "  Reporte:      ${report}"
    echo -e "  Tarball:      /tmp/${TARNAME}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Watch loop (monitor continuo)
# ─────────────────────────────────────────────────────────────────────────────
watch_loop() {
    local watch_interval="${1:-10}"

    echo
    info "Modo watch activo — verificando cada ${watch_interval}s"
    echo "  Socket: ${SOCKET_FILE}"
    echo "  Log:    ${OUTDIR}/watch.log"
    echo
    echo "Presiona Ctrl+C para detener."
    echo

    while true; do
        local ts
        ts="[$(date +%H:%M:%S)]"

        if check_socket_file && check_remote_info; then
            echo "${ts} OK"
        else
            echo "${ts} FAIL — socket caido, recuperando..." | tee -a "$OUTDIR/watch.log"
            recover
            if check_socket_file && check_remote_info; then
                echo "${ts} RECOVERED $(date +%H:%M:%S)" | tee -a "$OUTDIR/watch.log"
            else
                echo "${ts} UNRECOVERABLE — fallo tras ${RETRY} intentos" | tee -a "$OUTDIR/watch.log"
            fi
        fi

        sleep "$watch_interval"
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# EJECUCION PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════

echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Podman Socket Recovery${RESET}"
echo -e "  Host:    $(hostname)"
echo -e "  UID:     ${UID_CURRENT}"
echo -e "  Socket:  ${SOCKET_FILE}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

# ── Diagnostico ──────────────────────────────────────────────────────────────
diagnose

# ── Modo watch ───────────────────────────────────────────────────────────────
if [[ "$WATCH" -eq 1 ]]; then
    watch_loop "$INTERVAL"
    # watch_loop solo sale con Ctrl+C
    generate_report "WATCH"
    package_results
    exit 0
fi

# ── Solo diagnostico ─────────────────────────────────────────────────────────
if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Check-only — no se ejecuta recuperacion${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    if check_socket_file && check_remote_info; then
        success "Podman socket funcional — no requiere recuperacion"
        generate_report "OK"
    else
        error "Podman socket no funciona — ejecuta sin --check-only para recuperar"
        generate_report "FAIL"
        exit 1
    fi
    package_results
    exit 0
fi

# ── Recuperacion ─────────────────────────────────────────────────────────────
if check_socket_file && check_remote_info; then
    success "Podman socket ya funciona — no requiere recuperacion"
    generate_report "OK"
    package_results
    exit 0
fi

warn "Podman socket no funciona — iniciando recuperacion..."
if recover; then
    generate_report "OK"
else
    error "Recuperacion fallida tras ${RETRY} intentos"
    generate_report "FAIL"

    # Ultimo diagnostico
    echo
    warn "Diagnostico adicional:"
    journalctl --user -u podman --no-pager -n 30 2>/dev/null || true
    echo

    package_results
    exit 1
fi

package_results
