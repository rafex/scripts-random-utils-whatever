#!/usr/bin/env bash
# Instala herramientas de auditoría y laboratorio por etapas.
# No ejecuta escaneos, capturas, ataques, cracking ni inicia servicios.
set -Eeuo pipefail

umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
TARGET_USER="$(id -un)"
readonly TARGET_USER

ACTION="check"
STAGE="base"
ASSUME_YES=0

readonly -a BASE_PACKAGES=(
    nmap ncat ndiff tcpdump tshark wireshark
    mtr-tiny bind9-dnsutils whois arp-scan
    ethtool iw socat lsof strace usbutils libcap2-bin
)
readonly -a WIRELESS_PACKAGES=(
    aircrack-ng hcxdumptool hcxtools macchanger wireless-tools
)
# Kismet fue retirado de Debian Testing/Forky. Se conserva como referencia
# informativa, pero su ausencia no debe impedir instalar la etapa wireless.
readonly -a OPTIONAL_WIRELESS_PACKAGES=(kismet)
readonly -a WEB_PACKAGES=(
    ffuf gobuster nikto whatweb mitmproxy dirb
)
readonly -a FORENSICS_PACKAGES=(
    sleuthkit testdisk yara hashdeep ssdeep rkhunter
)
readonly -a CREDENTIALS_PACKAGES=(
    john hydra hashcat
)
readonly -a VIRTUALIZATION_PACKAGES=(
    qemu-system-x86 qemu-utils
    libvirt-daemon-system libvirt-clients
    virt-manager virt-viewer ovmf swtpm
)

info() { printf '→ %s\n' "$*"; }
success() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Uso: $SCRIPT_NAME [acción] [opciones]

Acciones:
  --check                 Auditar plataforma y paquetes de la etapa (predeterminada)
  --plan                  Mostrar acciones sin modificar el sistema
  --apply                 Instalar la etapa seleccionada
  --status                Mostrar herramientas, Wi-Fi, dumpcap y virtualización

Opciones:
  --stage NOMBRE          base|wireless|web|forensics|credentials|virtualization|all
  --yes                   No solicitar confirmación para etapas sensibles
  --help                  Mostrar esta ayuda

Ejemplos:
  $SCRIPT_NAME --check
  $SCRIPT_NAME --plan --stage base
  $SCRIPT_NAME --apply --stage base
  $SCRIPT_NAME --apply --stage wireless
  $SCRIPT_NAME --status
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --check)
                ACTION="check"
                ;;
            --plan|--dry-run)
                ACTION="plan"
                ;;
            --apply)
                ACTION="apply"
                ;;
            --status)
                ACTION="status"
                ;;
            --stage)
                (($# >= 2)) || die "--stage requiere un valor"
                STAGE="$2"
                shift
                ;;
            --yes)
                ASSUME_YES=1
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "opción desconocida: $1 (usa --help)"
                ;;
        esac
        shift
    done

    case "$STAGE" in
        base|wireless|web|forensics|credentials|virtualization|all) ;;
        *) die "etapa desconocida: $STAGE" ;;
    esac
}

require_linux_debian() {
    [[ "$(uname -s)" == "Linux" ]] || die "este instalador solo funciona en Linux"
    [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "ejecútalo como usuario normal; sudo se usa internamente en --apply"
    [[ -r /etc/os-release ]] || die "no se puede identificar la distribución"
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "debian" ]] || die "se requiere Debian; distribución detectada: ${ID:-desconocida}"
    command -v dpkg-query >/dev/null 2>&1 || die "falta dpkg-query"
    command -v apt-cache >/dev/null 2>&1 || die "falta apt-cache"
    command -v apt-get >/dev/null 2>&1 || die "falta apt-get"
    if [[ "$ACTION" == "apply" ]]; then
        command -v sudo >/dev/null 2>&1 || die "falta sudo para --apply"
    fi
}

stage_names() {
    if [[ "$STAGE" == "all" ]]; then
        printf '%s\n' base wireless web forensics credentials virtualization
    else
        printf '%s\n' "$STAGE"
    fi
}

stage_packages() {
    case "$1" in
        base) printf '%s\n' "${BASE_PACKAGES[@]}" ;;
        wireless) printf '%s\n' "${WIRELESS_PACKAGES[@]}" ;;
        web) printf '%s\n' "${WEB_PACKAGES[@]}" ;;
        forensics) printf '%s\n' "${FORENSICS_PACKAGES[@]}" ;;
        credentials) printf '%s\n' "${CREDENTIALS_PACKAGES[@]}" ;;
        virtualization) printf '%s\n' "${VIRTUALIZATION_PACKAGES[@]}" ;;
        *) die "etapa no soportada: $1" ;;
    esac
}

