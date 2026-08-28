#!/usr/bin/env bash
# install_java_runtime_linux.sh v1.0.0
# Descarga runtimes Java oficiales en el espacio del usuario y verifica SHA-256.
set -Eeuo pipefail
umask 077

ACTION="check"
PROVIDER="temurin"
VERSION="21"
IMAGE="jdk"
AUTO_MISE=1
RUNTIME_ROOT="${HOME}/.local/share/java-runtimes"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRAPER="${SCRIPT_DIR}/scrape_java_runtimes.py"
RUNTIME_SWITCHER="${SCRIPT_DIR}/install_runtime_switcher_linux.sh"
REGISTRY="${SCRIPT_DIR}/runtime_registry_linux.sh"
JAVA_HOME_LINK="${HOME}/.local/share/java-runtimes/current-java"
TEMP_DIR=""

usage() {
    cat <<'EOF'
Uso: install_java_runtime_linux.sh [opción]

Descarga un runtime Java oficial en ~/.local/share/java-runtimes y, si mise
está disponible, lo registra automáticamente usando la ruta real instalada.
JAVA_HOME se mantiene en ~/.local/share/java-runtimes/current-java.

Opciones:
  --check                         Muestra el estado local (predeterminado)
  --plan | --dry-run              Consulta metadatos y muestra el plan
  --apply                         Descarga, verifica e instala
  --provider NOMBRE               temurin, graalvm-community, graalvm-oracle o semeru
  --version VERSION               latest, mayor o versión exacta según proveedor
  --image jdk|jre                 Imagen a instalar (GraalVM solo admite jdk)
  --root DIRECTORIO               Raíz local alternativa y absoluta
  --no-mise                       No registrar automáticamente el runtime en mise
  --help                          Muestra esta ayuda

No usa sudo ni instala en /usr/lib. La configuración automática de mise solo
afecta al usuario actual y apunta directamente al directorio de la versión;
mise nunca descarga el runtime.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

timestamp() {
    date '+%Y%m%d_%H%M%S'
}

valid_root() {
    [[ "$1" == /* ]] || die '--root debe ser una ruta absoluta'
    [[ "$1" != "/" && "$1" != */ && "$1" != *..* ]] || die '--root no puede ser /, terminar en / ni contener ..'
}

parse_args() {
    while (($#)); do
        case "$1" in
            --check) ACTION="check" ;;
            --plan|--dry-run) ACTION="plan" ;;
            --apply) ACTION="apply" ;;
            --provider)
                (($# >= 2)) || die 'falta valor para --provider'
                PROVIDER="$2"
                shift
                ;;
            --version)
                (($# >= 2)) || die 'falta valor para --version'
                VERSION="$2"
                shift
                ;;
            --image)
                (($# >= 2)) || die 'falta valor para --image'
                IMAGE="$2"
                shift
                ;;
            --root)
                (($# >= 2)) || die 'falta valor para --root'
                RUNTIME_ROOT="$2"
                shift
                ;;
            --no-mise) AUTO_MISE=0 ;;
            --help|-h) usage; exit 0 ;;
            *) die "opción desconocida: $1" ;;
        esac
        shift
    done

    case "$PROVIDER" in
        temurin|graalvm-community|graalvm-oracle|semeru) ;;
        *) die "proveedor no soportado: $PROVIDER" ;;
    esac
    [[ "$IMAGE" == jdk || "$IMAGE" == jre ]] || die "imagen no soportada: $IMAGE"
    if [[ "$PROVIDER" == graalvm-community || "$PROVIDER" == graalvm-oracle ]] && [[ "$IMAGE" != jdk ]]; then
        die 'GraalVM solo admite --image jdk'
    fi
    [[ "$VERSION" =~ ^[[:alnum:]._-]+$ ]] || die 'versión inválida'
    valid_root "$RUNTIME_ROOT"
}

require_tools() {
    [[ "$(uname -s)" == Linux ]] || die 'este instalador solo soporta Linux'
    command -v python3 >/dev/null 2>&1 || die 'falta python3'
    command -v curl >/dev/null 2>&1 || die 'falta curl'
    command -v sha256sum >/dev/null 2>&1 || die 'falta sha256sum'
    command -v tar >/dev/null 2>&1 || die 'falta tar'
    [[ -r "$SCRAPER" ]] || die "no se encuentra $SCRAPER"
    if [[ "$AUTO_MISE" -eq 1 && ! -r "$REGISTRY" ]]; then
        die "no se encuentra $REGISTRY"
    fi
}

metadata_field() {
    local metadata_file="$1" field="$2"
    python3 - "$metadata_file" "$PROVIDER" "$field" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
value = data["providers"][sys.argv[2]].get(sys.argv[3])
if value is None:
    raise SystemExit(1)
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
else:
    print(value)
PY
}

