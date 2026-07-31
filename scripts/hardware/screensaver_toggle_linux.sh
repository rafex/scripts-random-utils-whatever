#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# screensaver_toggle_linux.sh
# Activa/desactiva la espera de inactividad del protector de pantalla (X11).
# Opera sobre xset (Screen Saver + DPMS). No bloquea la pantalla — solo
# controla si el protector se activará tras N segundos sin actividad.
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
# Configuración por defecto — sobreescribible con env vars o flags
# ─────────────────────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_FILE="$CONFIG_DIR/screensaver-toggle.conf"
SS_TIMEOUT="${SS_TIMEOUT:-600}"       # segundos de inactividad para blanking
SS_CYCLE="${SS_CYCLE:-600}"           # ciclo del Screen Saver
SS_DPMS_S="${SS_DPMS_S:-600}"         # segundos para DPMS Standby
SS_DPMS_M="${SS_DPMS_M:-600}"         # segundos para DPMS Suspend
SS_DPMS_O="${SS_DPMS_O:-600}"         # segundos para DPMS Off
ARG_TIMEOUT=""
DISPLAY_TARGET="${DISPLAY:-:0}"
DRY_RUN="${SS_DRY_RUN:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 <on|off|toggle|status> [opciones]"
    echo
    echo -e "${BOLD}Subcomandos:${RESET}"
    echo -e "  ${CYAN}on${RESET}           Activa la espera de inactividad (restaura xset)"
    echo -e "  ${CYAN}off${RESET}          Desactiva la espera de inactividad (xset s off + dpms off)"
    echo -e "  ${CYAN}toggle${RESET}       Alterna entre on/off según el estado actual"
    echo -e "  ${CYAN}status${RESET}       Muestra el estado actual del protector de pantalla"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--timeout${RESET} <s>   Segundos de inactividad antes del protector (default: $SS_TIMEOUT)"
    echo -e "  ${CYAN}--display${RESET} <d>   DISPLAY X a usar (default: ${DISPLAY_TARGET})"
    echo -e "  ${CYAN}--dry-run${RESET}       Muestra los comandos sin ejecutarlos"
    echo -e "  ${CYAN}-h, --help${RESET}      Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}SS_TIMEOUT${RESET}   Tiempo de inactividad en segundos (default: $SS_TIMEOUT)"
    echo -e "  ${CYAN}SS_CYCLE${RESET}     Ciclo del Screen Saver (default: $SS_CYCLE)"
    echo -e "  ${CYAN}SS_DPMS_S${RESET}    DPMS Standby en segundos (default: $SS_DPMS_S)"
    echo -e "  ${CYAN}SS_DPMS_M${RESET}    DPMS Suspend en segundos (default: $SS_DPMS_M)"
    echo -e "  ${CYAN}SS_DPMS_O${RESET}    DPMS Off en segundos (default: $SS_DPMS_O)"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 off              # desactivar"
    echo "  $0 on               # activar con timeout default"
    echo "  $0 on --timeout 300 # activar con 5 min de espera"
    echo "  $0 toggle           # alternar"
    echo "  $0 status           # consultar estado"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar / guardar config persistente
# ─────────────────────────────────────────────────────────────────────────────
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(grep -E '^SS_TIMEOUT=' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2-)" || true
        if [[ -n "$val" ]]; then SS_TIMEOUT="$val"; fi
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# screensaver-toggle configuración — generado automáticamente
SS_TIMEOUT=${SS_TIMEOUT}
SS_CYCLE=${SS_CYCLE}
SS_DPMS_S=${SS_DPMS_S}
SS_DPMS_M=${SS_DPMS_M}
SS_DPMS_O=${SS_DPMS_O}
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones previas
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    if ! command -v xset &>/dev/null; then
        error "xset no está instalado. Requiere X11."
        exit 1
    fi

    if ! xset q &>/dev/null; then
        error "No se puede conectar al display ${BOLD}${DISPLAY_TARGET}${RESET}. ¿Está corriendo X11?"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Obtener estado actual
