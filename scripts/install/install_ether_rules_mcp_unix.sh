#!/usr/bin/env bash
# install_ether_rules_mcp_unix.sh v1.0.0
# Instala el wheel oficial de Ether-rules y configura clientes MCP locales.
set -Eeuo pipefail
umask 077

ACTION="check"
CLIENT="all"
API_URL="https://api.github.com/repos/rafex/ether-my-best-practice/releases/latest"
TEMP_DIR=""
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_SERVER_COMMAND="uvx"
MCP_SERVER_ARG="ether-mcp"
COMPAT_LAUNCHER="${REPO_ROOT}/tools/ether_rules_mcp_compat.py"

usage() {
    cat <<'EOF'
Uso: install_ether_rules_mcp_unix.sh [opción]

Instala Ether-rules MCP en el espacio del usuario y configura clientes detectados.

Opciones:
  --check                         Diagnóstico local sin red ni cambios (predeterminado)
  --plan | --dry-run              Consulta release y muestra acciones sin cambiar
  --apply                         Descarga, verifica e instala el MCP
  --status                        Muestra estado de ether-mcp y clientes
  --uninstall                     Quita ether-rules de clientes y uv
  --action install|status|uninstall Acción equivalente a las opciones anteriores
  --client all|claude|codex|opencode Clientes a configurar (predeterminado: all detectados)
  --help                          Muestra esta ayuda

No usa sudo ni configura credenciales, API keys o contraseñas.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

info() { printf '→ %s\n' "$1"; }
ok() { printf '✓ %s\n' "$1"; }
warn() { printf '⚠ %s\n' "$1" >&2; }

timestamp() { date '+%Y%m%d_%H%M%S'; }

parse_args() {
    while (($#)); do
        case "$1" in
            --check) ACTION="check" ;;
            --plan|--dry-run) ACTION="plan" ;;
            --apply) ACTION="install" ;;
            --status) ACTION="status" ;;
            --uninstall) ACTION="uninstall" ;;
            --action)
                (($# >= 2)) || die 'falta valor para --action'
                ACTION="$2"
                shift
                ;;
            --client)
                (($# >= 2)) || die 'falta valor para --client'
                CLIENT="$2"
                shift
                ;;
            --help|-h) usage; exit 0 ;;
            *) die "opción desconocida: $1" ;;
        esac
        shift
    done

    case "$ACTION" in
        check|plan|install|status|uninstall) ;;
        *) die "acción no soportada: $ACTION" ;;
    esac
    case "$CLIENT" in
        all|claude|codex|opencode) ;;
        *) die "cliente no soportado: $CLIENT" ;;
    esac
}

require_common_tools() {
    command -v python3 >/dev/null 2>&1 || die 'falta python3'
    command -v curl >/dev/null 2>&1 || die 'falta curl'
}

require_install_tools() {
    command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || die 'falta sha256sum o shasum'
    command -v uv >/dev/null 2>&1 || die 'falta uv; instálalo con el gestor de paquetes del sistema o desde https://docs.astral.sh/uv/'
}

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

client_present() {
    command -v "$1" >/dev/null 2>&1
}

selected_clients() {
    if [[ "$CLIENT" == all ]]; then
        for candidate in claude codex opencode; do
            client_present "$candidate" && printf '%s\n' "$candidate"
        done
    else
        printf '%s\n' "$CLIENT"
    fi
}

config_path() {
    case "$1" in
        claude) printf '%s\n' "${HOME}/.claude.json" ;;
        codex) printf '%s\n' "${HOME}/.codex/config.toml" ;;
        opencode) printf '%s\n' "${HOME}/.config/opencode/opencode.json" ;;
        *) return 1 ;;
    esac
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp -p "$file" "${file}.bak.$(timestamp)"
        info "respaldo creado: ${file}.bak.*"
    fi
}

fetch_release() {
    local output="$1"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        --output "$output" "$API_URL"
}

release_asset() {
    local metadata="$1" kind="$2"
    python3 - "$metadata" "$kind" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    release = json.load(stream)
assets = release.get("assets", [])
kind = sys.argv[2]
if kind == "wheel":
    values = [asset for asset in assets if asset.get("name", "").endswith(".whl")]
else:
    values = [asset for asset in assets if asset.get("name", "").endswith(".whl.sha256")]
if not values:
    raise SystemExit(1)
asset = values[0]
print(asset.get("name", ""))
print(asset.get("browser_download_url", ""))
PY
}

checksum_from_file() {
    local checksum_file="$1"
    python3 - "$checksum_file" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
match = re.search(r"\b([0-9a-fA-F]{64})\b", text)
if not match:
    raise SystemExit("no se encontró SHA-256 en el release")
print(match.group(1).lower())
PY
}

select_server_command() {
    if [[ -f "$COMPAT_LAUNCHER" ]] && command -v ether-mcp >/dev/null 2>&1; then
        if ! ether-mcp --version >/dev/null 2>&1; then
            MCP_SERVER_COMMAND="python3"
            MCP_SERVER_ARG="$COMPAT_LAUNCHER"
            warn 'el wheel upstream no supera --version; se usará el adaptador local de compatibilidad'
        fi
    fi
}

