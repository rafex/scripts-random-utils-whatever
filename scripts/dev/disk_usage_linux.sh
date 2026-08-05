#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# disk_usage_linux.sh  v1.0.0
# Diagnostico rapido de uso de disco. Identifica que llena el disco con
# sudo, genera evidencia en /tmp y un REPORTE.md con analisis automatico.
# ─────────────────────────────────────────────────────────────────────────────

OUTDIR="/tmp/disk-usage-$(date +%Y%m%d-%H%M%S)"
TOPDIR="${DISK_DIAG_PATH:-/}"
TOP_N="${DISK_DIAG_TOP:-20}"
SIZE_THRESHOLD="${DISK_DIAG_THRESHOLD:-100M}"
DEEP_LEVEL="${DISK_DIAG_DEEP:-3}"
HOURS_OLD="${DISK_DIAG_OLD:-2160}"  # 90 dias

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

run_quiet() {
    "$@" >> "$2" 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  sudo $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}-p, --path${RESET} <dir>        Raiz a analizar (default: ${TOPDIR})"
    echo -e "  ${CYAN}-n, --top${RESET} <N>          Top N archivos/dirs mas grandes (default: ${TOP_N})"
    echo -e "  ${CYAN}-t, --threshold${RESET} <size>  Tamaño minimo para listar archivos (default: ${SIZE_THRESHOLD})"
    echo -e "  ${CYAN}    --deep${RESET} <n>          Niveles de deep scan du (default: ${DEEP_LEVEL})"
    echo -e "  ${CYAN}    --old${RESET} <hours>       Antiguedad para archivos viejos en horas (default: ${HOURS_OLD})"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>      Directorio de salida (default: ${OUTDIR})"
    echo -e "  ${CYAN}-h, --help${RESET}             Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}DISK_DIAG_PATH${RESET}       Raiz a analizar"
    echo -e "  ${CYAN}DISK_DIAG_TOP${RESET}        Top N archivos/directorios"
    echo -e "  ${CYAN}DISK_DIAG_THRESHOLD${RESET}  Tamaño minimo (ej: 50M, 1G)"
    echo -e "  ${CYAN}DISK_DIAG_DEEP${RESET}       Niveles de du profundo"
    echo -e "  ${CYAN}DISK_DIAG_OLD${RESET}        Antiguedad en horas"
    echo
    echo -e "${BOLD}Ejemplo:${RESET}"
    echo "  sudo $0"
    echo "  sudo $0 -p /var -t 10M --top 30"
    echo "  DISK_DIAG_THRESHOLD=500M sudo $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--path)        TOPDIR="$2";         shift 2 ;;
        -n|--top)         TOP_N="$2";          shift 2 ;;
        -t|--threshold)   SIZE_THRESHOLD="$2"; shift 2 ;;
        --deep)           DEEP_LEVEL="$2";     shift 2 ;;
        --old)            HOURS_OLD="$2";      shift 2 ;;
        -o|--output)      OUTDIR="$2";         shift 2 ;;
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
    error "este script requiere sudo para leer directorios del sistema."
    echo "  Ejecutalo con: sudo $0"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Inicializar directorio de salida
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"
report="$OUTDIR/REPORTE.md"