fetch_metadata() {
    local metadata_file="$1"
    local architecture
    case "$(uname -m)" in
        x86_64|amd64) architecture="x64" ;;
        aarch64|arm64) architecture="aarch64" ;;
        *) die "arquitectura no soportada por los enlaces oficiales: $(uname -m)" ;;
    esac
    python3 "$SCRAPER" \
        --provider "$PROVIDER" \
        --version "$VERSION" \
        --image "$IMAGE" \
        --architecture "$architecture" \
        --pretty >"$metadata_file" \
        || die 'no se pudieron obtener metadatos oficiales del runtime'
}

check_installation() {
    printf '═══ Runtimes Java locales ═══\n'
    printf 'root=%s\n' "$RUNTIME_ROOT"
    if [[ -L "${RUNTIME_ROOT}/current-${PROVIDER}-${IMAGE}" ]]; then
        printf 'current=%s\n' "$(readlink -- "${RUNTIME_ROOT}/current-${PROVIDER}-${IMAGE}")"
        if [[ -x "${RUNTIME_ROOT}/current-${PROVIDER}-${IMAGE}/bin/java" ]]; then
            "${RUNTIME_ROOT}/current-${PROVIDER}-${IMAGE}/bin/java" -version 2>&1 | head -n 1
        fi
    else
        printf 'current=%s\n' 'missing'
    fi
    if [[ -d "${RUNTIME_ROOT}/${PROVIDER}" ]]; then
        find "${RUNTIME_ROOT}/${PROVIDER}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    else
        printf 'instalaciones=%s\n' 'missing'
    fi
    if [[ -L "$JAVA_HOME_LINK" ]]; then
        printf 'JAVA_HOME_link=%s\n' "$(readlink -f -- "$JAVA_HOME_LINK" 2>/dev/null || readlink -- "$JAVA_HOME_LINK")"
    else
        printf 'JAVA_HOME_link=%s\n' 'missing'
    fi
}

