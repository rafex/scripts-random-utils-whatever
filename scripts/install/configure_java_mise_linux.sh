#!/usr/bin/env bash
# shellcheck shell=bash
# Registra un JDK Temurin local en mise usando su ruta directa.
set -Eeuo pipefail
umask 077

ACTION="check"
PROVIDER="temurin"
VERSION="25"
RUNTIME_ROOT="${HOME}/.local/share/java-runtimes"
RUNTIME_PATH=""
MISE_BIN="${HOME}/.local/bin/mise"
MISE_CONFIG="${HOME}/.config/mise/config.toml"
STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_java_mise_linux.sh --check
  configure_java_mise_linux.sh --plan --version 25
  configure_java_mise_linux.sh --apply --version 25

Opciones:
  --check                  Mostrar estado sin modificar archivos (default)
  --plan | --dry-run      Mostrar cambios previstos sin modificar
  --apply                  Enlazar el JDK y seleccionarlo globalmente en mise
  --provider temurin       Proveedor soportado (default: temurin)
  --version VERSION       Versión mayor que se expondrá como temurin-VERSION
  --path DIRECTORIO       Ruta exacta del JDK instalado; evita usar current
  --help                   Mostrar esta ayuda

La configuración apunta directamente al directorio versionado del JDK; no
usa ~/.local/share/java-runtimes/current-temurin-jdk.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --provider)
        (($# >= 2)) || die "falta valor para --provider"
        PROVIDER="$2"
        shift
        ;;
      --version)
        (($# >= 2)) || die "falta valor para --version"
        VERSION="$2"
        shift
        ;;
      --path)
        (($# >= 2)) || die "falta valor para --path"
        RUNTIME_PATH="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$PROVIDER" == temurin ]] || die "solo se admite --provider temurin"
  [[ "$VERSION" =~ ^[0-9]+$ ]] || die "--version debe ser un número mayor, por ejemplo 25"
  if [[ -n "$RUNTIME_PATH" ]]; then
    [[ "$RUNTIME_PATH" == /* && "$RUNTIME_PATH" != *..* ]] || die "--path debe ser absoluta y no contener .."
  fi
}

find_mise() {
  if [[ -x "$MISE_BIN" ]]; then
    printf '%s\n' "$MISE_BIN"
  elif command -v mise >/dev/null 2>&1; then
    command -v mise
  else
    return 1
  fi
}

resolve_runtime_path() {
  local candidate
  if [[ -n "$RUNTIME_PATH" ]]; then
    printf '%s\n' "$RUNTIME_PATH"
    return 0
  fi
  candidate="$(find "$RUNTIME_ROOT/$PROVIDER" -mindepth 1 -maxdepth 1 -type d \
    -name "jdk-${VERSION}*-jdk" -print 2>/dev/null | sort -V | tail -n 1)"
  [[ -n "$candidate" ]] || die "no se encontró Temurin JDK $VERSION en $RUNTIME_ROOT/$PROVIDER"
  printf '%s\n' "$candidate"
}

backup_config() {
  local backup="${MISE_CONFIG}.bak.${STAMP}" suffix=1
  [[ -e "$MISE_CONFIG" || -L "$MISE_CONFIG" ]] || return 0
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${MISE_CONFIG}.bak.${STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  cp -a -- "$MISE_CONFIG" "$backup"
  info "respaldo creado: $backup"
}

check_mode() {
  local mise_path runtime_path
  echo '═══ Java Temurin y mise ═══'
  printf 'version=%s\n' "$VERSION"
  if runtime_path="$(resolve_runtime_path 2>/dev/null)"; then
    printf 'runtime=%s\n' "$runtime_path"
    if [[ -x "$runtime_path/bin/java" ]]; then
      "$runtime_path/bin/java" -version 2>&1 | head -n 1
    else
      warn "falta $runtime_path/bin/java"
    fi
  else
    printf 'runtime=missing\n'
  fi
  if mise_path="$(find_mise 2>/dev/null)"; then
    printf 'mise=%s\n' "$mise_path"
    "$mise_path" current java 2>&1 || true
  else
    printf 'mise=missing\n'
  fi
}

plan_mode() {
  local runtime_path
  runtime_path="$(resolve_runtime_path 2>/dev/null || printf '%s' "${RUNTIME_ROOT}/${PROVIDER}/jdk-${VERSION}*-jdk")"
  echo '═══ Plan Java Temurin y mise ═══'
  info "[plan] localizar el JDK versionado: $runtime_path"
  info "[plan] mise link --force java@temurin-${VERSION} $runtime_path"
  info "[plan] respaldar $MISE_CONFIG si existe"
  info "[plan] mise use --global java@temurin-${VERSION}"
  info "[plan] mise reshim"
}

apply_mode() {
  local mise_path runtime_path
  mise_path="$(find_mise)" || die "mise no está instalado; ejecuta primero install-terminal-workstation --stage runtimes"
  runtime_path="$(resolve_runtime_path)"
  [[ -d "$runtime_path" && -x "$runtime_path/bin/java" ]] || die "JDK inválido o inexistente: $runtime_path"
  backup_config
  mkdir -p "$(dirname "$MISE_CONFIG")"
  "$mise_path" link --force "java@temurin-${VERSION}" "$runtime_path"
  "$mise_path" use --global "java@temurin-${VERSION}"
  "$mise_path" reshim
  ok "mise usa directamente: $runtime_path"
  "$runtime_path/bin/java" -version 2>&1 | head -n 1
  "$mise_path" current java || true
}

main() {
  parse_args "$@"
  case "$ACTION" in
    check) check_mode ;;
    plan) plan_mode ;;
    apply) apply_mode ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
