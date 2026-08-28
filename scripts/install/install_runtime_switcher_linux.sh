#!/usr/bin/env bash
# shellcheck shell=bash
# Instala runtime-use y mantiene JAVA_HOME en un enlace estable.
set -Eeuo pipefail
umask 077

ACTION="check"
BASHRC="${BASHRC:-$HOME/.bashrc}"
JAVA_HOME_LINK="${HOME}/.local/share/java-runtimes/current-java"
BEGIN_MARKER="# BEGIN rafex runtime-switcher"
END_MARKER="# END rafex runtime-switcher"
STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_runtime_switcher_linux.sh --check
  install_runtime_switcher_linux.sh --plan | --dry-run
  install_runtime_switcher_linux.sh --apply

Instala la función Bash runtime-use y mantiene JAVA_HOME en:
  ~/.local/share/java-runtimes/current-java

Opciones:
  --check                 Mostrar estado sin modificar archivos (default)
  --plan | --dry-run     Mostrar cambios sin modificar archivos
  --apply                 Instalar o actualizar el bloque administrado
  --help | -h             Mostrar esta ayuda
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

selector_block() {
  cat <<'EOF'
# Mantiene JAVA_HOME estable y apunta el enlace al Java activo de mise.
_rafex_runtime_java_link="${HOME}/.local/share/java-runtimes/current-java"

_rafex_runtime_sync_java_home() {
  local resolved canonical current temporary
  command -v mise >/dev/null 2>&1 || return 0
  resolved="$(mise where java 2>/dev/null | awk 'NF { print; exit }' || true)"
  [[ -n "$resolved" && -x "$resolved/bin/java" ]] || return 0
  canonical="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
  if [[ -e "$_rafex_runtime_java_link" && ! -L "$_rafex_runtime_java_link" ]]; then
    printf 'runtime-use: no se reemplaza %s porque no es un enlace simbólico\n' \
      "$_rafex_runtime_java_link" >&2
    return 1
  fi
  current="$(readlink -f -- "$_rafex_runtime_java_link" 2>/dev/null || true)"
  if [[ "$current" != "$canonical" ]]; then
    mkdir -p "$(dirname -- "$_rafex_runtime_java_link")"
    temporary="${_rafex_runtime_java_link}.tmp.$$"
    rm -f -- "$temporary"
    ln -s -- "$canonical" "$temporary"
    mv -Tf -- "$temporary" "$_rafex_runtime_java_link"
  fi
  if [[ "${JAVA_HOME:-}" != "$_rafex_runtime_java_link" ]]; then
    export JAVA_HOME="$_rafex_runtime_java_link"
  fi
}

_rafex_runtime_prompt_sync() {
  _rafex_runtime_sync_java_home || true
}

runtime-use() {
  local scope="global" action="${1:-}" tool version identifier answer
  if [[ "$action" == "--local" || "$action" == "--global" ]]; then
    [[ $# -ge 2 ]] || { printf 'Uso: runtime-use [--local|--global] java|node versión\n' >&2; return 2; }
    scope="${action#--}"
    shift
    action="$1"
  fi

  if [[ "$action" == "--list" ]]; then
    action="list"
  fi

  case "$action" in
    list)
      command -v mise >/dev/null 2>&1 || { printf 'runtime-use: mise no está instalado\n' >&2; return 1; }
      if [[ $# -ge 2 ]]; then
        mise ls --installed "$2"
      else
        mise ls --installed
      fi
      return
      ;;
    current)
      command -v mise >/dev/null 2>&1 || { printf 'runtime-use: mise no está instalado\n' >&2; return 1; }
      if [[ $# -ge 2 ]]; then
        mise current "$2"
      else
        mise current
      fi
      printf 'JAVA_HOME=%s\n' "${JAVA_HOME:-ausente}"
      if [[ -L "$_rafex_runtime_java_link" ]]; then
        printf 'current-java=%s\n' "$(readlink -f -- "$_rafex_runtime_java_link" 2>/dev/null || readlink -- "$_rafex_runtime_java_link")"
      else
        printf 'current-java=ausente\n'
      fi
      return
      ;;
    java|node)
      tool="$action"
      version="${2:-}"
      ;;
    *)
      printf 'Uso: runtime-use [--local|--global] java|node versión\n' >&2
      printf '     runtime-use --list [java|node]\n' >&2
      printf '     runtime-use current [java|node]\n' >&2
      return 2
      ;;
  esac

  [[ -n "$version" ]] || { printf 'runtime-use: falta la versión\n' >&2; return 2; }
  command -v mise >/dev/null 2>&1 || { printf 'runtime-use: mise no está instalado\n' >&2; return 1; }
  if [[ "$tool" == java && "$version" =~ ^[0-9]+$ ]]; then
    version="temurin-${version}"
  fi
  identifier="${tool}@${version}"
  if ! mise where "$identifier" >/dev/null 2>&1; then
    printf '%s no está instalado. Ejecutar mise install %s? [y/N] ' \
      "$identifier" "$identifier" >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES) mise install "$identifier" || return ;;
      *) printf 'No se instaló %s\n' "$identifier" >&2; return 1 ;;
    esac
  fi
  if [[ "$scope" == local ]]; then
    # mise usa el archivo local del proyecto por defecto.
    mise use "$identifier" || return
  else
    mise use --global "$identifier" || return
  fi
  eval "$(mise hook-env)"
  _rafex_runtime_sync_java_home || return
  hash -r
  printf 'runtime activo: %s (%s)\n' "$identifier" "$scope"
  if [[ "$tool" == java ]]; then
    printf 'JAVA_HOME=%s -> %s\n' "$JAVA_HOME" "$(readlink -f -- "$JAVA_HOME" 2>/dev/null || readlink -- "$JAVA_HOME")"
  fi
}

if [[ $- == *i* ]]; then
  if [[ ! -e "$_rafex_runtime_java_link" || -L "$_rafex_runtime_java_link" ]]; then
    export JAVA_HOME="$_rafex_runtime_java_link"
  fi
  _rafex_runtime_sync_java_home || true
  if declare -p PROMPT_COMMAND 2>/dev/null | grep -Fq 'declare -a'; then
    case " ${PROMPT_COMMAND[*]} " in
      *" _rafex_runtime_prompt_sync "*) ;;
      *) PROMPT_COMMAND=("_rafex_runtime_prompt_sync" "${PROMPT_COMMAND[@]}") ;;
    esac
  else
    case ";${PROMPT_COMMAND:-};" in
      *";_rafex_runtime_prompt_sync;"*) ;;
      *) PROMPT_COMMAND="_rafex_runtime_prompt_sync${PROMPT_COMMAND:+;${PROMPT_COMMAND}}" ;;
    esac
  fi