info "Directorio de evidencia: ${BOLD}${OUTDIR}${RESET}"
echo

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 1: Informacion general del disco${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "df -h"
run 01-df-h df -h

info "df -i (inodos)"
run 02-df-i df -i

info "lsblk"
run 03-lsblk lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 2: Duplicacion profunda por niveles${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

for level in $(seq 1 "$DEEP_LEVEL"); do
    info "du -xh -d ${level} ${TOPDIR} | sort -rh | head -${TOP_N}"
    run "04-du-level-${level}" bash -c "du -xh -d ${level} ${TOPDIR} 2>/dev/null | sort -rh | head -${TOP_N}"
done

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 3: Archivos mas grandes${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "find archivos > ${SIZE_THRESHOLD} en ${TOPDIR}"
run 05-large-files find "$TOPDIR" -xdev -type f -size "+${SIZE_THRESHOLD}" -exec ls -lhS {} \; 2>/dev/null | head -"$TOP_N"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 4: Zonas calientes${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

info "Logs grandes"
run 06-large-logs find /var/log -type f -size +50M -exec ls -lh {} \; 2>/dev/null

info "journald"
{ journalctl --disk-usage 2>/dev/null; journalctl --vacuum-size=0 2>&1 | grep -i "deleted\|freed\|disk" || true; } > "$OUTDIR/07-journal.txt" 2>&1

info "docker"
{ docker system df 2>/dev/null || echo "docker no disponible"; } > "$OUTDIR/08-docker.txt" 2>&1

info "podman / containers"
{ podman system df 2>/dev/null || echo "podman no disponible"; echo; ls -laSh /var/lib/containers 2>/dev/null || true; } > "$OUTDIR/09-podman.txt" 2>&1

info "caches" 
{ du -sh /home/*/.cache 2>/dev/null; echo; du -sh /var/cache 2>/dev/null; echo; du -sh /var/cache/apt 2>/dev/null; } > "$OUTDIR/10-caches.txt" 2>&1

info "tmp"
{ du -sh /tmp /var/tmp 2>/dev/null; } > "$OUTDIR/11-tmp.txt" 2>&1

info "snap / flatpak"
{ du -sh /snap 2>/dev/null || true; du -sh /var/lib/snapd 2>/dev/null || true; du -sh /var/lib/flatpak 2>/dev/null || true; } > "$OUTDIR/12-snap-flatpak.txt" 2>&1

info "core dumps"
find / -xdev \( -name 'core' -o -name 'core.*' -o -name '*.core' \) -type f -exec ls -lh {} \; 2>/dev/null | head -"$TOP_N" > "$OUTDIR/13-core-dumps.txt"

info "archivos no accedidos en > ${HOURS_OLD}h"
find "$TOPDIR" -xdev -type f -atime +$((HOURS_OLD / 24)) -size +10M -exec ls -lhS {} \; 2>/dev/null | head -"$TOP_N" > "$OUTDIR/14-old-files.txt"

info "paquetes grandes"
dpkg-query -Wf '${Installed-Size}\t${Package}\n' 2>/dev/null | sort -rn | head -"$TOP_N" > "$OUTDIR/15-large-packages.txt"

info "apt cache"
apt-get --just-print autoclean 2>/dev/null | head -20 > "$OUTDIR/16-apt-autoclean.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 5: Generando REPORTE.md${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Funciones de analisis
# ─────────────────────────────────────────────────────────────────────────────
get_disk_pct() {
    grep -E "^/dev/" "$OUTDIR/01-df-h.txt" 2>/dev/null | head -1 | awk '{print $5}' | tr -d '%' || echo "0"
}

get_disk_mount() {
    grep -E "^/dev/" "$OUTDIR/01-df-h.txt" 2>/dev/null | head -1 | awk '{print $NF}' || echo "/"
}

get_top_dir() {
    grep -E "^[0-9]" "$OUTDIR/04-du-level-1.txt" 2>/dev/null | head -1 | awk '{print $2" ("$1")"}' || echo "N/D"
}

# ─────────────────────────────────────────────────────────────────────────────
# Generar REPORTE.md
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "# Reporte de diagnostico de disco — $(hostname)"
    echo
    echo "**Fecha:** $(date)"
    echo "**Ruta analizada:** ${TOPDIR}"
    echo "**Directorio de evidencia:** ${OUTDIR}"
    echo

    DISK_PCT=$(get_disk_pct)

    echo "## Resumen"
    echo
    if [[ "$DISK_PCT" -ge 98 ]]; then
        echo "🔴 **CRITICO:** Disco al ${DISK_PCT}% — el sistema esta en riesgo inminente."
    elif [[ "$DISK_PCT" -ge 90 ]]; then
        echo "🔴 **PELIGRO:** Disco al ${DISK_PCT}% — quedan pocos GB libres."
    elif [[ "$DISK_PCT" -ge 85 ]]; then
        echo "🟡 **PRECAUCION:** Disco al ${DISK_PCT}% — monitorear y planificar limpieza."
    else
        echo "🟢 **OK:** Disco al ${DISK_PCT}% — dentro de rangos normales."
    fi
    echo

    TOP_DIR=$(get_top_dir)
    echo "**Directorio dominante:** ${TOP_DIR}"
    echo

    echo "## Hallazgos"
    echo
    echo "| Check | Estado | Detalle |"
    echo "|-------|--------|---------|"

    # Disco
    local_emoji="🟢"; if [[ "$DISK_PCT" -ge 95 ]]; then local_emoji="🔴"; elif [[ "$DISK_PCT" -ge 85 ]]; then local_emoji="🟡"; fi
    echo "| Uso del disco | ${local_emoji} | ${DISK_PCT}% en $(get_disk_mount) |"

    # Top directorio
    TOP_DIR_PCT=$(grep -E "^[0-9]" "$OUTDIR/04-du-level-1.txt" 2>/dev/null | head -1 | awk '{gsub(/[A-Za-z]/,"",$1); print $1}' || echo "0")
    local_emoji="🟢"; if (( $(echo "$TOP_DIR_PCT > 50" | bc -l 2>/dev/null || echo 0) )); then local_emoji="🔴"; elif (( $(echo "$TOP_DIR_PCT > 30" | bc -l 2>/dev/null || echo 0) )); then local_emoji="🟡"; fi
    echo "| Directorio dominante | ${local_emoji} | ${TOP_DIR} |"

    # Journal
    JOURNAL_SIZE=$(grep -oP '[\d.]+[MG]' "$OUTDIR/07-journal.txt" 2>/dev/null | head -1 || echo "N/D")
    local_emoji="🟢"; if echo "$JOURNAL_SIZE" | grep -qi "G"; then local_emoji="🟡"; fi
    echo "| Journal size | ${local_emoji} | ${JOURNAL_SIZE} |"

    # Logs grandes
    LARGE_LOGS=$(wc -l < "$OUTDIR/06-large-logs.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$LARGE_LOGS" -gt 3 ]]; then local_emoji="🟡"; fi
    echo "| Logs > 50MB | ${local_emoji} | ${LARGE_LOGS} archivo(s) |"

    # Docker/Podman
    CONTAINER_LINES=$(grep -ci "GB\|TB" "$OUTDIR/08-docker.txt" "$OUTDIR/09-podman.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$CONTAINER_LINES" -gt 0 ]]; then local_emoji="🟡"; fi
    echo "| Contenedores | ${local_emoji} | $(grep -oP '\d+\.?\d*[GM]B' "$OUTDIR/08-docker.txt" "$OUTDIR/09-podman.txt" 2>/dev/null | head -1 || echo "N/D") |"

    # Core dumps
    CORE_COUNT=$(grep -c "^-rw" "$OUTDIR/13-core-dumps.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$CORE_COUNT" -gt 0 ]]; then local_emoji="🔴"; fi
    echo "| Core dumps | ${local_emoji} | ${CORE_COUNT} archivo(s) |"

    # Old files
    OLD_COUNT=$(grep -c "^-rw" "$OUTDIR/14-old-files.txt" 2>/dev/null || echo "0")
    local_emoji="🟢"; if [[ "$OLD_COUNT" -gt 5 ]]; then local_emoji="🟡"; fi
    echo "| Archivos no accedidos 90+ dias | ${local_emoji} | ${OLD_COUNT} archivo(s) |"

    # Cache
    echo "| Caches /home | 🟢 | ver 10-caches.txt |"

    echo
    echo "## Top 10 directorios mas grandes (nivel 1)"
    echo
    echo '```'
    head -10 "$OUTDIR/04-du-level-1.txt" 2>/dev/null || echo "no disponible"
    echo '```'
    echo

    echo "## Top ${TOP_N} archivos mas grandes (> ${SIZE_THRESHOLD})"
    echo
    echo '```'
    head -"$TOP_N" "$OUTDIR/05-large-files.txt" 2>/dev/null || echo "no disponible"
    echo '```'
    echo

    echo "## Recomendaciones de limpieza"
    echo
    echo "Ejecuta SOLO despues de revisar manualmente:"
    echo
    echo '```bash'
    echo "# 1. Limpiar journal"
    echo "sudo journalctl --vacuum-size=200M"
    echo
    echo "# 2. Limpiar cache APT"
    echo "sudo apt-get clean"
    echo "sudo apt-get autoremove --purge"
    echo
    echo "# 3. Eliminar core dumps"
    echo "sudo find / -xdev -name core -type f -delete"
    echo
    echo "# 4. Docker cleanup (si aplica)"
    echo "docker system prune -af"
    echo
    echo "# 5. Podman cleanup (si aplica)"
    echo "podman system prune -af"
    echo
    echo "# 6. Archivos de cache de usuario"
    echo "du -sh /home/*/.cache  # revisa y limpia manualmente"
    echo '```'
    echo
    echo "---"
    echo "*Reporte generado por disk_usage_linux.sh v1.0.0*"

} > "$report"

success "REPORTE.md generado: ${BOLD}${report}${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Fase 6: Empaquetando${RESET}"
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
