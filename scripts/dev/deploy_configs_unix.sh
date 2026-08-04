#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# deploy_configs_unix.sh
# Deploya configs de dotfiles (Xorg, autorandr, etc.) a hosts remotos.
# Los configs que requieren /etc/ necesitan el flag --sudo.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/commons_deploy_verify_unix.sh"

MODE=""
HOST=""
PROFILE=""
USE_SUDO=0
DRY_RUN=0
CONFIGS_TOML="${CONFIGS_TOML:-$REPO_ROOT/PATH.toml}"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--deploy-verify <host> <profile>${RESET}  Deploya y verifica configs del perfil"
    echo -e "  ${CYAN}--verify <host> <profile>${RESET}         Verifica configs en el host"
    echo -e "  ${CYAN}--sudo${RESET}                            Incluye configs que requieren /etc/ (pide sudo)"
    echo -e "  ${CYAN}--list-profiles${RESET}                    Lista perfiles disponibles"
    echo -e "  ${CYAN}--dry-run${RESET}                          Simular sin ejecutar"
    echo -e "  ${CYAN}-h, --help${RESET}                         Mostrar esta ayuda"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 --deploy-verify macbook-pro-late2012 192.168.3.177"
    echo "  $0 --deploy-verify macbook-pro-late2012 192.168.3.177 --sudo"
    echo "  $0 --verify macbook-pro-late2012 192.168.3.177"
    echo "  $0 --list-profiles"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then usage; exit 0; fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deploy|--verify|--deploy-verify)
                MODE="${1#--}"
                shift
                ;;
            --sudo)
                USE_SUDO=1
                shift
                ;;
            --list-profiles)
                MODE="list-profiles"
                shift
                return
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage; exit 0
                ;;
            *)
                if [[ -z "$PROFILE" ]]; then
                    PROFILE="$1"
                elif [[ -z "$HOST" ]]; then
                    HOST="$1"
                else
                    fatal "argumento desconocido: $1"; echo; usage; exit 1
                fi
                shift
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones
# ─────────────────────────────────────────────────────────────────────────────
validate_profile() {
    local profile_dir="$REPO_ROOT/dotfiles/profiles/$PROFILE"
    if [[ ! -d "$profile_dir" ]]; then
        fatal "Perfil ${BOLD}$PROFILE${RESET} no encontrado en $profile_dir"
        local profiles=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && profiles+=("$line")
        done < <(ls "$REPO_ROOT/dotfiles/profiles/" 2>/dev/null)
        if [[ ${#profiles[@]} -gt 0 ]]; then
            info "Perfiles disponibles:"
            for p in "${profiles[@]}"; do echo "  - $p"; done
        fi
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Leer configs de DEPS.toml del perfil
# ─────────────────────────────────────────────────────────────────────────────
get_system_configs() {
    local deps="$REPO_ROOT/dotfiles/profiles/$PROFILE/DEPS.toml"
    if [[ ! -f "$deps" ]]; then
        echo ""
        return
    fi
    toml_list_array "$deps" "xorg" "system_files"
}

# List all config files in the profile's config/ directory
get_profile_configs() {
    local config_dir="$REPO_ROOT/dotfiles/profiles/$PROFILE/config"
    if [[ ! -d "$config_dir" ]]; then
        echo ""
        return
    fi
    find "$config_dir" -type f | sed "s|$config_dir/||" | sort
}

# ─────────────────────────────────────────────────────────────────────────────
# List profiles
# ─────────────────────────────────────────────────────────────────────────────
do_list_profiles() {
    echo -e "\n${BOLD}${CYAN}═══ Perfiles disponibles ═══${RESET}"
    local profiles_dir="$REPO_ROOT/dotfiles/profiles"
    if [[ ! -d "$profiles_dir" ]]; then
        warn "No hay perfiles en $profiles_dir"
        return
    fi
    for dir in "$profiles_dir"/*/; do
        local name
        name="$(basename "$dir")"
        local count
        count="$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
        echo -e "  ${BOLD}${name}${RESET} (${count} archivos)"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy + verify de configs
# ─────────────────────────────────────────────────────────────────────────────
do_deploy_verify_configs() {
    validate_profile

    local profile_dir="$REPO_ROOT/dotfiles/profiles/$PROFILE"
    local config_src="$profile_dir/config"
    local target
    if [[ -n "$HOST" ]]; then
        target="$(ssh_target "$HOST")"
    fi

    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Deploy configs — perfil: ${PROFILE}${RESET}"
    if [[ -n "$HOST" ]]; then
        echo -e "${BOLD}  Host: ${HOST} (${target:-local})${RESET}"
    else
        echo -e "${BOLD}  Modo: local${RESET}"
    fi
    if [[ "$USE_SUDO" -eq 1 ]]; then
        echo -e "${BOLD}  Sudo: ${RED}activado${RESET} (incluye /etc/...)${RESET}"
    else
        echo -e "${BOLD}  Sudo: desactivado (solo ~/.config/)${RESET}"
    fi
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] deploy de configs del perfil $PROFILE"
        local configs_list
        local configs_list=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && configs_list+=("$line")
        done < <(get_profile_configs)
        local system_configs
        local system_configs=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && system_configs+=("$line")
        done < <(get_system_configs)

        local user_count=0 sudo_count=0
        for cfg in "${configs_list[@]}"; do
            local is_system=0
            for sc in "${system_configs[@]}"; do
                if echo "$cfg" | grep -qF "${sc##*/}"; then
                    is_system=1
                    break
                fi
            done
            if [[ "$is_system" -eq 1 ]]; then
                ((sudo_count++))
                info "  [dry-run/sudo] $cfg → /etc/..."
            else
                ((user_count++))
                info "  [dry-run] $cfg → ~/.config/..."
            fi
        done

        echo
        info "Resumen: ${user_count} sin sudo, ${sudo_count} requieren sudo"
        if [[ "$USE_SUDO" -eq 0 && "$sudo_count" -gt 0 ]]; then
            warn "${sudo_count} archivos requieren /etc/ — usa ${CYAN}--sudo${RESET} para incluirlos."
        fi
        return
    fi

    # Procesar configs user-space (~/.config/)
    local user_count=0
    info "Deployando configs user-space (~/.config/)..."

    if [[ -d "$config_src" ]]; then
        if [[ -n "$HOST" ]]; then
            local target
            target="$(ssh_target "$HOST")"
            scp -r "$config_src"/* "${target}:~/.config/" 2>/dev/null && \
            ssh_exec "$target" "find ~/.config -type f -name '*.conf' -exec chmod 644 {} \; 2>/dev/null" && \
            success "Configs user-space deployados a ${HOST}."
        fi
        user_count="$(find "$config_src" -type f | wc -l | tr -d ' ')"
    fi
    success "${user_count} archivos deployados (sin sudo)"

    # Procesar configs que requieren sudo (/etc/)
    local system_configs
    local system_configs=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && system_configs+=("$line")
    done < <(get_system_configs)

    if [[ ${#system_configs[@]} -gt 0 ]]; then
        echo
        if [[ "$USE_SUDO" -eq 1 ]]; then
            if [[ "$(id -u)" -ne 0 ]]; then
                info "Se requiere sudo para archivos de sistema. Solicitando..."
                sudo -v 2>/dev/null || { error "Sudo no disponible. Omitiendo archivos de /etc/."; USE_SUDO=0; }
            fi

            if [[ "$USE_SUDO" -eq 1 ]]; then
                info "Deployando configs de sistema (/etc/...) con sudo..."
                local sudo_count=0
                for sc in "${system_configs[@]}"; do
                    local src_file="$config_src/${sc##*/}"
                    if [[ -f "$src_file" ]]; then
                        if [[ -n "$HOST" ]]; then
                            ssh_exec "$target" "sudo mkdir -p '$(dirname "$sc")' 2>/dev/null"
                            scp "$src_file" "$target:/tmp/config_$(basename "$sc")"
                            ssh_exec "$target" "sudo cp '/tmp/config_$(basename "$sc")' '$sc' && sudo chmod 644 '$sc' && rm '/tmp/config_$(basename "$sc")'"
                        fi
                        ((sudo_count++))
                    fi
                done
                success "${sudo_count} archivos deployados con sudo (/etc/)"
            fi
        else
            warn "${#system_configs[@]} archivos requieren sudo (omitiendo):"
            for sc in "${system_configs[@]}"; do
                warn "  - $sc"
            done
            warn "${CYAN}Usa --sudo para deployar estos archivos.${RESET}"
        fi
    fi

    echo
    success "Deploy de configs completado."
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

    case "$MODE" in
        deploy-verify|deploy|verify) do_deploy_verify_configs ;;
        list-profiles)               do_list_profiles ;;
        *)                           fatal "modo desconocido: $MODE"; usage; exit 1 ;;
    esac
}

main "$@"
