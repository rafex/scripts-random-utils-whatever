#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# podman_cleanup_linux.sh  v1.0.0
# Limpia almacenamiento de Podman/Docker por niveles (0=analisis a 5=nuclear).
# Ejecuta analisis en paralelo (jobs background) y genera REPORTE.md
# con comparativa antes/despues y espacio liberado.
# ─────────────────────────────────────────────────────────────────────────────

LEVEL="${PODMAN_CLEANUP_LEVEL:-0}"
YES="${PODMAN_CLEANUP_YES:-0}"
FORCE="${PODMAN_CLEANUP_FORCE:-0}"
INCLUDE_DOCKER="${PODMAN_CLEANUP_DOCKER:-0}"
OUTDIR="${PODMAN_CLEANUP_OUTPUT:-}"
INTERVAL="${PODMAN_CLEANUP_INTERVAL:-2}"

# Storage paths
PODMAN_OVERLAY="${HOME}/.local/share/containers/storage/overlay"
PODMAN_IMAGES_JSON="${HOME}/.local/share/containers/storage/images/images.json"
DOCKER_OVERLAY="/var/lib/docker/overlay2"

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
    local label="$1"; shift
    info "${label}"
    if "$@" 2>&1 | tee -a "$OUTDIR/cmd-output.txt"; then
        success "${label} — OK"
        return 0
    else
        warn "${label} — fallo (codigo $?)"
        return 1
    fi
}

run_quiet() {
    "$@" 2>> "$OUTDIR/errors.txt" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Niveles de limpieza:${RESET}"
    echo -e "  ${CYAN}0${RESET} — Analisis (default, solo lectura)"
    echo -e "  ${CYAN}1${RESET} — Container prune  (contenedores stopped)"
    echo -e "  ${CYAN}2${RESET} — Image prune       (imagenes sin contenedor)"
    echo -e "  ${CYAN}3${RESET} — Builder prune     (build cache)          [pide confirmacion]"
    echo -e "  ${CYAN}4${RESET} — System prune      (TODO + volumenes)      [pide confirmacion]"
    echo -e "  ${CYAN}5${RESET} — Storage reset     (rm -rf overlay)        [pide confirmacion]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--analyze${RESET}              Nivel 0: solo analisis (default)"
    echo -e "  ${CYAN}-l, --level${RESET} <0-5>       Nivel de limpieza"
    echo -e "  ${CYAN}--yes${RESET}                  Saltar confirmacion (niveles 3+)"
    echo -e "  ${CYAN}-f, --force${RESET}             Limpiar aunque haya contenedores running"
    echo -e "  ${CYAN}--docker${RESET}               Incluir docker ademas de podman"
    echo -e "  ${CYAN}--podman-only${RESET}          Solo podman (default: auto-detecta ambos)"
    echo -e "  ${CYAN}--interval${RESET} <seg>       Intervalo de monitoreo background (default: ${INTERVAL})"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>      Directorio de salida (default: /tmp/podman-cleanup-<ts>)"
    echo -e "  ${CYAN}-h, --help${RESET}             Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}PODMAN_CLEANUP_LEVEL${RESET}    Nivel (0-5)"
    echo -e "  ${CYAN}PODMAN_CLEANUP_YES${RESET}      Saltar confirmacion"
    echo -e "  ${CYAN}PODMAN_CLEANUP_FORCE${RESET}    Forzar con contenedores running"
    echo -e "  ${CYAN}PODMAN_CLEANUP_DOCKER${RESET}   Incluir docker"
    echo -e "  ${CYAN}PODMAN_CLEANUP_OUTPUT${RESET}   Directorio de salida"
    echo -e "  ${CYAN}PODMAN_CLEANUP_INTERVAL${RESET} Intervalo de monitoreo (seg)"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 --analyze                       # solo analizar"
    echo "  $0 -l 2                            # limpiar imagenes y contenedores stopped"
    echo "  $0 -l 4 --yes                      # system prune sin confirmacion"
    echo "  $0 -l 2 --docker                   # podman + docker"
    echo "  PODMAN_CLEANUP_LEVEL=3 $0 --yes    # via env vars"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
PODMAN_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --analyze)          LEVEL=0;          shift ;;
        -l|--level)         LEVEL="$2";       shift 2 ;;
        --yes)              YES=1;            shift ;;
        -f|--force)         FORCE=1;          shift ;;
        --docker)           INCLUDE_DOCKER=1;  shift ;;
        --podman-only)      PODMAN_ONLY=1;     shift ;;
        --interval)         INTERVAL="$2";     shift 2 ;;
        -o|--output)        OUTDIR="$2";       shift 2 ;;
        -h|--help)          usage; exit 0 ;;
        *)
            error "argumento desconocido: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Validar nivel
