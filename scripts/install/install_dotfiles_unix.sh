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
PROFILE="${PROFILE:-default}"
BUNDLE_DIR="$DIST_DIR/i3-dotfiles-bundle"
ARCHIVE="$DIST_DIR/i3-dotfiles-bundle.tar.gz"
DRY_RUN="${DRY_RUN:-0}"

SCRIPTS_MAP=(
    "scripts/hardware/notify_volume_linux.sh:volume-notify.sh"
    "scripts/hardware/notify_brightness_linux.sh:brightness-notify.sh"
    "scripts/hardware/notify_kbd_brightness_linux.sh:kbd-brightness-notify.sh"
    "scripts/hardware/notify_power_linux.sh:power-notify.sh"
    "scripts/hardware/screensaver_toggle_linux.sh:screensaver-toggle"
    "scripts/hardware/usb_mount_perms_linux.sh:usb-mount-perms"
    "scripts/hardware/autorotate_x1_yoga_linux.sh:autorotate-x1-yoga.sh"
    "scripts/display/hidpi_xorg_linux.sh:hidpi_xorg.sh"
    "scripts/display/screen_auto_mirror_linux.sh:screen-auto-mirror.sh"
    "scripts/display/screen_auto_edge_mirror_linux.sh:screen-auto-edge-mirror.sh"
    "scripts/display/screen_extend_auto_linux.sh:screen-extend-auto.sh"
    "scripts/display/screen_mirror_linux.sh:screen-mirror.sh"
    "scripts/display/screen_projector_linux.sh:screen-projector.sh"
    "scripts/system/theme_toggle_linux.sh:theme-toggle.sh"
    "scripts/system/dunst_smart_start_linux.sh:dunst-smart.sh"
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
    echo -e "  ${CYAN}--profile${RESET} <name>   Perfil de dotfiles (default: default)"
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
        --profile) PROFILE="$2"; shift 2 ;;
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
    local profile_dir="$REPO_ROOT/dotfiles/profiles/$PROFILE"
    local dotfiles_config="$profile_dir/config"

    if [[ ! -d "$profile_dir" || ! -d "$dotfiles_config" ]]; then
        error "No se encontró el perfil dotfiles/profiles/$PROFILE/ en el repo."
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
    local profile_dir="$REPO_ROOT/dotfiles/profiles/$PROFILE"
    local bundle_profile="$bundle/profiles/$PROFILE"

    info "Preparando bundle en ${BOLD}${bundle#"$REPO_ROOT"/}${RESET}..."
    rm -rf "$bundle"
    mkdir -p "$bundle_profile/scripts"

    # Copiar configs
    info "Copiando configs..."
    cp -r "$profile_dir/config" "$bundle_profile/"
    cp "$profile_dir/DEPS.toml" "$bundle_profile/"
    cp "$profile_dir/README.md" "$bundle_profile/"

    # Copiar el instalador y la lista de dependencias del perfil
    cp "$REPO_ROOT/dotfiles/install.sh" "$bundle/"
    cp "$profile_dir/deps.txt" "$bundle_profile/"

    # Copiar scripts referenciados (renombrar según nombre en ~/.local/bin/)
    info "Copiando scripts auxiliares..."
    for entry in "${SCRIPTS_MAP[@]}"; do
        local src="${entry%%:*}"
        local dst="${entry##*:}"
        local src_path="$REPO_ROOT/$src"
        if [[ -f "$src_path" ]]; then
            cp "$src_path" "$bundle_profile/scripts/$dst"
            success "  ${src#"$REPO_ROOT"/} → profiles/$PROFILE/scripts/${dst}"
        else
            warn "  ${src} no encontrado — se omite"
        fi
    done

    # Asegurar permisos
    chmod +x "$bundle/install.sh"
    chmod +x "$bundle_profile/scripts/"* 2>/dev/null || true

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
    echo -e "  ${CYAN}  cd i3-dotfiles-bundle && ./install.sh --profile $PROFILE${RESET}"
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