# ─────────────────────────────────────────────────────────────────────────────
get_status() {
    local xset_output
    xset_output="$(xset q 2>/dev/null)" || {
        echo "unknown"
        return
    }

    local s_timeout s_on
    s_timeout="$(echo "$xset_output" | grep -E '^\s+timeout:\s+' | awk '{print $2}')"
    s_on="$(echo "$xset_output" | grep -E '^\s+timeout:' | awk '{print $4}' | cut -d'/' -f1)"

    if [[ "$s_timeout" == "0" || "$s_on" != "$s_timeout" ]]; then
        echo "off"
    else
        echo "on"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar estado detallado
# ─────────────────────────────────────────────────────────────────────────────
show_status() {
    local xset_output state
    xset_output="$(xset q 2>/dev/null)" || {
        error "No se puede consultar xset"
        exit 1
    }

    state="$(get_status)"

    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Estado del protector de pantalla${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  Display:    ${BOLD}${DISPLAY_TARGET}${RESET}"
    if [[ "$state" == "on" ]]; then
        echo -e "  Protector:  ${GREEN}${BOLD}ACTIVADO (espera inactividad)${RESET}"
    else
        echo -e "  Protector:  ${RED}${BOLD}DESACTIVADO (no se activará por inactividad)${RESET}"
    fi
    echo
    echo -e "  ${BOLD}Configuración actual (xset):${RESET}"
    echo "$xset_output" | grep -E '(^\s+(timeout:|cycle:|prefer blanking:|Standby:)|^\s+DPMS is )' | sed 's/^/  /'
    echo
    echo -e "  ${BOLD}Timeout persistente:${RESET} ${SS_TIMEOUT}s"
    echo
    echo -e "  ${BOLD}Config:${RESET} ${CONFIG_FILE}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "  ${BOLD}Archivo:${RESET} existe"
    else
        echo -e "  ${BOLD}Archivo:${RESET} no existe (se creará al ejecutar ${CYAN}on${RESET})"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Desactivar protector de pantalla (no esperar inactividad)
# ─────────────────────────────────────────────────────────────────────────────
screensaver_off() {
    local state
    state="$(get_status)"

    if [[ "$state" == "off" ]]; then
        info "El protector de pantalla ya está ${BOLD}DESACTIVADO${RESET}."
        show_status_short
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] xset s off"
        info "[dry-run] xset -dpms"
        return 0
    fi

    info "Desactivando protección de pantalla (por inactividad)..."
    xset s off
    xset -dpms
    success "Protector de pantalla ${BOLD}DESACTIVADO${RESET}."
    notify_send "Protector DESACTIVADO" "No se activará por inactividad."
}

# ─────────────────────────────────────────────────────────────────────────────
# Activar protector de pantalla (esperar inactividad con timeout)
# ─────────────────────────────────────────────────────────────────────────────
screensaver_on() {
    local timeout="$1"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] xset s ${timeout} ${SS_CYCLE}"
        info "[dry-run] xset dpms ${SS_DPMS_S} ${SS_DPMS_M} ${SS_DPMS_O}"
        info "[dry-run] xset s on"
        info "[dry-run] xset +dpms"
        save_config
        info "[dry-run] Config guardada en ${CONFIG_FILE}"
        return 0
    fi

    info "Activando protector de pantalla (timeout: ${BOLD}${timeout}s${RESET})..."
    xset s "$timeout" "$SS_CYCLE"
    xset s on
    xset dpms "$SS_DPMS_S" "$SS_DPMS_M" "$SS_DPMS_O"
    xset +dpms
    save_config
    success "Protector de pantalla ${BOLD}ACTIVADO${RESET} (${timeout}s de inactividad)."
    notify_send "Protector ACTIVADO" "Se activará tras ${timeout}s de inactividad."
}

# ─────────────────────────────────────────────────────────────────────────────
# Alternar estado
# ─────────────────────────────────────────────────────────────────────────────
screensaver_toggle() {
    local timeout="$1" state
    state="$(get_status)"

    if [[ "$state" == "off" ]]; then
        screensaver_on "$timeout"
    else
        screensaver_off
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Notificación de escritorio
# ─────────────────────────────────────────────────────────────────────────────
notify_send() {
    local summary="$1" body="$2"
    if command -v notify-send &>/dev/null; then
        notify-send -u normal -t 2000 -- "⏳ $summary" "$body" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Resumen corto (para cuando ya está en el estado deseado y no se hace nada)
# ─────────────────────────────────────────────────────────────────────────────
show_status_short() {
    echo
    echo -e "  Tiempo restante según xset: $(xset q 2>/dev/null | grep -E '^\s+timeout:' | awk '{print $2}')s"
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
CMD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        on|off|toggle|status)
            CMD="$1"
            shift
            ;;
        --timeout)
            ARG_TIMEOUT="$2"
            shift 2
            ;;
        --display)
            DISPLAY_TARGET="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "argumento desconocido: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$CMD" ]]; then
    error "subcomando requerido: on, off, toggle o status"
    echo
    usage
    exit 1
fi

export DISPLAY="$DISPLAY_TARGET"

load_config

if [[ -n "$ARG_TIMEOUT" ]]; then
    if [[ ! "$ARG_TIMEOUT" =~ ^[0-9]+$ ]]; then
        error "--timeout debe ser un número entero: ${BOLD}$ARG_TIMEOUT${RESET}"
        exit 1
    fi
    SS_TIMEOUT="$ARG_TIMEOUT"
fi

preflight

case "$CMD" in
    on)     screensaver_on "$SS_TIMEOUT" ;;
    off)    screensaver_off ;;
    toggle) screensaver_toggle "$SS_TIMEOUT" ;;
    status) show_status ;;
esac