fi
EOF
}

check_markers() {
  local begin_count end_count
  begin_count="$(grep -Fxc "$BEGIN_MARKER" "$BASHRC" 2>/dev/null || true)"
  end_count="$(grep -Fxc "$END_MARKER" "$BASHRC" 2>/dev/null || true)"
  [[ "$begin_count" == "$end_count" ]] || die "$BASHRC contiene un bloque runtime-switcher incompleto"
  [[ "$begin_count" -le 1 ]] || die "$BASHRC contiene bloques runtime-switcher duplicados"
}

show_status() {
  echo '═══ Selector de runtimes Bash ═══'
  printf 'bashrc=%s\n' "$BASHRC"
  printf 'java_home_link=%s\n' "$JAVA_HOME_LINK"
  printf 'JAVA_HOME=%s\n' "${JAVA_HOME:-ausente}"
  if [[ -f "$BASHRC" ]] && grep -Fq "$BEGIN_MARKER" "$BASHRC"; then
    ok "bloque runtime-use presente"
  else
    warn "bloque runtime-use ausente"
  fi
  if [[ -L "$JAVA_HOME_LINK" ]]; then
    ok "enlace current-java: $(readlink -f -- "$JAVA_HOME_LINK" 2>/dev/null || readlink -- "$JAVA_HOME_LINK")"
  elif [[ -e "$JAVA_HOME_LINK" ]]; then
    warn "$JAVA_HOME_LINK existe pero no es un enlace simbólico"
  else
    warn "enlace current-java ausente"
  fi
  if command -v mise >/dev/null 2>&1; then
    mise current java 2>&1 || true
    mise current node 2>&1 || true
  else
    printf 'mise=missing\n'
  fi
}

backup_bashrc() {
  local backup="${BASHRC}.bak.${STAMP}" suffix=1
  [[ -e "$BASHRC" || -L "$BASHRC" ]] || return 0
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${BASHRC}.bak.${STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  cp -a -- "$BASHRC" "$backup"
  info "respaldo creado: $backup"
}

sync_java_link() {
  local resolved canonical current temporary
  command -v mise >/dev/null 2>&1 || return 0
  resolved="$(mise where java 2>/dev/null | awk 'NF { print; exit }' || true)"
  [[ -n "$resolved" && -x "$resolved/bin/java" ]] || return 0
  if [[ -e "$JAVA_HOME_LINK" && ! -L "$JAVA_HOME_LINK" ]]; then
    die "$JAVA_HOME_LINK existe pero no es un enlace simbólico"
  fi
  canonical="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
  current="$(readlink -f -- "$JAVA_HOME_LINK" 2>/dev/null || true)"
  if [[ "$current" != "$canonical" ]]; then
    mkdir -p "$(dirname -- "$JAVA_HOME_LINK")"
    temporary="${JAVA_HOME_LINK}.tmp.$$"
    rm -f -- "$temporary"
    ln -s -- "$canonical" "$temporary"
    mv -Tf -- "$temporary" "$JAVA_HOME_LINK"
    info "current-java actualizado: $canonical"
  fi
}

write_bashrc() {
  local temporary current expected
  check_markers
  expected="$(selector_block)"
  if [[ -f "$BASHRC" ]]; then
    current="$(awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      inside { print }
    ' "$BASHRC")"
    if grep -Fq "$BEGIN_MARKER" "$BASHRC" && [[ "$current" == "$expected" ]]; then
      ok "bloque runtime-use ya está actualizado"
      return 0
    fi
  fi
  backup_bashrc
  temporary="$(mktemp)"
  if [[ -f "$BASHRC" ]]; then
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      !inside { print }
    ' "$BASHRC" > "$temporary"
  fi
  printf '\n%s\n%s\n%s\n' "$BEGIN_MARKER" "$expected" "$END_MARKER" >> "$temporary"
  mkdir -p "$(dirname -- "$BASHRC")"
  chmod 600 "$temporary"
  mv -- "$temporary" "$BASHRC"
  ok "bloque runtime-use instalado en $BASHRC"
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  case "$ACTION" in
    check)
      show_status
      ;;
    plan)
      show_status
      info "[plan] respaldar y actualizar el bloque runtime-use en $BASHRC"
      info "[plan] usar $JAVA_HOME_LINK como JAVA_HOME estable"
      info "[plan] sincronizar current-java con mise where java"
      ;;
    apply)
      write_bashrc
      sync_java_link
      ok "runtime-use listo; abre una nueva shell o ejecuta: source $BASHRC"
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