# ─────────────────────────────────────────────────────────────────────────────
if ! [[ "$LEVEL" =~ ^[0-5]$ ]]; then
    error "nivel invalido: ${BOLD}${LEVEL}${RESET}. Debe ser 0-5."
    usage
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Inicializar directorio de salida
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$OUTDIR" ]]; then
    OUTDIR="/tmp/podman-cleanup-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTDIR"
report="$OUTDIR/REPORTE.md"

touch "$OUTDIR/cmd-output.txt" "$OUTDIR/errors.txt"

# ─────────────────────────────────────────────────────────────────────────────
# Funciones de deteccion
# ─────────────────────────────────────────────────────────────────────────────
has_podman()  { command -v podman &>/dev/null; }
has_docker()  { command -v docker &>/dev/null; }

has_running_podman() {
    has_podman && podman ps -q 2>/dev/null | grep -q . || return 1
}

has_running_docker() {
    has_docker && docker ps -q 2>/dev/null | grep -q . || return 1
}

get_overlay_size() {
    local path="$1"
    du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "N/D"
}

get_layer_count() {
    local path="$1"
    find "$path" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l || echo "0"
}

get_disk_used() {
    df -h / 2>/dev/null | awk 'NR==2{print $3}' || echo "N/D"
}

get_disk_pct() {
    df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo "N/D"
}

get_containers_count() {
    podman ps -a -q 2>/dev/null | wc -l | tr -d ' ' || echo "0"
}

get_images_count() {
    podman images -q 2>/dev/null | wc -l | tr -d ' ' || echo "N/D"
}