install_runtime() {
    local metadata_file="$1"
    local filename download_url checksum algorithm resolved_version
    filename="$(metadata_field "$metadata_file" filename)"
    download_url="$(metadata_field "$metadata_file" download_url)"
    checksum="$(metadata_field "$metadata_file" checksum)"
    algorithm="$(metadata_field "$metadata_file" checksum_algorithm)"
    resolved_version="$(metadata_field "$metadata_file" version)"
    [[ "$algorithm" == sha256 ]] || die "algoritmo no soportado: $algorithm"
    [[ "$checksum" =~ ^[0-9a-fA-F]{64}$ ]] || die 'checksum SHA-256 inválido'
    [[ "$filename" != */* && "$filename" != *..* ]] || die 'nombre de archivo remoto inválido'

    local target="${RUNTIME_ROOT}/${PROVIDER}/${resolved_version}-${IMAGE}"
    local current="${RUNTIME_ROOT}/current-${PROVIDER}-${IMAGE}"
    mkdir -p "${RUNTIME_ROOT}/${PROVIDER}"
    if [[ -x "${target}/bin/java" ]]; then
        printf '✓ ya instalado: %s\n' "$target"
    else
        local archive="${TEMP_DIR}/${filename}"
        printf '→ descargando %s\n' "$download_url"
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            --output "$archive" "$download_url"
        printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict -

        local extract_dir="${TEMP_DIR}/extract"
        mkdir -p "$extract_dir"
        tar --extract --gzip --file "$archive" --directory "$extract_dir"
        local topdir
        topdir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
        [[ -n "$topdir" && -x "${topdir}/bin/java" ]] || die 'el archivo no contiene un JDK/JRE válido'

        if [[ -e "$target" || -L "$target" ]]; then
            mv -- "$target" "${target}.bak.$(timestamp)"
            printf '→ respaldo creado para instalación anterior\n'
        fi
        mv -- "$topdir" "$target"
    fi
    ln -sfn -- "$target" "$current"
    printf '✓ runtime seleccionado: %s\n' "$target"
    if [[ -e "$JAVA_HOME_LINK" && ! -L "$JAVA_HOME_LINK" ]]; then
        die "$JAVA_HOME_LINK existe pero no es un enlace simbólico"
    fi
    mkdir -p "$(dirname -- "$JAVA_HOME_LINK")"
    local target_real current_real temporary_link
    target_real="$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")"
    current_real="$(readlink -f -- "$JAVA_HOME_LINK" 2>/dev/null || true)"
    if [[ "$current_real" != "$target_real" ]]; then
        temporary_link="${JAVA_HOME_LINK}.tmp.$$"
        rm -f -- "$temporary_link"
        ln -s -- "$target_real" "$temporary_link"
        mv -Tf -- "$temporary_link" "$JAVA_HOME_LINK"
    fi
    printf '✓ JAVA_HOME estable: %s\n' "$JAVA_HOME_LINK"
    printf 'Para usarlo en la sesión actual:\n'
    printf '  export JAVA_HOME=%q\n' "$JAVA_HOME_LINK"
    printf '  export PATH="$%s/bin:$%s"\n' 'JAVA_HOME' 'PATH'
}

install_runtime_switcher() {
    [[ -r "$RUNTIME_SWITCHER" ]] || die "no se encuentra $RUNTIME_SWITCHER"
    if [[ "$ACTION" == plan ]]; then
        info "[plan] instalar runtime-use en $HOME/.bashrc"
        return 0
    fi
    bash "$RUNTIME_SWITCHER" --apply
}

configure_mise_after_install() {
    local target="$1" resolved_version="$2" mise_version mise_tool mise_id selection_file
    [[ "$AUTO_MISE" -eq 1 ]] || return 0
    case "$PROVIDER" in
        temurin|semeru) mise_tool="java"; mise_version="$PROVIDER-${resolved_version%%.*}" ;;
        graalvm-community|graalvm-oracle)
            mise_tool="graalvm"
            mise_version="${resolved_version#graal-}"
            mise_version="${mise_version#jdk-}"
            ;;
    esac
    mise_id="${mise_tool}@${mise_version}"
    if [[ "$ACTION" == plan ]]; then
        info "[plan] registrar $mise_id en mise apuntando directamente a $target"
        return 0
    fi
    if ! command -v "$HOME/.local/bin/mise" >/dev/null 2>&1 && ! command -v mise >/dev/null 2>&1; then
        die "mise no está instalado; ejecuta primero install-terminal-workstation --stage runtimes"
    fi
    local mise_path
    mise_path="$(command -v mise 2>/dev/null || printf '%s' "$HOME/.local/bin/mise")"
    "$mise_path" link --force "$mise_id" "$target"
    "$mise_path" use --global "$mise_id"
    "$mise_path" reshim
    selection_file="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/runtime-java-selection"
    mkdir -p "$(dirname -- "$selection_file")"
    printf '%s\n' "$mise_id" >"${selection_file}.tmp.$$"
    chmod 600 "${selection_file}.tmp.$$"
    mv -f -- "${selection_file}.tmp.$$" "$selection_file"
    ok "mise usa directamente: $target"
}

mise_runtime_version() {
    local resolved_version="$1"
    case "$PROVIDER" in
        temurin|semeru) printf '%s-%s\n' "$PROVIDER" "${resolved_version%%.*}" ;;
        graalvm-community|graalvm-oracle)
            resolved_version="${resolved_version#graal-}"
            printf '%s\n' "${resolved_version#jdk-}"
            ;;
    esac
}

main() {
    parse_args "$@"
    require_tools
    if [[ "$ACTION" == check ]]; then
        check_installation
        return 0
    fi

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-runtime.XXXXXX")"
    trap 'rm -rf -- "$TEMP_DIR"' EXIT
    local metadata_file="${TEMP_DIR}/metadata.json"
    fetch_metadata "$metadata_file"
    printf '═══ %s Java ═══\n' "$PROVIDER"
    printf 'version=%s\n' "$(metadata_field "$metadata_file" version)"
    printf 'image=%s\n' "$IMAGE"
    printf 'archivo=%s\n' "$(metadata_field "$metadata_file" filename)"
    printf 'checksum=%s\n' "$(metadata_field "$metadata_file" checksum)"
    printf 'origen=%s\n' "$(metadata_field "$metadata_file" source_url)"
    if [[ "$ACTION" == plan ]]; then
        printf '[plan] instalar en %s\n' "$RUNTIME_ROOT"
        configure_mise_after_install "${RUNTIME_ROOT}/${PROVIDER}/<versión>-<imagen>" '<versión>'
        install_runtime_switcher
    else
        local resolved_version
        resolved_version="$(metadata_field "$metadata_file" version)"
        install_runtime "$metadata_file"
        configure_mise_after_install \
            "${RUNTIME_ROOT}/${PROVIDER}/${resolved_version}-${IMAGE}" \
            "$resolved_version"
        # shellcheck source=/dev/null
        source "$REGISTRY"
        runtime_registry_upsert java "$PROVIDER" "$(mise_runtime_version "$resolved_version")" \
            "${RUNTIME_ROOT}/${PROVIDER}/${resolved_version}-${IMAGE}" \
            "$(metadata_field "$metadata_file" checksum)" \
            "$(metadata_field "$metadata_file" source_url)"
        install_runtime_switcher
        check_installation
    fi
}

main "$@"