selected_packages() {
    local stage
    while IFS= read -r stage; do
        stage_packages "$stage"
    done < <(stage_names) | sort -u
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'
}

package_candidate() {
    # apt-cache traduce las etiquetas según LANG (por ejemplo, "Candidato:")
    # y el resto del instalador necesita una salida estable para analizarla.
    LC_ALL=C apt-cache policy "$1" 2>/dev/null |
        awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

package_installed_size_kb() {
    dpkg-query -W -f='${Installed-Size}' "$1" 2>/dev/null || printf '0'
}

show_package_report() {
    local package installed_count=0 missing_count=0
    printf '═══ Paquetes de la etapa %s ═══\n' "$STAGE"
    while IFS= read -r package; do
        if package_installed "$package"; then
            printf '✓ %-24s instalado\n' "$package"
            installed_count=$((installed_count + 1))
        else
            printf '✗ %-24s ausente\n' "$package"
            missing_count=$((missing_count + 1))
        fi
    done < <(selected_packages)
    printf 'resumen: instalados=%d ausentes=%d\n' "$installed_count" "$missing_count"
}

show_optional_package_report() {
    local package candidate
    if [[ "$STAGE" == "wireless" || "$STAGE" == "all" ]]; then
        printf '═══ Paquetes opcionales no bloqueantes ═══\n'
        for package in "${OPTIONAL_WIRELESS_PACKAGES[@]}"; do
            if package_installed "$package"; then
                printf '✓ %-24s instalado\n' "$package"
                continue
            fi
            candidate="$(package_candidate "$package")"
            if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
                printf '⚠ %-24s sin candidato Debian; se omite\n' "$package"
            else
                printf '○ %-24s disponible (%s), no se instala automáticamente\n' "$package" "$candidate"
            fi
        done
    fi
}

show_stage_sizes() {
    local original_stage="$STAGE" stage package size total
    printf '═══ Tamaño aproximado por etapa ═══\n'
    STAGE="all"
    while IFS= read -r stage; do
        total=0
        while IFS= read -r package; do
            if package_installed "$package"; then
                size="$(package_installed_size_kb "$package")"
                [[ "$size" =~ ^[0-9]+$ ]] || size=0
                total=$((total + size))
            fi
        done < <(stage_packages "$stage")
        printf '%-16s %8s KiB\n' "$stage" "$total"
    done < <(stage_names)
    STAGE="$original_stage"
}

show_dumpcap_status() {
    local dumpcap_path permissions mode_bits capabilities groups getcap_path
    dumpcap_path="$(command -v dumpcap || true)"
    permissions=''
    capabilities=''
    groups="$(id -nG "$TARGET_USER" 2>/dev/null || true)"
    printf '═══ Privilegios de captura Wireshark ═══\n'
    if [[ -z "$dumpcap_path" ]]; then
        warn "dumpcap no está instalado"
        return 0
    fi
    permissions="$(stat -c '%A %U:%G' "$dumpcap_path" 2>/dev/null || true)"
    getcap_path="$(command -v getcap 2>/dev/null || true)"
    if [[ -n "$getcap_path" ]]; then
        capabilities="$($getcap_path "$dumpcap_path" 2>/dev/null || true)"
    else
        capabilities='no verificada: falta getcap'
    fi
    printf 'dumpcap=%s\n' "$dumpcap_path"
    printf 'permisos=%s\n' "${permissions:-desconocidos}"
    printf 'capabilities=%s\n' "${capabilities:-ninguna detectada}"
    if [[ "$groups" == *wireshark* ]]; then
        warn "el usuario pertenece al grupo wireshark; la política recomienda no usarlo"
    else
        success "el usuario no pertenece al grupo wireshark"
    fi
    mode_bits="$(stat -c '%A' "$dumpcap_path" 2>/dev/null || true)"
    if [[ "$mode_bits" == *s* || "$capabilities" == *cap_net_* ]]; then
        warn "dumpcap tiene privilegios persistentes; revísalos y no ejecutes Wireshark como root"
    elif [[ "$capabilities" == no\ verificada* ]]; then
        warn 'no se pudo verificar la ausencia de capacidades de dumpcap'
    else
        success "no se detectó SUID ni capacidad persistente en dumpcap"
    fi
}

normalize_dumpcap_privileges() {
    local dumpcap_path getcap_path setcap_path mode_bits capabilities
    dumpcap_path="$(command -v dumpcap 2>/dev/null || true)"
    [[ -n "$dumpcap_path" ]] || return 0
    getcap_path="$(command -v getcap 2>/dev/null || true)"
    setcap_path="$(command -v setcap 2>/dev/null || true)"
    [[ -n "$getcap_path" && -n "$setcap_path" ]] ||
        die 'no se puede normalizar dumpcap: instala libcap2-bin y repite --apply'

    capabilities="$($getcap_path "$dumpcap_path" 2>/dev/null || true)"
    mode_bits="$(stat -c '%A' "$dumpcap_path" 2>/dev/null || true)"
    if [[ "$capabilities" == *cap_net_* ]]; then
        info 'eliminando capacidades persistentes de dumpcap'
        sudo "$setcap_path" -r "$dumpcap_path"
    fi
    if [[ "$mode_bits" == *s* ]]; then
        info 'eliminando SUID de dumpcap'
        sudo chmod u-s "$dumpcap_path"
    fi

    capabilities="$($getcap_path "$dumpcap_path" 2>/dev/null || true)"
    mode_bits="$(stat -c '%A' "$dumpcap_path" 2>/dev/null || true)"
    [[ "$mode_bits" != *s* && "$capabilities" != *cap_net_* ]] ||
        die 'dumpcap conserva privilegios persistentes después de la normalización'
    success 'dumpcap quedó reservado para capturas explícitas con sudo'
}

show_wireless_status() {
    local iface dev_path driver transport
    printf '═══ Adaptadores inalámbricos ═══\n'
    if ! command -v iw >/dev/null 2>&1; then
        warn "iw no está instalado; instala la etapa base para inspeccionar Wi-Fi"
        return 0
    fi
    iw dev 2>/dev/null || warn "no se pudieron enumerar interfaces con iw"
    while IFS= read -r iface; do
        [[ -n "$iface" ]] || continue
        dev_path="/sys/class/net/$iface/device"
        driver="desconocido"
        transport="integrado/PCI"
        if [[ -L "$dev_path/driver" ]]; then
            driver="$(basename "$(readlink "$dev_path/driver")")"
        fi
        if [[ "$(readlink -f "$dev_path" 2>/dev/null || true)" == */usb/* ]]; then
            transport="USB externo"
        fi
        printf 'interface=%s driver=%s transporte=%s\n' "$iface" "$driver" "$transport"
    done < <(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }')
    printf '%s\n' 'modos soportados (si el adaptador los anuncia):'
    iw list 2>/dev/null |
        sed -n '/Supported interface modes:/,/valid interface combinations:/p' ||
        warn "no se pudo consultar iw list"
    info "no se ejecuta airmon-ng check kill ni se altera NetworkManager"
}

show_virtualization_status() {
    local cpu_flag=''
    printf '═══ Virtualización ═══\n'
    cpu_flag="$(grep -Eom1 '(^|[[:space:]])(vmx|svm)([[:space:]]|$)' /proc/cpuinfo 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$cpu_flag" ]]; then
        success "la CPU anuncia $cpu_flag"
    else
        warn "no se detectó vmx/svm en /proc/cpuinfo"
    fi
    if [[ -e /dev/kvm ]]; then
        success "/dev/kvm presente"
    else
        warn "/dev/kvm ausente; puede requerir virtualización activada en firmware"
    fi
    if getent group kvm >/dev/null 2>&1; then
        if id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx kvm; then
            success "$TARGET_USER pertenece al grupo kvm"
        else
            warn "$TARGET_USER todavía no pertenece al grupo kvm"
        fi
    else
        warn "el grupo kvm aún no existe"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        local service state
        for service in kismet mitmproxy libvirtd; do
            state="$(systemctl is-enabled "$service" 2>/dev/null || true)"
            printf 'servicio %-12s %s\n' "$service" "${state:-no instalado/desconocido}"
        done
    fi
    info "se usará preferentemente qemu:///session; no se crean bridges ni se abren puertos"
}

show_tool_versions() {
    local command_name version
    printf '═══ Herramientas disponibles ═══\n'
    for command_name in nmap tcpdump tshark wireshark aircrack-ng kismet ffuf gobuster fls john hashcat virsh; do
        if command -v "$command_name" >/dev/null 2>&1; then
            version="$("$command_name" --version 2>&1 | head -n 1 || true)"
            printf '✓ %-14s %s\n' "$command_name" "${version:-disponible}"
        else
            printf '✗ %-14s ausente\n' "$command_name"
        fi
    done
}

show_status() {
    local requested_stage="$STAGE"
    STAGE="all"
    printf '═══ Laboratorio de seguridad ═══\n'
    printf 'usuario=%s\n' "$TARGET_USER"
    show_package_report
    show_optional_package_report
    show_tool_versions
    show_dumpcap_status
    show_wireless_status
    show_virtualization_status
    show_stage_sizes
    printf 'servicios: no se habilitan ni arrancan automáticamente\n'
    printf 'red: NetworkManager y UFW permanecen sin cambios\n'
    STAGE="$requested_stage"
}

show_check() {
    printf '═══ Laboratorio de seguridad: comprobación ═══\n'
    printf 'distribución=%s\n' "${PRETTY_NAME:-Debian}"
    printf 'etapa=%s\n' "$STAGE"
    show_package_report
    show_optional_package_report
    info "--check no actualiza índices APT, no instala paquetes y no cambia servicios"
}

show_plan() {
    local package
    printf '═══ Plan laboratorio de seguridad ═══\n'
    printf 'etapa=%s\n' "$STAGE"
    printf 'paquetes:\n'
    while IFS= read -r package; do
        printf '  - %s\n' "$package"
    done < <(selected_packages)
    info '[plan] sudo -v (solo se ejecuta durante --apply)'
    info '[plan] sudo apt-get update'
    info '[plan] comprobar candidato APT para cada paquete'
    info '[plan] sudo apt-get install -y ...'
    if [[ "$STAGE" == virtualization || "$STAGE" == all ]]; then
        info '[plan] añadir únicamente el usuario actual al grupo kvm si existe'
        info '[plan] no añadir el usuario al grupo libvirt, no crear bridges y no abrir puertos'
    fi
    warn 'no se ejecutarán escaneos, capturas, ataques, cracking ni servicios de Kismet/mitmproxy'
    if [[ "$STAGE" == wireless || "$STAGE" == web || "$STAGE" == forensics || "$STAGE" == credentials || "$STAGE" == all ]]; then
        warn 'esta etapa requiere autorización explícita y mostrará una confirmación durante --apply'
    fi
}

validate_candidates() {
    local package candidate missing=0
    while IFS= read -r package; do
        candidate="$(package_candidate "$package")"
        if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
            warn "sin candidato APT: $package"
            missing=1
        fi
    done < <(selected_packages)
    ((missing == 0)) || die 'uno o más paquetes no tienen candidato APT; revisa las fuentes Debian'
}

confirm_sensitive_stage() {
    case "$STAGE" in
        wireless|web|forensics|credentials|all)
            warn "vas a instalar la etapa sensible '$STAGE'; úsala solo en equipos, redes y datos autorizados"
            if ((ASSUME_YES == 0)); then
                [[ -t 0 || -t 1 ]] || die 'la confirmación requiere una terminal; usa --yes solo si ya autorizaste esta instalación'
                local answer
                read -r -p '¿Continuar? [y/N] ' answer
                [[ "$answer" =~ ^([yY][eE][sS]|[yY])$ ]] || die 'instalación cancelada'
            fi
            ;;
    esac
}

install_selected_packages() {
    local -a packages=()
    mapfile -t packages < <(selected_packages)
    ((${#packages[@]} > 0)) || die 'no hay paquetes para instalar'
    validate_candidates
    sudo apt-get install -y "${packages[@]}"
}

configure_kvm_access() {
    if ! getent group kvm >/dev/null 2>&1; then
        warn 'el grupo kvm no existe después de instalar; no se modificaron grupos'
        return 0
    fi
    if id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx kvm; then
        success "$TARGET_USER ya pertenece al grupo kvm"
    else
        sudo usermod -aG kvm "$TARGET_USER"
        success "$TARGET_USER añadido únicamente al grupo kvm; abre una nueva sesión para aplicarlo"
    fi
    info 'no se añadió el usuario al grupo libvirt y no se configuró una red bridge'
}

apply_stage() {
    confirm_sensitive_stage
    sudo -v
    info "actualizando índices APT para la etapa '$STAGE'"
    sudo apt-get update
    validate_candidates
    info "instalando paquetes de la etapa '$STAGE'"
    install_selected_packages
    if [[ "$STAGE" == base || "$STAGE" == all ]]; then
        normalize_dumpcap_privileges
    fi
    if [[ "$STAGE" == virtualization || "$STAGE" == all ]]; then
        configure_kvm_access
    fi
    success "etapa '$STAGE' instalada"
    warn 'cierra y abre la sesión para que el grupo kvm tenga efecto, si fue añadido'
}

parse_args "$@"
require_linux_debian

# shellcheck disable=SC2154
case "$ACTION" in
    check) show_check ;;
    plan) show_plan ;;
    apply) apply_stage ;;
    status) show_status ;;
    *) die "acción interna no válida: $ACTION" ;;
esac