# ─────────────────────────────────────────────────────────────────────────────
# Analisis previo (snapshot antes)
# ─────────────────────────────────────────────────────────────────────────────
snapshot_before() {
    {
        echo "=== SNAPSHOT ANTES ==="
        echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "disco_used: $(get_disk_used)"
        echo "disco_pct:  $(get_disk_pct)"

        if has_podman; then
            echo "podman_overlay_size:  $(get_overlay_size "$PODMAN_OVERLAY")"
            echo "podman_layer_count:   $(get_layer_count "$PODMAN_OVERLAY")"
            echo "podman_containers:    $(get_containers_count)"
            echo "podman_images:        $(get_images_count)"
        fi

        if has_docker && [[ "$INCLUDE_DOCKER" -eq 1 ]]; then
            echo "docker_overlay_size:  $(get_overlay_size "$DOCKER_OVERLAY")"
            echo "docker_layer_count:   $(get_layer_count "$DOCKER_OVERLAY")"
        fi
    } > "$OUTDIR/snapshot-before.txt" 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# Analisis posterior (snapshot despues)
# ─────────────────────────────────────────────────────────────────────────────
snapshot_after() {
    {
        echo "=== SNAPSHOT DESPUES ==="
        echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "disco_used: $(get_disk_used)"
        echo "disco_pct:  $(get_disk_pct)"

        if has_podman; then
            echo "podman_overlay_size:  $(get_overlay_size "$PODMAN_OVERLAY")"
            echo "podman_layer_count:   $(get_layer_count "$PODMAN_OVERLAY")"
            echo "podman_containers:    $(get_containers_count)"
            echo "podman_images:        $(get_images_count)"
        fi

        if has_docker && [[ "$INCLUDE_DOCKER" -eq 1 ]]; then
            echo "docker_overlay_size:  $(get_overlay_size "$DOCKER_OVERLAY")"
            echo "docker_layer_count:   $(get_layer_count "$DOCKER_OVERLAY")"
        fi
    } > "$OUTDIR/snapshot-after.txt" 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# Monitoreo background (disco en tiempo real)
# ─────────────────────────────────────────────────────────────────────────────
start_monitor() {
    local pid_file="$OUTDIR/.monitor-pid"
    (
        local count=0
        while true; do
            count=$((count + 1))
            echo "[$(date +%H:%M:%S)] df: $(df -h / | awk 'NR==2{print $3 " usado, " $5}') | overlay: $(get_overlay_size "$PODMAN_OVERLAY") | capas: $(get_layer_count "$PODMAN_OVERLAY")"
            sleep "$INTERVAL"
        done
    ) > "$OUTDIR/monitor.log" 2>&1 &
    echo $! > "$pid_file"
    info "Monitor background iniciado (PID: $(cat "$pid_file"))"
}

stop_monitor() {
    local pid_file="$OUTDIR/.monitor-pid"
    if [[ -f "$pid_file" ]]; then
        kill "$(cat "$pid_file")" 2>/dev/null || true
        rm -f "$pid_file"
        info "Monitor background detenido"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Backup de images.json
# ─────────────────────────────────────────────────────────────────────────────
backup_images_json() {
    if [[ -f "$PODMAN_IMAGES_JSON" ]]; then
        cp "$PODMAN_IMAGES_JSON" "$OUTDIR/images.json.bak"
        info "Backup de images.json guardado en ${OUTDIR}/images.json.bak"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Top 10 capas mas grandes
# ─────────────────────────────────────────────────────────────────────────────
top_layers() {
    local path="${1:-$PODMAN_OVERLAY}"
    du -sh "$path"/* 2>/dev/null | sort -rh | head -10 > "$OUTDIR/top-layers.txt" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Confirmacion interactiva
# ─────────────────────────────────────────────────────────────────────────────
confirm() {
    local msg="$1"
    if [[ "$YES" -eq 1 ]]; then
        echo -e "${YELLOW}${BOLD}  ⚠${RESET}  ${msg} (--yes: continuando sin confirmacion)"
        return 0
    fi
    echo -e "${YELLOW}${BOLD}  ⚠${RESET}  ${msg}"
    echo -ne "  ${BOLD}Continuar? [y/N]:${RESET} "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# Generar REPORTE.md
# ══════════════════════════════════════════════════════════════════════════════
generate_report() {
    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Generando REPORTE.md${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    local disk_before="" disk_after="" disk_pct_before="" disk_pct_after=""
    local overlay_before="" overlay_after="" layers_before="" layers_after=""
    local containers_before="" containers_after="" images_before="" images_after=""

    if [[ -f "$OUTDIR/snapshot-before.txt" ]]; then
        disk_before=$(grep "disco_used:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "N/D")
        disk_pct_before=$(grep "disco_pct:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "N/D")
        overlay_before=$(grep "podman_overlay_size:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "N/D")
        layers_before=$(grep "podman_layer_count:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "0")
        containers_before=$(grep "podman_containers:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "0")
        images_before=$(grep "podman_images:" "$OUTDIR/snapshot-before.txt" | cut -d' ' -f2 || echo "0")
    fi

    if [[ -f "$OUTDIR/snapshot-after.txt" ]]; then
        disk_after=$(grep "disco_used:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "N/D")
        disk_pct_after=$(grep "disco_pct:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "N/D")
        overlay_after=$(grep "podman_overlay_size:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "N/D")
        layers_after=$(grep "podman_layer_count:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "0")
        containers_after=$(grep "podman_containers:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "0")
        images_after=$(grep "podman_images:" "$OUTDIR/snapshot-after.txt" | cut -d' ' -f2 || echo "0")
    fi

    local layers_freed=$((layers_before - layers_after))
    local layers_freed_abs=${layers_freed#-}

    {
        echo "# Reporte de limpieza de contenedores — $(hostname)"
        echo
        echo "**Fecha:** $(date)"
        echo "**Nivel ejecutado:** ${LEVEL}"
        echo "**Directorio de evidencia:** ${OUTDIR}"
        echo

        echo "## Resultado"
        echo
        echo "| Metrica | Antes | Despues | Delta |"
        echo "|---------|-------|---------|-------|"

        echo "| Disco usado | ${disk_before} (${disk_pct_before}) | ${disk_after} (${disk_pct_after}) | — |"

        if [[ "$HAS_PODMAN" -eq 1 ]]; then
            echo "| Overlay (size) | ${overlay_before} | ${overlay_after} | — |"
            echo "| Capas (count) | ${layers_before} | ${layers_after} | -${layers_freed_abs} |"
            echo "| Contenedores | ${containers_before} | ${containers_after} | — |"
            echo "| Imagenes | ${images_before} | ${images_after} | — |"
        fi

        echo

        echo "## Niveles ejecutados"
        echo
        [[ "$LEVEL" -ge 1 ]] && echo "- [x] Nivel 1 — Container prune"
        [[ "$LEVEL" -ge 2 ]] && echo "- [x] Nivel 2 — Image prune"
        [[ "$LEVEL" -ge 3 ]] && echo "- [x] Nivel 3 — Builder prune"
        [[ "$LEVEL" -ge 4 ]] && echo "- [x] Nivel 4 — System prune + volumes"
        [[ "$LEVEL" -ge 5 ]] && echo "- [x] Nivel 5 — Storage reset (rm -rf overlay)"
        echo

        echo "## Log de monitor (disco en tiempo real)"
        echo
        echo '```'
        cat "$OUTDIR/monitor.log" 2>/dev/null || echo "(monitor no disponible)"
        echo '```'
        echo

        echo "## Top 10 capas antes de limpiar"
        echo
        echo '```'
        cat "$OUTDIR/top-layers-before.txt" 2>/dev/null || echo "(no disponible)"
        echo '```'
        echo

        if [[ "$LEVEL" -ge 1 ]]; then
            echo "## Top 10 capas despues de limpiar"
            echo
            echo '```'
            cat "$OUTDIR/top-layers-after.txt" 2>/dev/null || echo "(no disponible)"
            echo '```'
            echo
        fi

        if [[ "$LEVEL" -ge 5 ]]; then
            echo "## Post-nivel 5: reinicializar storage"
            echo
            echo '```bash'
            echo "podman system reset"
            echo '```'
            echo
        fi

        echo "---"
        echo "*Reporte generado por podman_cleanup_linux.sh v1.0.0*"
    } > "$report"

    success "REPORTE.md generado: ${BOLD}${report}${RESET}"
}

# ══════════════════════════════════════════════════════════════════════════════
# Empaquetar resultados
# ══════════════════════════════════════════════════════════════════════════════
package_results() {
    echo
    info "Empaquetando resultados..."

    TARNAME="$(basename "$OUTDIR").tar.gz"
    tar czf "/tmp/${TARNAME}" -C /tmp "$(basename "$OUTDIR")"

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Limpieza nivel ${LEVEL} completado${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  Evidencia: ${BOLD}${OUTDIR}/${RESET}"
    echo -e "  Reporte:   ${BOLD}${report}${RESET}"
    echo -e "  Tarball:   ${BOLD}/tmp/${TARNAME}${RESET}"
    echo
    echo -e "  Para traer a tu maquina local:"
    echo -e "  ${CYAN}scp $(hostname):/tmp/${TARNAME} .${RESET}"

    if [[ "$LEVEL" -ge 5 ]]; then
        echo
        warn "Despues de nivel 5, ejecuta ${BOLD}podman system reset${RESET} para reinicializar."
    fi
    echo
}

# ══════════════════════════════════════════════════════════════════════════════
# EJECUCION
# ══════════════════════════════════════════════════════════════════════════════

echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Podman/Docker Cleanup — Nivel ${LEVEL}${RESET}"
echo -e "  Host:    $(hostname)"
echo -e "  Evidencia en: ${OUTDIR}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

# ── Detectar runtimes ───────────────────────────────────────────────────────
HAS_PODMAN=0; HAS_DOCKER=0
has_podman && { HAS_PODMAN=1; info "Podman detectado: $(podman --version | head -1)"; }
has_docker && { if [[ "$PODMAN_ONLY" -eq 0 ]] || [[ "$INCLUDE_DOCKER" -eq 1 ]]; then
    if docker --version 2>/dev/null | grep -qi podman; then
        info "Docker detectado como alias de Podman (podman-docker) — omitiendo limpieza Docker"
    else
        HAS_DOCKER=1; info "Docker detectado: $(docker --version | head -1)"
    fi
fi; }

if [[ "$HAS_PODMAN" -eq 0 ]] && [[ "$HAS_DOCKER" -eq 0 ]]; then
    error "ni Podman ni Docker detectados — nada que limpiar."
    exit 1
fi

# ── Check contenedores running ───────────────────────────────────────────────
if [[ "$LEVEL" -ge 4 ]] && [[ "$FORCE" -eq 0 ]]; then
    if has_running_podman; then
        warn "Podman tiene contenedores running:"
        podman ps --format "  {{.Names}} ({{.Status}})" 2>/dev/null
        if ! confirm "Hay contenedores Podman running. Nivel ${LEVEL} puede afectarlos."; then
            error "abortado."
            exit 1
        fi
    fi
    if [[ "$HAS_DOCKER" -eq 1 ]] && has_running_docker; then
        warn "Docker tiene contenedores running"
        if ! confirm "Hay contenedores Docker running. Nivel ${LEVEL} puede afectarlos."; then
            error "abortado."
            exit 1
        fi
    fi
fi

# ── Confirmacion niveles destructivos ────────────────────────────────────────
if [[ "$LEVEL" -ge 3 ]]; then
    echo
    warn "Nivel ${LEVEL} — operacion destructiva."
    echo -e "  ${YELLOW}Acciones:${RESET}"
    [[ "$LEVEL" -ge 3 ]] && echo "  - podman/docker builder prune"
    [[ "$LEVEL" -ge 4 ]] && echo "  - podman/docker system prune (TODO + volumenes)"
    [[ "$LEVEL" -ge 5 ]] && echo "  - rm -rf overlay/*  (nuclear, borrado directo)"
    echo
    if ! confirm "Seguro que queres continuar con nivel ${LEVEL}?"; then
        error "abortado por el usuario."
        exit 1
    fi
fi

# ── Backup ───────────────────────────────────────────────────────────────────
backup_images_json

# ── Snapshot antes ───────────────────────────────────────────────────────────
echo
info "Tomando snapshot inicial..."
snapshot_before
cat "$OUTDIR/snapshot-before.txt"
echo

# Top 10 capas
if [[ "$HAS_PODMAN" -eq 1 ]] && [[ -d "$PODMAN_OVERLAY" ]]; then
    info "Top 10 capas mas grandes:"
    du -sh "$PODMAN_OVERLAY"/* 2>/dev/null | sort -rh | head -10 > "$OUTDIR/top-layers-before.txt"
    cat "$OUTDIR/top-layers-before.txt"
    echo
fi

# ── Nivel 0: solo analisis ──────────────────────────────────────────────────
if [[ "$LEVEL" -eq 0 ]]; then
    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}Analisis completado (nivel 0 — solo lectura)${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
    echo "Para ejecutar limpieza:"
    echo "  $0 -l 1          # container prune (seguro)"
    echo "  $0 -l 2          # + image prune (medio)"
    echo "  $0 -l 3 --yes    # + builder prune (agresivo)"
    echo "  $0 -l 4 --yes    # + system prune (nuclear)"
    echo "  $0 -l 5 --yes    # + rm -rf overlay/* (storage reset)"
    echo

    snapshot_after
    cp "$OUTDIR/snapshot-before.txt" "$OUTDIR/snapshot-after.txt"
    generate_report
    package_results
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Iniciar monitoreo background
# ══════════════════════════════════════════════════════════════════════════════
start_monitor

# ══════════════════════════════════════════════════════════════════════════════
# EJECUTAR LIMPIEZA POR NIVEL
# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Ejecutando nivel ${LEVEL}${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

# ── Nivel 1: Container prune ─────────────────────────────────────────────────
if [[ "$LEVEL" -ge 1 ]]; then
    echo
    echo -e "${BOLD}--- Nivel 1: Container prune ---${RESET}"
    if [[ "$HAS_PODMAN" -eq 1 ]]; then
        run_cmd "podman container prune" podman container prune -f
    fi
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        run_cmd "docker container prune" docker container prune -f
    fi
fi

# ── Nivel 2: Image prune ─────────────────────────────────────────────────────
if [[ "$LEVEL" -ge 2 ]]; then
    echo
    echo -e "${BOLD}--- Nivel 2: Image prune ---${RESET}"
    if [[ "$HAS_PODMAN" -eq 1 ]]; then
        run_cmd "podman image prune" podman image prune -af 2>&1 || true
    fi
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        run_cmd "docker image prune" docker image prune -af 2>&1 || true
    fi
fi

# ── Nivel 3: Builder prune ───────────────────────────────────────────────────
if [[ "$LEVEL" -ge 3 ]]; then
    echo
    echo -e "${BOLD}--- Nivel 3: Builder prune ---${RESET}"
    if [[ "$HAS_PODMAN" -eq 1 ]]; then
        run_cmd "podman builder prune" podman builder prune -af 2>&1 || true
    fi
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        run_cmd "docker builder prune" docker builder prune -af 2>&1 || true
    fi
fi

# ── Nivel 4: System prune ────────────────────────────────────────────────────
if [[ "$LEVEL" -ge 4 ]]; then
    echo
    echo -e "${BOLD}--- Nivel 4: System prune + volumes ---${RESET}"
    if [[ "$HAS_PODMAN" -eq 1 ]]; then
        run_cmd "podman system prune" podman system prune -af --volumes 2>&1 || true
    fi
    if [[ "$HAS_DOCKER" -eq 1 ]]; then
        run_cmd "docker system prune" docker system prune -af --volumes 2>&1 || true
    fi
fi

# ── Nivel 5: Storage reset (rm -rf overlay) ──────────────────────────────────
if [[ "$LEVEL" -ge 5 ]]; then
    echo
    echo -e "${RED}${BOLD}--- Nivel 5: Storage reset (rm -rf overlay) ---${RESET}"

    if [[ "$HAS_PODMAN" -eq 1 ]] && [[ -d "$PODMAN_OVERLAY" ]]; then
        warn "Borrando ${BOLD}${PODMAN_OVERLAY}/*${RESET} ..."
        info "Capas antes: $(get_layer_count "$PODMAN_OVERLAY")"
        run_cmd "rm podman overlay" bash -c "rm -rf ${PODMAN_OVERLAY}/*" || true
        info "Capas despues: $(get_layer_count "$PODMAN_OVERLAY")"
        success "Overlay de Podman vaciado"
        echo
        warn "Despues de nivel 5, es necesario reinicializar el storage:"
        echo "  ${CYAN}podman system reset${RESET}"
    fi

    if [[ "$HAS_DOCKER" -eq 1 ]] && [[ -d "$DOCKER_OVERLAY" ]]; then
        warn "Borrando ${BOLD}${DOCKER_OVERLAY}/*${RESET} ..."
        run_cmd "rm docker overlay" bash -c "sudo rm -rf ${DOCKER_OVERLAY}/*" || true
        success "Overlay de Docker vaciado"
    fi
fi

echo

# ══════════════════════════════════════════════════════════════════════════════
# Detener monitoreo y tomar snapshot final
# ══════════════════════════════════════════════════════════════════════════════
stop_monitor
echo
info "Tomando snapshot final..."
snapshot_after

# Top 10 capas despues
if [[ "$HAS_PODMAN" -eq 1 ]] && [[ -d "$PODMAN_OVERLAY" ]]; then
    du -sh "$PODMAN_OVERLAY"/* 2>/dev/null | sort -rh | head -10 > "$OUTDIR/top-layers-after.txt" || true
fi

generate_report
package_results
