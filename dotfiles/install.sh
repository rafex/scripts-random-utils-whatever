#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# i3-dotfiles install.sh
# Instalador autocontenido para dotfiles de i3wm con soporte de perfiles.
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

PROFILE="default"
DRY_RUN=0
PROFILES_DIR="$SCRIPT_DIR/profiles"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--profile <name>${RESET}   Perfil a instalar (default: default)"
    echo -e "  ${CYAN}--list-profiles${RESET}    Lista perfiles disponibles y sale"
    echo -e "  ${CYAN}--dry-run${RESET}          Muestra acciones sin ejecutarlas"
    echo -e "  ${CYAN}-h, --help${RESET}         Muestra esta ayuda"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0"
    echo "  $0 --profile macbook-pro-late2012"
    echo "  $0 --list-profiles"
    echo "  $0 --profile macbook-pro-late2012 --dry-run"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --list-profiles)
                list_profiles
                exit 0
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
}

# ─────────────────────────────────────────────────────────────────────────────
# Listar perfiles disponibles
# ─────────────────────────────────────────────────────────────────────────────
list_profiles() {
    echo -e "${BOLD}Perfiles disponibles:${RESET}"
    if [[ ! -d "$PROFILES_DIR" ]]; then
        warn "Directorio profiles/ no encontrado."
        return 0
    fi
    for d in "$PROFILES_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name
        name="$(basename "$d")"
                local count
                count="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$name" == "$PROFILE" ]]; then
            echo -e "  ${GREEN}${BOLD}* $name${RESET} (${count} archivos) ← activo"
        else
            echo -e "  ${CYAN}$name${RESET} (${count} archivos)"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Validar que el perfil existe
# ─────────────────────────────────────────────────────────────────────────────
validate_profile() {
    local profile_dir="$PROFILES_DIR/$PROFILE"
    if [[ ! -d "$profile_dir" ]]; then
        error "perfil ${BOLD}$PROFILE${RESET} no encontrado en ${BOLD}$PROFILES_DIR/${RESET}."
        echo
        list_profiles
        exit 1
    fi

    local config_dir="$profile_dir/config"
    if [[ ! -d "$config_dir" ]]; then
        error "el perfil ${BOLD}$PROFILE${RESET} no tiene directorio config/."
        exit 1
    fi
}

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
    local deps_file="$PROFILES_DIR/$PROFILE/deps.txt"

    if [[ ! -f "$deps_file" ]]; then
        warn "Archivo deps.txt no encontrado para el perfil ${BOLD}$PROFILE${RESET}."
        warn "Saltando instalación de paquetes."
        return 0
    fi

    if [[ "$HAS_SUDO" != "true" ]]; then
        warn "Saltando instalación de paquetes (sin sudo)."
        echo
        echo -e "  Paquetes requeridos (instálalos manualmente):"
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            echo -e "    ${CYAN}${pkg}${RESET}"
        done < "$deps_file"
        echo
        return 0
    fi

    info "Instalando paquetes desde ${BOLD}${deps_file}${RESET}..."
    local pkgs=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        pkgs+=("$pkg")
    done < "$deps_file"

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "deps.txt vacío — no hay paquetes para instalar."
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] apt-get update && apt-get install -y ${pkgs[*]}"
    else
        sudo apt-get update -qq
        sudo apt-get install -y "${pkgs[@]}"
        success "Paquetes instalados."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Backup de configs existentes