download_and_verify_wheel() {
    local metadata="$1" wheel_path="$2" checksum_path="$3"
    local wheel_name wheel_url checksum_name checksum_url expected actual wheel_data checksum_data
    wheel_data="$(release_asset "$metadata" wheel)" || die 'el release no contiene un wheel válido'
    wheel_name="${wheel_data%%$'\n'*}"
    wheel_url="${wheel_data#*$'\n'}"
    [[ "$wheel_name" != */* && "$wheel_name" != *..* ]] || die 'nombre de wheel inválido'
    [[ "$wheel_url" == https://github.com/* ]] || die 'enlace de wheel fuera del repositorio oficial'

    checksum_data="$(release_asset "$metadata" checksum)" || die 'el release no contiene checksum del wheel'
    checksum_name="${checksum_data%%$'\n'*}"
    checksum_url="${checksum_data#*$'\n'}"
    [[ "$checksum_name" == "$wheel_name.sha256" ]] || die 'checksum no corresponde al wheel'
    [[ "$checksum_url" == https://github.com/* ]] || die 'enlace de checksum fuera del repositorio oficial'

    info "descargando $wheel_name"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --output "$wheel_path" "$wheel_url"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --output "$checksum_path" "$checksum_url"
    expected="$(checksum_from_file "$checksum_path")" || die 'checksum del wheel inválido'
    actual="$(hash_file "$wheel_path")"
    [[ "$actual" == "$expected" ]] || die 'checksum SHA-256 del wheel no coincide'
    ok 'checksum SHA-256 verificado'
}

configure_json_client() {
    local client="$1" config
    config="$(config_path "$client")"
    mkdir -p "$(dirname "$config")"
    python3 - "$client" "$config" <<'PY'
import json
import os
import sys
import tempfile

client, path = sys.argv[1:]
if os.path.exists(path):
    with open(path, encoding="utf-8") as stream:
        config = json.load(stream)
else:
    config = {}

    if client == "claude":
    config.setdefault("mcpServers", {})["ether-rules"] = {
        "command": os.environ["ETHER_MCP_COMMAND"],
        "args": [os.environ["ETHER_MCP_ARG"]],
    }
else:
    config.setdefault("mcp", {})["ether-rules"] = {
        "type": "local",
        "command": [os.environ["ETHER_MCP_COMMAND"], os.environ["ETHER_MCP_ARG"]],
        "enabled": True,
    }

directory = os.path.dirname(path) or "."
fd, temporary = tempfile.mkstemp(prefix=".ether-rules.", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(config, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
except Exception:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
}

configure_codex_fallback() {
    local config
    config="$(config_path codex)"
    mkdir -p "$(dirname "$config")"
    if [[ -f "$config" ]] && grep -Fq '[mcp_servers.ether-rules]' "$config"; then
        ok 'Codex ya tiene ether-rules configurado'
        return 0
    fi
    if [[ -s "$config" ]]; then
        printf '\n' >>"$config"
    fi
    printf '%s\n' '[mcp_servers.ether-rules]' \
        "command = \"${MCP_SERVER_COMMAND}\"" \
        "args = [\"${MCP_SERVER_ARG}\"]" >>"$config"
}

configure_client() {
    local client="$1"
    if ! client_present "$client"; then
        warn "$client no está instalado; se omite configuración"
        return 0
    fi
    local config
    config="$(config_path "$client")"
    # El CLI puede modificar el archivo, por lo que el respaldo debe precederlo.
    backup_file "$config"
    export ETHER_MCP_COMMAND="$MCP_SERVER_COMMAND"
    export ETHER_MCP_ARG="$MCP_SERVER_ARG"
    case "$client" in
        claude)
            if claude mcp add --scope user ether-rules -- "$MCP_SERVER_COMMAND" "$MCP_SERVER_ARG" >/dev/null 2>&1; then
                ok 'Claude configurado mediante su CLI'
            else
                warn 'CLI de Claude no pudo configurar MCP; usando fallback JSON'
                configure_json_client "$client"
            fi
            ;;
        codex)
            if codex mcp add ether-rules -- "$MCP_SERVER_COMMAND" "$MCP_SERVER_ARG" >/dev/null 2>&1; then
                ok 'Codex configurado mediante su CLI'
            else
                warn 'CLI de Codex no pudo configurar MCP; usando fallback TOML'
                configure_codex_fallback
            fi
            ;;
        opencode)
            if opencode mcp add ether-rules -- "$MCP_SERVER_COMMAND" "$MCP_SERVER_ARG" >/dev/null 2>&1; then
                ok 'OpenCode configurado mediante su CLI'
            else
                warn 'CLI de OpenCode no pudo configurar MCP; usando fallback JSON'
                configure_json_client "$client"
            fi
            ;;
    esac
    [[ -e "$config" ]] || warn "no se pudo confirmar la configuración de $client"
}

remove_json_entry() {
    local client="$1" config
    config="$(config_path "$client")"
    [[ -f "$config" ]] || return 0
    backup_file "$config"
    python3 - "$client" "$config" <<'PY'
import json
import os
import sys
import tempfile

client, path = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    config = json.load(stream)
key = "mcpServers" if client == "claude" else "mcp"
if isinstance(config.get(key), dict):
    config[key].pop("ether-rules", None)
directory = os.path.dirname(path) or "."
fd, temporary = tempfile.mkstemp(prefix=".ether-rules.", dir=directory, text=True)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2, ensure_ascii=False)
    stream.write("\n")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
}

remove_codex_fallback() {
    local config="$1" temporary
    [[ -f "$config" ]] || return 0
    backup_file "$config"
    temporary="$(mktemp)"
    awk '
        /^\[mcp_servers\.ether-rules\]$/ { skip=1; next }
        /^\[/ { skip=0 }
        !skip { print }
    ' "$config" >"$temporary"
    chmod 600 "$temporary"
    mv "$temporary" "$config"
}

remove_client() {
    local client="$1" config
    if client_present "$client" && "$client" mcp remove ether-rules >/dev/null 2>&1; then
        ok "$client: ether-rules eliminado mediante su CLI"
        return 0
    fi
    config="$(config_path "$client")"
    if [[ "$client" == codex ]]; then
        remove_codex_fallback "$config"
    else
        remove_json_entry "$client" "$config"
    fi
    ok "$client: entrada ether-rules eliminada si existía"
}

show_status() {
    local verify_version="${1:-0}"
    printf '═══ Estado Ether-rules MCP ═══\n'
    if command -v ether-mcp >/dev/null 2>&1; then
        if [[ "$verify_version" == 1 ]]; then
            local version_output
            if version_output="$(ether-mcp --version 2>&1)"; then
                printf '%s\n' "$version_output" | head -n 1
            else
                warn "ether-mcp existe pero --version terminó con error: $(printf '%s\n' "$version_output" | head -n 1)"
            fi
        else
            printf 'ether-mcp=available\n'
        fi
    else
        printf 'ether-mcp=missing\n'
    fi
    if command -v uv >/dev/null 2>&1; then
        uv tool list 2>/dev/null | grep -i -E 'ether|best-practice' || printf 'uv-tool=ether-mcp no detectado\n'
    else
        printf 'uv=missing\n'
    fi
    while IFS= read -r client; do
        [[ -n "$client" ]] || continue
        if "$client" mcp list 2>/dev/null | grep -qi ether-rules; then
            printf '%s=configured\n' "$client"
        else
            printf '%s=not-configured\n' "$client"
        fi
    done < <(selected_clients)
}

install_mcp() {
    require_install_tools
    mkdir -p "$TEMP_DIR"
    local metadata="${TEMP_DIR}/release.json" wheel_name wheel
    local checksum="${TEMP_DIR}/ether_mcp.whl.sha256"
    fetch_release "$metadata"
    wheel_name="$(release_asset "$metadata" wheel | sed -n '1p')" || die 'el release no contiene un wheel válido'
    [[ "$wheel_name" != */* && "$wheel_name" != *..* ]] || die 'nombre de wheel inválido'
    wheel="${TEMP_DIR}/${wheel_name}"
    download_and_verify_wheel "$metadata" "$wheel" "$checksum"
    info 'instalando wheel en el entorno de herramientas del usuario'
    uv tool install --force "$wheel"
    command -v ether-mcp >/dev/null 2>&1 || warn 'ether-mcp no aparece todavía en PATH; revisa ~/.local/bin'
    select_server_command
    while IFS= read -r client; do
        [[ -n "$client" ]] || continue
        configure_client "$client"
    done < <(selected_clients)
    ok 'Ether-rules MCP instalado'
}

main() {
    parse_args "$@"
    require_common_tools
    case "$ACTION" in
        check)
            show_status 0
            ;;
        status)
            show_status 1
            ;;
        plan)
            TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ether-mcp.XXXXXX")"
            trap 'rm -rf -- "$TEMP_DIR"' EXIT
            fetch_release "${TEMP_DIR}/release.json"
            printf '[plan] descargar wheel y checksum del release oficial\n'
            printf '[plan] instalar con uv tool install\n'
            while IFS= read -r client; do
                [[ -n "$client" ]] && printf '[plan] configurar %s como uvx ether-mcp\n' "$client"
            done < <(selected_clients)
            ;;
        install)
            TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ether-mcp.XXXXXX")"
            trap 'rm -rf -- "$TEMP_DIR"' EXIT
            install_mcp
            ;;
        uninstall)
            while IFS= read -r client; do
                [[ -n "$client" ]] && remove_client "$client"
            done < <(selected_clients)
            if command -v uv >/dev/null 2>&1; then
                uv tool uninstall ether-mcp-my-best-practices >/dev/null 2>&1 || true
                uv tool uninstall ether-mcp >/dev/null 2>&1 || true
            fi
            ok 'desinstalación solicitada completada'
            ;;
    esac
}

main "$@"
