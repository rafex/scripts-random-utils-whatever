#!/usr/bin/env bash
# shellcheck shell=bash
# Descarga Maven o Gradle oficial, lo instala localmente y lo integra en mise.
set -Eeuo pipefail
umask 077

ACTION="check"
TOOL="maven"
VERSION="latest"
RUNTIME_ROOT="${HOME}/.local/share/build-runtimes"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRAPER="${SCRIPT_DIR}/scrape_build_runtime.py"
REGISTRY="${SCRIPT_DIR}/runtime_registry_linux.sh"
MISE_BIN="${HOME}/.local/bin/mise"
TEMP_DIR=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso:
  install_build_runtime_linux.sh --check --tool maven|gradle
  install_build_runtime_linux.sh --plan --tool maven|gradle --version latest|VERSION
  install_build_runtime_linux.sh --apply --tool maven|gradle --version latest|VERSION

Descarga desde Apache Maven o Gradle, verifica checksum y registra la ruta
local en mise. Nunca descarga herramientas mediante mise.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --tool) (($# >= 2)) || die 'falta valor para --tool'; TOOL="$2"; shift ;;
      --version) (($# >= 2)) || die 'falta valor para --version'; VERSION="$2"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$TOOL" == maven || "$TOOL" == gradle ]] || die '--tool debe ser maven o gradle'
}

find_mise() {
  if [[ -x "$MISE_BIN" ]]; then
    printf '%s\n' "$MISE_BIN"
  else
    command -v mise
  fi
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
  echo "═══ $TOOL local y mise ═══"
  printf 'root=%s\n' "$RUNTIME_ROOT"
  if [[ -L "${RUNTIME_ROOT}/current-${TOOL}" ]]; then
    printf 'current=%s\n' "$(readlink -f -- "${RUNTIME_ROOT}/current-${TOOL}")"
  else
    printf 'current=missing\n'
  fi
  [[ -f "${HOME}/.local/share/rafex-runtimes/registry.tsv" ]] && \
    awk -F '\t' -v tool="$TOOL" '$1 == tool { print }' "${HOME}/.local/share/rafex-runtimes/registry.tsv"
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v python3 >/dev/null || die 'falta python3'
  command -v curl >/dev/null || die 'falta curl'
  command -v sha256sum >/dev/null || die 'falta sha256sum'
  command -v sha512sum >/dev/null || die 'falta sha512sum'
  command -v tar >/dev/null || die 'falta tar'
  command -v unzip >/dev/null || die 'falta unzip'
  [[ -r "$SCRAPER" && -r "$REGISTRY" ]] || die 'faltan scraper o registro'
  if [[ "$ACTION" == check ]]; then check_installation; return; fi
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/build-runtime.XXXXXX")"
  trap 'rm -rf -- "$TEMP_DIR"' EXIT
  local metadata="${TEMP_DIR}/metadata.json"
  python3 "$SCRAPER" --tool "$TOOL" --version "$VERSION" >"$metadata"
  local resolved filename url checksum algorithm target archive topdir mise_path
  resolved="$(json_field "$metadata" version)"
  filename="$(json_field "$metadata" filename)"
  url="$(json_field "$metadata" download_url)"
  checksum="$(json_field "$metadata" checksum)"
  algorithm="$(json_field "$metadata" checksum_algorithm)"
  target="${RUNTIME_ROOT}/${TOOL}/${resolved}"
  echo "═══ $TOOL ═══"
  printf 'version=%s\narchivo=%s\nchecksum=%s\n' "$resolved" "$filename" "$checksum"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] descargar y verificar $url"
    info "[plan] instalar en $target"
    info "[plan] mise link --force $TOOL@$resolved y mise use --global $TOOL@$resolved"
    return
  fi
  find_mise >/dev/null || die 'mise no está instalado; ejecuta primero la etapa runtimes'
  mkdir -p "${RUNTIME_ROOT}/${TOOL}"
  local executable="gradle"
  [[ "$TOOL" == maven ]] && executable="mvn"
  if [[ ! -x "$target/bin/$executable" ]]; then
    archive="${TEMP_DIR}/${filename}"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 -o "$archive" "$url"
    if [[ "$algorithm" == sha256 ]]; then
      printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict -
    else
      printf '%s  %s\n' "$checksum" "$archive" | sha512sum --check --strict -
    fi
    if [[ "$TOOL" == maven ]]; then
      # Leer todo el listado evita SIGPIPE en tar cuando pipefail está activo.
      topdir="$(tar -tzf "$archive" | awk -F/ 'NF > 1 && first == "" { first=$1 } END { print first }')"
      tar -xzf "$archive" -C "$TEMP_DIR"
    else
      topdir="$(unzip -Z1 "$archive" | awk -F/ 'NF > 1 && first == "" { first=$1 } END { print first }')"
      unzip -q "$archive" -d "$TEMP_DIR"
    fi
    [[ -n "$topdir" ]] || die "archivo $TOOL vacío"
    if [[ -e "$target" || -L "$target" ]]; then
      mv -- "$target" "${target}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    mv -- "$TEMP_DIR/$topdir" "$target"
  fi
  mise_path="$(find_mise)"
  "$mise_path" link --force "$TOOL@${resolved}" "$target"
  "$mise_path" use --global "$TOOL@${resolved}"
  "$mise_path" reshim
  # shellcheck source=/dev/null
  source "$REGISTRY"
  runtime_registry_upsert "$TOOL" official "$resolved" "$target" "$checksum" "$(json_field "$metadata" source_url)"
  ln -sfn -- "$target" "${RUNTIME_ROOT}/current-${TOOL}"
  ok "$TOOL $resolved instalado manualmente e integrado en mise"
}

main "$@"
