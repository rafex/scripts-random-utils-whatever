#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# install_dotfiles_unix.sh
# Empaqueta los dotfiles de i3wm en un tar.gz distribuible con instalador
# autocontenido. El paquete resultante se copia a cualquier máquina y al
# extraerlo contiene su propio install.sh.
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
BUNDLE_DIR="$DIST_DIR/i3-dotfiles-bundle"
ARCHIVE="$DIST_DIR/i3-dotfiles-bundle.tar.gz"
DRY_RUN="${DRY_RUN:-0}"

SCRIPTS_MAP=(
    "scripts/hardware/notify_volume_linux.sh:volume-notify.sh"
    "scripts/hardware/notify_brightness_linux.sh:brightness-notify.sh"
    "scripts/hardware/notify_kbd_brightness_linux.sh:kbd-brightness-notify.sh"
    "scripts/hardware/notify_power_linux.sh:power-notify.sh"
    "scripts/hardware/screensaver_toggle_linux.sh:screensaver-toggle"
)

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--dist-dir${RESET} <dir>   Directorio de salida (default: dist/)"
    echo -e "  ${CYAN}--dry-run${RESET}         Muestra los pasos sin empaquetar"
    echo -e "  ${CYAN}-h, --help${RESET}        Esta ayuda"
    echo
    echo -e "${BOLD}Ejemplo:${RESET}"
    echo "  $0"
    echo "  $0 --dist-dir ./output"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dist-dir) DIST_DIR="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) error "argumento desconocido: $1"; usage; exit 1 ;;
    esac
done

BUNDLE_DIR="$DIST_DIR/i3-dotfiles-bundle"
ARCHIVE="$DIST_DIR/i3-dotfiles-bundle.tar.gz"

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    local dotfiles_config="$REPO_ROOT/dotfiles/config"

    if [[ ! -d "$dotfiles_config" ]]; then
        error "No se encontró dotfiles/config/ en el repo. Ejecuta desde la raíz del repositorio."
        exit 1
    fi

    if [[ ! -f "$dotfiles_config/i3/config" ]]; then
        error "No se encontró dotfiles/config/i3/config."
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Empaquetar
# ─────────────────────────────────────────────────────────────────────────────
build_bundle() {
    local bundle="$BUNDLE_DIR"
    local dotfiles="$REPO_ROOT/dotfiles"

    info "Preparando bundle en ${BOLD}${bundle#"$REPO_ROOT"/}${RESET}..."
    rm -rf "$bundle"
    mkdir -p "$bundle/scripts"

    # Copiar configs
    info "Copiando configs..."
    cp -r "$dotfiles/config" "$bundle/"

    # Copiar install.sh + deps.txt
    cp "$dotfiles/install.sh" "$bundle/"
    cp "$dotfiles/deps.txt" "$bundle/"

    # Copiar scripts referenciados (renombrar según nombre en ~/.local/bin/)
    info "Copiando scripts auxiliares..."
    for entry in "${SCRIPTS_MAP[@]}"; do
        local src="${entry%%:*}"
        local dst="${entry##*:}"
        local src_path="$REPO_ROOT/$src"
        if [[ -f "$src_path" ]]; then
            cp "$src_path" "$bundle/scripts/$dst"
            success "  ${src#"$REPO_ROOT"/} → scripts/${dst}"
        else
            warn "  ${src} no encontrado — se omite"
        fi
    done

    # Asegurar permisos
    chmod +x "$bundle/install.sh"
    chmod +x "$bundle/scripts/"* 2>/dev/null || true

    # Crear tar.gz
    info "Empaquetando ${BOLD}${ARCHIVE#"$REPO_ROOT"/}${RESET}..."
    mkdir -p "$DIST_DIR"
    rm -f "$ARCHIVE"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] tar czf ${ARCHIVE#"$REPO_ROOT"/} -C ${DIST_DIR} i3-dotfiles-bundle/"
        success "Simulación completada (--dry-run)."
        return 0
    fi

    # macOS: evitar archivos ._* (Apple resource forks) en el tar
    COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" -C "$DIST_DIR" "i3-dotfiles-bundle"

    echo
    success "${BOLD}Paquete generado: ${ARCHIVE#"$REPO_ROOT"/}${RESET}"

    local size
    size="$(du -h "$ARCHIVE" | cut -f1)"
    echo
    echo -e "  Tamaño:       ${BOLD}${size}${RESET}"
    echo -e "  Destino:       ${BOLD}dist/i3-dotfiles-bundle.tar.gz${RESET}"
    echo
    echo -e "  ${BOLD}Para instalarlo en otra máquina:${RESET}"
    echo -e "  ${CYAN}  scp dist/i3-dotfiles-bundle.tar.gz user@machine:~/${RESET}"
    echo -e "  ${CYAN}  ssh user@machine${RESET}"
    echo -e "  ${CYAN}  tar xzf i3-dotfiles-bundle.tar.gz${RESET}"
    echo -e "  ${CYAN}  cd i3-dotfiles-bundle && ./install.sh${RESET}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  i3 Dotfiles — Empaquetador${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

preflight
build_bundle
