#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# deploy_verify_unix.sh
# Deploya scripts del repo a hosts remotos y verifica checksums.
# Usa find + xargs con procesamiento paralelo (-P4).
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/commons_deploy_verify_unix.sh"

MODE=""
HOST=""
SCRIPTS=()
DRY_RUN=0
PARALLEL="${DEPLOY_PARALLEL:-4}"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}--deploy <host> [script...]${RESET}       Deploya script(s) al host"
    echo -e "  ${CYAN}--verify <host> [script...]${RESET}       Verifica script(s) en el host"
    echo -e "  ${CYAN}--deploy-verify <host> [script...]${RESET} Deploya y verifica en un paso"
    echo -e "  ${CYAN}--verify-all${RESET}                      Verifica todos los hosts en paralelo"
    echo -e "  ${CYAN}--list${RESET}                             Lista hosts y scripts configurados"
    echo -e "  ${CYAN}--check${RESET}                            Verifica hashes locales contra SHA256SUMS"
    echo -e "  ${CYAN}--dry-run${RESET}                          Simular sin ejecutar deploy/copiar"
    echo -e "  ${CYAN}-h, --help${RESET}                         Mostrar esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}DEPLOY_PARALLEL${RESET}   Número de procesos paralelos (default: 4)"
    echo -e "  ${CYAN}PATH_TOML${RESET}         Ruta al archivo PATH.toml"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 --deploy-verify bastion-usb-wifi"
    echo "  $0 --verify bastion-usb-wifi scripts/network/nm_force_ip_linux.sh"
    echo "  $0 --verify-all"
    echo "  $0 --list"
    echo "  $0 --check"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then usage; exit 0; fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deploy|--verify|--deploy-verify)
                MODE="${1#--}"
                HOST="$2"
                shift 2
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    SCRIPTS+=("$1")
                    shift
                done
                return
                ;;
            --verify-all)
                MODE="verify-all"
                shift
                return
                ;;
            --list)
                MODE="list"
                shift
                return
                ;;
            --check)
                MODE="check"
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
                fatal "argumento desconocido: $1"; echo; usage; exit 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones
# ─────────────────────────────────────────────────────────────────────────────
validate_host() {
    local host="$1"
    if ! list_hosts | grep -qxF "$host"; then
        fatal "Host ${BOLD}$host${RESET} no encontrado en PATH.toml"
        echo
        info "Hosts disponibles:"
        list_hosts | while read -r h; do info "  - $h"; done
        exit 1
    fi

    local target
    target="$(ssh_target "$host")"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "echo ok" &>/dev/null; then
            warn "No se pudo conectar a ${BOLD}$target${RESET}. ¿Está accesible por SSH?"
            read -rp "$(echo -e "${YELLOW}¿Continuar de todas formas? [s/N]:${RESET} ")" confirm
            [[ "$confirm" != "s" && "$confirm" != "S" ]] && exit 0
        fi
    fi
}

