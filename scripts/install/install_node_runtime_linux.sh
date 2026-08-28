#!/usr/bin/env bash
# shellcheck shell=bash
# Descarga Node.js oficial, lo instala localmente y lo registra en mise.
set -Eeuo pipefail
umask 077

ACTION="check"
VERSION="lts"
RUNTIME_ROOT="${HOME}/.local/share/node-runtimes"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRAPER="${SCRIPT_DIR}/scrape_node_runtime.py"
REGISTRY="${SCRIPT_DIR}/runtime_registry_linux.sh"
MISE_BIN="${HOME}/.local/bin/mise"
TEMP_DIR=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso:
  install_node_runtime_linux.sh --check
  install_node_runtime_linux.sh --plan [--version lts|22|24.20.0]
  install_node_runtime_linux.sh --apply [--version lts|22|24.20.0]

Node.js se descarga desde nodejs.org, se verifica con SHA-256 y se registra
en mise mediante mise link/use. Este script nunca descarga con mise.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --version) (($# >= 2)) || die 'falta valor para --version'; VERSION="$2"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$VERSION" =~ ^(lts|[0-9]+|v?[0-9]+\.[0-9]+\.[0-9]+)$ ]] || die 'versión inválida'
}

find_mise() {
  [[ -x "$MISE_BIN" ]] && { printf '%s\n' "$MISE_BIN"; return; }
  command -v mise
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)[sys.argv[2]])
PY
}

check_installation() {
  echo '═══ Node.js local y mise ═══'
  printf 'root=%s\n' "$RUNTIME_ROOT"
  if [[ -L "${RUNTIME_ROOT}/current-node" ]]; then
    printf 'current=%s\n' "$(readlink -f -- "${RUNTIME_ROOT}/current-node")"
    "${RUNTIME_ROOT}/current-node/bin/node" --version 2>/dev/null || true
  else
    printf 'current=missing\n'
  fi
  if [[ -f "${HOME}/.local/share/rafex-runtimes/registry.tsv" ]]; then
    awk -F '\t' '$1 == "node" { print $0 }' "${HOME}/.local/share/rafex-runtimes/registry.tsv"
  fi
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v python3 >/dev/null || die 'falta python3'
  command -v curl >/dev/null || die 'falta curl'
  command -v sha256sum >/dev/null || die 'falta sha256sum'
  command -v tar >/dev/null || die 'falta tar'
  [[ -r "$SCRAPER" && -r "$REGISTRY" ]] || die 'faltan scraper o registro'
  if [[ "$ACTION" == check ]]; then check_installation; return; fi
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/node-runtime.XXXXXX")"
  trap 'rm -rf -- "$TEMP_DIR"' EXIT
  local metadata="${TEMP_DIR}/metadata.json"
  python3 "$SCRAPER" --version "$VERSION" >"$metadata"
  local resolved filename url checksum target archive topdir mise_path
  resolved="$(json_field "$metadata" version)"
  filename="$(json_field "$metadata" filename)"
  url="$(json_field "$metadata" download_url)"
  checksum="$(json_field "$metadata" checksum)"
  target="${RUNTIME_ROOT}/node-v${resolved}-linux-$(json_field "$metadata" architecture)"
  echo '═══ Node.js ═══'
  printf 'version=%s\narchivo=%s\nchecksum=%s\n' "$resolved" "$filename" "$checksum"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] descargar y verificar $url"
    info "[plan] instalar en $target"
    info "[plan] mise link --force node@$resolved y mise use --global node@$resolved"
    return
  fi
  find_mise >/dev/null || die 'mise no está instalado; ejecuta primero la etapa runtimes'
  mkdir -p "$RUNTIME_ROOT"
  if [[ ! -x "$target/bin/node" ]]; then
    archive="${TEMP_DIR}/${filename}"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 -o "$archive" "$url"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict -
    topdir="$(tar -tf "$archive" | awk -F/ 'NF > 1 { print $1; exit }')"
    [[ -n "$topdir" ]] || die 'archivo Node.js vacío'
    tar -xJf "$archive" -C "$TEMP_DIR"
    if [[ -e "$target" || -L "$target" ]]; then
      mv -- "$target" "${target}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    mv -- "$TEMP_DIR/$topdir" "$target"
  fi
  mise_path="$(find_mise)"
  "$mise_path" link --force "node@${resolved}" "$target"
  "$mise_path" use --global "node@${resolved}"
  "$mise_path" reshim
  # shellcheck source=/dev/null
  source "$REGISTRY"
  runtime_registry_upsert node nodejs "$resolved" "$target" "$checksum" "$(json_field "$metadata" source_url)"
  ln -sfn -- "$target" "${RUNTIME_ROOT}/current-node"
  ok "Node.js $resolved instalado manualmente e integrado en mise"
  "$target/bin/node" --version
}

main "$@"
