#!/usr/bin/env bash
# install_java_runtime_linux.sh v1.0.0
# Descarga runtimes Java oficiales en el espacio del usuario y verifica SHA-256.
set -Eeuo pipefail
umask 077

ACTION="check"
PROVIDER="temurin"
VERSION="21"
IMAGE="jdk"
RUNTIME_ROOT="${HOME}/.local/share/java-runtimes"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRAPER="${SCRIPT_DIR}/scrape_java_runtimes.py"
TEMP_DIR=""

usage() {
    cat <<'EOF'
Uso: install_java_runtime_linux.sh [opción]

Descarga un runtime Java oficial en ~/.local/share/java-runtimes.

Opciones:
  --check                         Muestra el estado local (predeterminado)
  --plan | --dry-run              Consulta metadatos y muestra el plan
  --apply                         Descarga, verifica e instala
  --provider NOMBRE               temurin, graalvm-community, graalvm-oracle o semeru
  --version VERSION               latest, mayor o versión exacta según proveedor
  --image jdk|jre                 Imagen a instalar (GraalVM solo admite jdk)
  --root DIRECTORIO               Raíz local alternativa y absoluta
  --help                          Muestra esta ayuda

No usa sudo, no instala en /usr/lib y no cambia la versión global de Java.
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
    printf '✓ activo: %s\n' "$current"
    printf 'Para usarlo en la sesión actual:\n'
    printf '  export JAVA_HOME=%q\n' "$current"
    printf '  export PATH="$%s/bin:$%s"\n' 'JAVA_HOME' 'PATH'
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
    else
        install_runtime "$metadata_file"
        check_installation
    fi
}

main "$@"