get_scripts_list() {
    local scripts=()
    if [[ ${#SCRIPTS[@]} -gt 0 ]]; then
        scripts=("${SCRIPTS[@]}")
    fi
    if [[ ${#scripts[@]} -eq 0 ]]; then
        local tmpfile
        tmpfile="$(mktemp /tmp/scripts_list.XXXXXX)"
        find_mapped_scripts > "$tmpfile"
        while IFS= read -r line; do
            [[ -n "$line" ]] && scripts+=("$line")
        done < "$tmpfile"
        rm -f "$tmpfile"
    fi
    if [[ ${#scripts[@]} -eq 0 ]]; then
        fatal "No hay scripts mapeados en PATH.toml ni especificados."
        exit 1
    fi
    printf '%s\n' "${scripts[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy + verify all scripts (por host)
# ─────────────────────────────────────────────────────────────────────────────
deploy_verify_host() {
    local host="$1" script="$2"
    local remote_name result=0
    remote_name="$(get_script_remote_name "$script")"

    if [[ -z "$remote_name" ]]; then
        error "Script ${BOLD}$script${RESET} no está mapeado en PATH.toml — se omite."
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] deploy + verify: $script → ${host}:$(remote_path_for_script "$host" "$script")"
        return 0
    fi

    deploy_one "$host" "$script" || result=1
    verify_one "$host" "$script" 0 || result=1
    return "$result"
}

do_deploy_verify() {
    validate_host "$HOST"

    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Deploy + Verify → ${HOST}${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    local scripts_list=()
    local tmpfile
    tmpfile="$(mktemp /tmp/deploy_scripts.XXXXXX)"
    get_scripts_list > "$tmpfile"
    while IFS= read -r line; do
        [[ -n "$line" ]] && scripts_list+=("$line")
    done < "$tmpfile"
    rm -f "$tmpfile"

    local total="${#scripts_list[@]}" ok=0 fail=0
    info "Procesando ${BOLD}${total}${RESET} scripts (paralelo max ${PARALLEL})..."
    echo

    local running=0
    for script in "${scripts_list[@]}"; do
        (
            if deploy_verify_host "$HOST" "$script"; then
                echo "OK"
            else
                echo "FAIL"
            fi
        ) &
        running=$((running + 1))
        if [[ $running -ge $PARALLEL ]]; then
            wait -n 2>/dev/null || true
            running=$((running - 1))
        fi
    done
    wait

    echo
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    info "Deploy + verify completado (${total} scripts)."
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Solo verificar
# ─────────────────────────────────────────────────────────────────────────────
do_verify() {
    validate_host "$HOST"

    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Verificar → ${HOST}${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    local scripts_list=()
    local tmpfile
    tmpfile="$(mktemp /tmp/deploy_scripts.XXXXXX)"
    get_scripts_list > "$tmpfile"
    while IFS= read -r line; do
        [[ -n "$line" ]] && scripts_list+=("$line")
    done < "$tmpfile"
    rm -f "$tmpfile"

    info "Verificando ${BOLD}${#scripts_list[@]}${RESET} scripts (paralelo max ${PARALLEL})..."
    echo

    if [[ "$DRY_RUN" -eq 1 ]]; then
        for script in "${scripts_list[@]}"; do
            info "[dry-run] verificar: $script → ${HOST}:$(remote_path_for_script "$HOST" "$script")"
        done
    else
        local running=0
        for script in "${scripts_list[@]}"; do
            ( verify_one "$HOST" "$script" 0 ) &
            running=$((running + 1))
            if [[ $running -ge $PARALLEL ]]; then
                wait -n 2>/dev/null || true
                running=$((running - 1))
            fi
        done
        wait
    fi

    echo
    success "Verificación completada."
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify all hosts (paralelo)
# ─────────────────────────────────────────────────────────────────────────────
verify_host_parallel() {
    local host="$1"
    echo -e "\n${BOLD}${CYAN}─── ${host} ───${RESET}"

    local scripts_list=()
    local tmpfile
    tmpfile="$(mktemp /tmp/verify_scripts.XXXXXX)"
    find_mapped_scripts > "$tmpfile"
    while IFS= read -r line; do
        [[ -n "$line" ]] && scripts_list+=("$line")
    done < "$tmpfile"
    rm -f "$tmpfile"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        for script in "${scripts_list[@]}"; do
            info "[dry-run] verificar: $script → ${host}:$(remote_path_for_script "$host" "$script")"
        done
        return 0
    fi

    local running=0
    for script in "${scripts_list[@]}"; do
        ( verify_one "$host" "$script" 1 ) &
        running=$((running + 1))
        if [[ $running -ge $PARALLEL ]]; then
            wait -n 2>/dev/null || true
            running=$((running - 1))
        fi
    done
    wait
}

do_verify_all() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Verify All — todos los hosts en paralelo${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    local hosts=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && hosts+=("$line")
    done < <(list_hosts)

    if [[ ${#hosts[@]} -eq 0 ]]; then
        error "No hay hosts configurados en PATH.toml"
        exit 1
    fi

    info "Hosts: ${hosts[*]}"
    echo

    for host in "${hosts[@]}"; do
        verify_host_parallel "$host" &
    done
    wait

    echo
    success "Verificación all completada."
}

# ─────────────────────────────────────────────────────────────────────────────
# List config
# ─────────────────────────────────────────────────────────────────────────────
do_list() {
    echo -e "\n${BOLD}${CYAN}═══ Hosts configurados ═══${RESET}"
    local hosts=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && hosts+=("$line")
    done < <(list_hosts)

    if [[ ${#hosts[@]} -eq 0 ]]; then
        warn "No hay hosts en PATH.toml"
    fi

    for host in "${hosts[@]}"; do
        local address base
        address="$(get_host_value "$host" "address")"
        base="$(get_host_value "$host" "base_path")"
        echo -e "  ${BOLD}${host}${RESET} → ${address} (${base})"
    done

    echo -e "\n${BOLD}${CYAN}═══ Scripts mapeados ═══${RESET}"
    toml_list_section "$PATH_TOML" "scripts" | while IFS='=' read -r src name; do
        echo -e "  ${CYAN}${src}${RESET} → ${BOLD}${name}${RESET}"
    done

    echo -e "\n${BOLD}${CYAN}═══ Search paths (fallback) ═══${RESET}"
    toml_list_array "$PATH_TOML" "search" "paths" | while read -r p; do
        echo -e "  ${p}"
    done
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
        deploy-verify) do_deploy_verify ;;
        deploy)        do_deploy_verify ;;  # deploy + verify implicit
        verify)        do_verify ;;
        verify-all)    do_verify_all ;;
        list)          do_list ;;
        check)         verify_local_checksums ;;
        *)             fatal "modo desconocido: $MODE"; usage; exit 1 ;;
    esac
}

main "$@"