# ─────────────────────────────────────────────────────────────────────────────
backup_existing() {
    local target="$1"
    local backup_name
    backup_name="${target}.bak.$(date +%Y%m%d_%H%M%S)"

    if [[ -e "$target" && ! -L "$target" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "[dry-run] backup: ${target} → ${backup_name}"
        else
            info "Respaldando ${BOLD}${target}${RESET} → ${backup_name}"
            mv "$target" "$backup_name"
        fi
    elif [[ -L "$target" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "[dry-run] eliminar symlink: ${target}"
        else
            info "Eliminando symlink anterior: ${BOLD}${target}${RESET}"
            rm "$target"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Copiar configs de directorios a ~/.config/<dir>
#    Detecta automáticamente los directorios dentro de config/
# ─────────────────────────────────────────────────────────────────────────────
install_configs() {
    info "Instalando configs desde perfil ${BOLD}$PROFILE${RESET} a ${BOLD}~/.config/${RESET}..."
    local config_src="$PROFILES_DIR/$PROFILE/config"

    # Mapeo de archivos especiales (fuera de ~/.config/)
    local special_files="Xresources xsession tmux.conf rafex"

    for item in "$config_src"/*; do
        local name="${item##*/}"

        # Saltar archivos especiales (se manejan por separado)
        if echo "$special_files" | grep -qw "$name"; then
            continue
        fi

        # Si es un directorio: copiar recursivamente a ~/.config/<name>/
        if [[ -d "$item" ]]; then
            local dest="$HOME/.config/$name"
            local file_count
            file_count="$(find "$item" -type f 2>/dev/null | wc -l | tr -d ' ')"

            if [[ "$file_count" -eq 0 ]]; then
                warn "  Directorio ${BOLD}$name${RESET} vacío — se omite."
                continue
            fi

            if [[ "$DRY_RUN" -eq 1 ]]; then
                info "[dry-run] instalar directorio: ${BOLD}$name${RESET} → ${dest} (${file_count} archivos)"
                find "$item" -type f | while read -r f; do
                    echo -e "    ${CYAN}→${RESET} ${f#"$item"/}"
                done
                continue
            fi

            backup_existing "$dest"
            mkdir -p "$(dirname "$dest")"
            cp -r "$item" "$dest"
            find "$dest" -type f -exec chmod 644 {} \;
            find "$dest" -type d -exec chmod 755 {} \;
            success "  ${BOLD}$name${RESET}/ (${file_count} archivos)"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 5b. Fusionar paletas sin reemplazar el estado actual del selector
# ─────────────────────────────────────────────────────────────────────────────
install_theme_configs() {
    local source_root="$PROFILES_DIR/$PROFILE/config/rafex/themes"
    local target_root="$HOME/.config/rafex/themes"
    local source_file target_file

    # El perfil Openbox comparte las paletas portables del perfil ThinkPad de
    # i3; no se duplican archivos de temas solo para cambiar de WM.
    if [[ ! -d "$source_root" && "$PROFILE" == "openbox-thinkpad-x1-yoga-1st" ]]; then
        source_root="$PROFILES_DIR/thinkpad-x1-yoga-1st/config/rafex/themes"
    fi
    [[ -d "$source_root" ]] || return 0
    info "Instalando paletas de tema en ${BOLD}${target_root}${RESET}..."
    while IFS= read -r -d '' source_file; do
        target_file="$target_root/${source_file#"$source_root/"}"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "[dry-run] instalar tema: ${target_file}"
            continue
        fi
        mkdir -p "$(dirname "$target_file")"
        if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
            continue
        fi
        backup_existing "$target_file"
        cp "$source_file" "$target_file"
        chmod 644 "$target_file"
    done < <(find "$source_root" -type f -print0)
    success "  paletas paper/nord/everforest/dracula y alias legacy"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6b. Instalar configuración de tmux en ~/.tmux.conf
# ─────────────────────────────────────────────────────────────────────────────
install_tmux_config() {
    local src="$PROFILES_DIR/$PROFILE/config/tmux.conf"
    local dest="$HOME/.tmux.conf"

    if [[ ! -f "$src" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] instalar tmux.conf → ${dest}"
        return 0
    fi

    backup_existing "$dest"
    cp "$src" "$dest"
    chmod 600 "$dest"
    success "  .tmux.conf"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6c. Inicializar Nord como tema por defecto
# ─────────────────────────────────────────────────────────────────────────────
initialize_theme() {
    local theme_root="$HOME/.config/rafex/themes"
    local current="$theme_root/current"

    if [[ ! -d "$theme_root/nord" ]]; then
        return 0
    fi
    if [[ -L "$current" ]]; then
        success "  tema actual: $(readlink "$current")"
        return 0
    fi
    if [[ -e "$current" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "[dry-run] respaldar tema actual: $current"
        else
            backup_existing "$current"
        fi
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] enlazar tema nord → $current"
    else
        ln -s nord "$current"
        printf '%s\n' nord > "$HOME/.config/rafex/theme"
        chmod 600 "$HOME/.config/rafex/theme"
        success "  tema inicial: nord"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Instalar Xresources
# ─────────────────────────────────────────────────────────────────────────────
install_xresources() {
    local src="$PROFILES_DIR/$PROFILE/config/Xresources"
    local dest="$HOME/.Xresources"

    if [[ ! -f "$src" ]]; then
        warn "Xresources no encontrado en el perfil — se omite."
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] instalar Xresources → ${dest}"
        return 0
    fi

    backup_existing "$dest"
    cp "$src" "$dest"
    chmod 644 "$dest"
    success "  .Xresources"
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Instalar xsession
# ─────────────────────────────────────────────────────────────────────────────
install_xsession() {
    local src="$PROFILES_DIR/$PROFILE/config/xsession"
    local dest="$HOME/.xsession"

    if [[ ! -f "$src" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] instalar xsession → ${dest}"
        return 0
    fi

    backup_existing "$dest"
    cp "$src" "$dest"
    chmod 755 "$dest"
    success "  .xsession"
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. Instalar scripts del perfil en ~/.local/bin/
# ─────────────────────────────────────────────────────────────────────────────
install_profile_scripts() {
    local scripts_src="$PROFILES_DIR/$PROFILE/scripts"

    if [[ ! -d "$scripts_src" ]]; then
        [[ "$PROFILE" == "thinkpad-x1-yoga-1st" ]] || return 0
        local direct_script direct_name target
        local direct_scripts=(
            "$SCRIPT_DIR/../scripts/system/theme_toggle_linux.sh:theme-toggle.sh"
            "$SCRIPT_DIR/../scripts/system/dunst_smart_start_linux.sh:dunst-smart.sh"
        )
        for direct_script in "${direct_scripts[@]}"; do
            direct_name="${direct_script##*:}"
            direct_script="${direct_script%%:*}"
            [[ -f "$direct_script" ]] || continue
            target="$HOME/.local/bin/$direct_name"
            if [[ "$DRY_RUN" -eq 1 ]]; then
                info "[dry-run] instalar script: ${target}"
            else
                mkdir -p "$(dirname "$target")"
                backup_existing "$target"
                cp "$direct_script" "$target"
                chmod 755 "$target"
                success "  $direct_name"
            fi
        done
        return 0
    fi

    info "Instalando scripts del perfil en ${BOLD}~/.local/bin/${RESET}..."

    mkdir -p "$HOME/.local/bin"

    shopt -s nullglob dotglob
    for script in "$scripts_src"/*; do
        [[ -f "$script" ]] || continue
        local fname="${script##*/}"
        local target="$HOME/.local/bin/$fname"

        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "  [dry-run] copiar script: $fname → $target"
            continue
        fi

        backup_existing "$target"
        cp "$script" "$target"
        chmod 755 "$target"
        success "  ~/.local/bin/$fname"
    done
    shopt -u dotglob nullglob
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. Crear directorios de imágenes
# ─────────────────────────────────────────────────────────────────────────────
create_image_dirs() {
    info "Creando directorios de imágenes..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] mkdir -p ~/Imágenes/FondosDePantalla ~/Imágenes/CapturasDePantalla"
    else
        mkdir -p "$HOME/Imágenes/FondosDePantalla"
        mkdir -p "$HOME/Imágenes/CapturasDePantalla"
        success "  ~/Imágenes/FondosDePantalla/"
        success "  ~/Imágenes/CapturasDePantalla/"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 9b. Instalar assets portables del perfil
# ─────────────────────────────────────────────────────────────────────────────
install_profile_assets() {
    local assets_src="$PROFILES_DIR/$PROFILE/assets"
    local assets_dest="$HOME/.local/share/rafex/profiles/$PROFILE/assets"
    local source_file target_file relative_path

    # Los assets son opcionales por perfil. Openbox reutiliza los scripts y
    # temas, pero no necesita duplicar los fondos del perfil i3.
    [[ -d "$assets_src" ]] || return 0
    info "Instalando assets del perfil en ${BOLD}${assets_dest}${RESET}..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        while IFS= read -r -d '' source_file; do
            relative_path="${source_file#"$assets_src"/}"
            info "[dry-run] asset: ${relative_path} → ${assets_dest}/${relative_path}"
        done < <(find "$assets_src" -type f -print0)
        return 0
    fi

    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$assets_src"/}"
        target_file="$assets_dest/$relative_path"
        mkdir -p "$(dirname "$target_file")"
        if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
            continue
        fi
        backup_existing "$target_file"
        cp "$source_file" "$target_file"
        chmod 644 "$target_file"
    done < <(find "$assets_src" -type f -print0)
    success "  assets del perfil instalados"
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. Inyectar variables de entorno en el RC file
# ─────────────────────────────────────────────────────────────────────────────
inject_env_vars() {
    local marker_start="# >>> i3-dotfiles (auto-generated) >>>"
    local marker_end="# <<< i3-dotfiles <<<"
    local rc="$RC_FILE"

    # Un perfil paralelo no puede imponer XDG_CURRENT_DESKTOP=openbox en el
    # shell: el usuario puede seguir entrando a i3 desde LightDM. La sesión
    # Openbox se identifica por su .desktop y no por .bashrc.
    if [[ "$PROFILE" == "openbox-thinkpad-x1-yoga-1st" ]]; then
        info "Perfil paralelo: no se cambia el entorno global de $rc"
        return 0
    fi

    info "Inyectando variables de entorno en ${BOLD}${rc#"$HOME"/}${RESET}..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] inyectar vars en $rc"
        return 0
    fi

    if [[ ! -f "$rc" ]]; then
        touch "$rc"
    fi

    if grep -q "$marker_start" "$rc" 2>/dev/null; then
        sed -i.tmp "/$marker_start/,/$marker_end/d" "$rc"
        rm -f "${rc}.tmp"
    fi

    cat >> "$rc" <<'EOF'

# >>> i3-dotfiles (auto-generated) >>>
export XDG_CURRENT_DESKTOP=i3
export XDG_SESSION_DESKTOP=i3
export DESKTOP_SESSION=i3

if [[ -d "$HOME/.local/bin" ]]; then
    case ":$PATH:" in
        *:"$HOME/.local/bin":*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
fi
# <<< i3-dotfiles <<<
EOF

    success "Variables de entorno agregadas a ${rc#"$HOME"/}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 11. Mostrar dependencias externas del perfil (informativo)
# ─────────────────────────────────────────────────────────────────────────────
show_profile_deps() {
    local deps_toml="$PROFILES_DIR/$PROFILE/DEPS.toml"

    if [[ ! -f "$deps_toml" ]]; then
        return 0
    fi

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Dependencias externas del perfil ${BOLD}$PROFILE${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  ${BOLD}DEPS.toml:${RESET} $deps_toml"
    echo -e "  ${BOLD}README.md:${RESET} $PROFILES_DIR/$PROFILE/README.md"
    echo
    echo -e "  ${YELLOW}Revisa DEPS.toml y README.md del perfil para:${RESET}"
    echo -e "  - Scripts de ${CYAN}~/.local/bin/${RESET} que deben copiarse del repo principal"
    echo -e "  - Wallpapers y archivos externos necesarios"
    echo -e "  - Reglas de polkit y configuración post-instalación"
    echo
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

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  i3 Dotfiles — Instalador${RESET}"
    echo -e "${BOLD}  Perfil: ${PROFILE}${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo

    validate_profile

    detect_shell
    check_sudo
    echo

    install_packages
    echo

    install_configs
    echo

    install_theme_configs
    echo

    install_tmux_config
    echo

    initialize_theme
    echo

    install_xresources
    echo

    install_xsession
    echo

    install_profile_scripts
    echo

    create_image_dirs
    echo

    install_profile_assets
    echo

    inject_env_vars
    echo

    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Instalación completada.${RESET}"
    echo
    if [[ -f "$PROFILES_DIR/$PROFILE/README.md" ]]; then
        echo -e "  ${BOLD}Post-instalación:${RESET} revisa ${CYAN}$PROFILES_DIR/$PROFILE/README.md${RESET}"
    fi
    echo -e "  ${BOLD}Para aplicar los cambios:${RESET}"
    if [[ "$PROFILE" == "openbox-thinkpad-x1-yoga-1st" ]]; then
        echo -e "  1. Cierra sesión y selecciona ${CYAN}Openbox${RESET} en LightDM"
        echo -e "     i3 permanece disponible como sesión de recuperación"
    else
        echo -e "  1. Reinicia la sesión: ${CYAN}i3-msg restart${RESET}"
        echo -e "     o cierra sesión y vuelve a entrar"
    fi
    echo

    show_profile_deps

    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo
}

main "$@"
