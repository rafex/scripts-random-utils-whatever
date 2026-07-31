#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# i3-dotfiles install.sh
# Instalador autocontenido para dotfiles de i3wm.
# Se ejecuta desde dentro del tar.gz extraído: ./install.sh
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
# 1. Detectar shell del usuario y archivo RC
# ─────────────────────────────────────────────────────────────────────────────
detect_shell() {
    USER_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)" || USER_SHELL="$SHELL"
    case "$USER_SHELL" in
        */zsh)
            RC_FILE="$HOME/.zshrc"
            SHELL_NAME="zsh"
            ;;
        */bash)
            RC_FILE="$HOME/.bashrc"
            SHELL_NAME="bash"
            ;;
        */fish)
            RC_FILE="$HOME/.config/fish/config.fish"
            SHELL_NAME="fish"
            ;;
        *)
            RC_FILE="$HOME/.profile"
            SHELL_NAME="$(basename "$USER_SHELL")"
            ;;
    esac
    success "Shell detectado: ${BOLD}${SHELL_NAME}${RESET} (RC: ${RC_FILE})"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Verificar sudo
# ─────────────────────────────────────────────────────────────────────────────
check_sudo() {
    if sudo -n true 2>/dev/null; then
        HAS_SUDO=true
        success "sudo disponible."
    else
        HAS_SUDO=false
        warn "sudo no disponible (o requiere contraseña interactiva)."
        warn "No se podrán instalar paquetes del sistema."
        warn "Los dotfiles se instalarán solo en espacio de usuario (~/.config)."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Instalar paquetes (solo si hay sudo)
# ─────────────────────────────────────────────────────────────────────────────
install_packages() {
    if [[ "$HAS_SUDO" != "true" ]]; then
        warn "Saltando instalación de paquetes (sin sudo)."
        echo
        echo -e "  Paquetes requeridos (instálalos manualmente):"
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            echo -e "    ${CYAN}${pkg}${RESET}"
        done < "$SCRIPT_DIR/deps.txt"
        echo
        return
    fi

    info "Instalando paquetes desde deps.txt..."
    local pkgs=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        pkgs+=("$pkg")
    done < "$SCRIPT_DIR/deps.txt"

    sudo apt-get update -qq
    sudo apt-get install -y "${pkgs[@]}"
    success "Paquetes instalados."
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Backup de configs existentes
# ─────────────────────────────────────────────────────────────────────────────
backup_existing() {
    local target="$1"
    local backup_name
    backup_name="${target}.bak.$(date +%Y%m%d_%H%M%S)"

    if [[ -e "$target" && ! -L "$target" ]]; then
        info "Respaldando ${BOLD}${target}${RESET} → ${backup_name}"
        mv "$target" "$backup_name"
    elif [[ -L "$target" ]]; then
        info "Eliminando symlink anterior: ${BOLD}${target}${RESET}"
        rm "$target"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Copiar configs a ~/.config/
# ─────────────────────────────────────────────────────────────────────────────
install_configs() {
    info "Instalando configs en ${BOLD}~/.config/${RESET}..."
    local config_src="$SCRIPT_DIR/config"

    for dir in i3 i3status rofi dunst alacritty picom; do
        local src="$config_src/$dir"
        local dest="$HOME/.config/$dir"

        if [[ ! -d "$src" ]]; then
            warn "Directorio fuente no encontrado: ${src} — se omite"
            continue
        fi

        mkdir -p "$(dirname "$dest")"

        shopt -s dotglob
        for file in "$src"/*; do
            [[ -f "$file" ]] || continue
            local fname="${file##*/}"
            local target="$dest/$fname"
            backup_existing "$target"
            mkdir -p "$dest"
            cp "$file" "$target"
            chmod 644 "$target"
            success "  ${dest#"$HOME"/}/$fname"
        done
        shopt -u dotglob
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Instalar Xresources
# ─────────────────────────────────────────────────────────────────────────────
install_xresources() {
    local src="$SCRIPT_DIR/config/Xresources"
    local dest="$HOME/.Xresources"

    if [[ ! -f "$src" ]]; then
        warn "Xresources no encontrado — se omite."
        return
    fi

    backup_existing "$dest"
    cp "$src" "$dest"
    chmod 644 "$dest"
    success "  .Xresources"
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Instalar scripts en ~/.local/bin/
# ─────────────────────────────────────────────────────────────────────────────
install_scripts() {
    info "Instalando scripts en ${BOLD}~/.local/bin/${RESET}..."
    local scripts_src="$SCRIPT_DIR/scripts"

    if [[ ! -d "$scripts_src" ]]; then
        warn "Directorio scripts no encontrado — se omite."
        return
    fi

    mkdir -p "$HOME/.local/bin"

    for script in "$scripts_src"/*; do
        [[ -f "$script" ]] || continue
        local fname="${script##*/}"
        local target="$HOME/.local/bin/$fname"
        backup_existing "$target"
        cp "$script" "$target"
        chmod 755 "$target"
        success "  ~/.local/bin/$fname"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. Crear directorios de imágenes
# ─────────────────────────────────────────────────────────────────────────────
create_image_dirs() {
    info "Creando directorios de imágenes..."
    mkdir -p "$HOME/Imágenes/FondosDePantalla"
    mkdir -p "$HOME/Imágenes/CapturasDePantalla"
    success "  ~/Imágenes/FondosDePantalla/"
    success "  ~/Imágenes/CapturasDePantalla/"
    warn "No olvides copiar un wallpaper a: ~/Imágenes/FondosDePantalla/wallpaper.jpg"
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. Inyectar variables de entorno en el RC file
# ─────────────────────────────────────────────────────────────────────────────
inject_env_vars() {
    local marker_start="# >>> i3-dotfiles (auto-generated) >>>"
    local marker_end="# <<< i3-dotfiles <<<"
    local rc="$RC_FILE"

    info "Inyectando variables de entorno en ${BOLD}${rc#"$HOME"/}${RESET}..."

    # Crear RC file si no existe
    if [[ ! -f "$rc" ]]; then
        touch "$rc"
    fi

    # Eliminar bloque anterior si existe
    if grep -q "$marker_start" "$rc" 2>/dev/null; then
        sed -i.tmp "/$marker_start/,/$marker_end/d" "$rc"
        rm -f "${rc}.tmp"
    fi

    # Añadir nuevo bloque
    cat >> "$rc" <<EOF

$marker_start
export XDG_CURRENT_DESKTOP=i3
export XDG_SESSION_DESKTOP=i3
export DESKTOP_SESSION=i3

if [[ -d "\$HOME/.local/bin" ]]; then
    case ":\$PATH:" in
        *:"\$HOME/.local/bin":*) ;;
        *) export PATH="\$HOME/.local/bin:\$PATH" ;;
    esac
fi
$marker_end
EOF

    success "Variables de entorno agregadas a ${rc#"$HOME"/}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  i3 Dotfiles — Instalador${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    detect_shell
    check_sudo
    echo

    install_packages
    echo

    install_configs
    echo

    install_xresources
    echo

    install_scripts
    echo

    create_image_dirs
    echo

    inject_env_vars
    echo

    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Instalación completada.${RESET}"
    echo
    echo -e "  ${BOLD}Para aplicar los cambios:${RESET}"
    echo -e "  1. Copia un wallpaper a: ~/Imágenes/FondosDePantalla/wallpaper.jpg"
    echo -e "  2. Reinicia la sesión: ${CYAN}i3-msg restart${RESET}"
    echo -e "     o cierra sesión y vuelve a entrar"
    echo -e "  3. Scripts en ~/.local/bin/ están listos para usarse"
    echo
    echo -e "  ${BOLD}Atajos útiles:${RESET}"
    echo -e "  ${CYAN}Mod4+Shift+s${RESET} → Toggle protector de pantalla"
    echo -e "  ${CYAN}Mod4+Shift+p${RESET} → Toggle picom (compositor)"
    echo -e "  ${CYAN}Mod4+Shift+l${RESET} → Bloquear pantalla"
    echo -e "  ${CYAN}Mod4+Shift+f${RESET} → Toggle ventana flotante"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
}

main
