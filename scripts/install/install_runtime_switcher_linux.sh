#!/usr/bin/env bash
# shellcheck shell=bash
# Instala runtime-use y mantiene JAVA_HOME en un enlace estable.
set -Eeuo pipefail
umask 077

ACTION="check"
BASHRC="${BASHRC:-$HOME/.bashrc}"
PROFILE="${PROFILE:-$HOME/.profile}"
JAVA_HOME_LINK="${HOME}/.local/share/java-runtimes/current-java"
JAVA_SELECTION_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/runtime-java-selection"
BEGIN_MARKER="# BEGIN rafex runtime-switcher"
END_MARKER="# END rafex runtime-switcher"
STAMP="$(date +%Y%m%d_%H%M%S)"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:${PATH:-}"

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
_rafex_runtime_java_selection="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/runtime-java-selection"
_rafex_runtime_registry="${XDG_DATA_HOME:-$HOME/.local/share}/rafex-runtimes/registry.tsv"

_rafex_runtime_local_java_tool() {
  local directory="$PWD" candidate
  while [[ "$directory" != "/" && "$directory" != "." ]]; do
    candidate="$directory/.mise.toml"
    if [[ -r "$candidate" ]] && grep -Eq '^[[:space:]]*(java|graalvm)[[:space:]]*=' "$candidate"; then
      awk -F '=' '/^[[:space:]]*(java|graalvm)[[:space:]]*=/ {
        gsub(/[[:space:]]/, "", $1); print $1; exit
      }' "$candidate"
      return 0
    fi
    directory="$(dirname -- "$directory")"
  done
  return 1
}

_rafex_runtime_sync_java_home() {
  local selection local_tool resolved canonical current temporary
  command -v mise >/dev/null 2>&1 || return 0
  local_tool="$(_rafex_runtime_local_java_tool || true)"
  selection=""
  if [[ -r "$_rafex_runtime_java_selection" ]]; then
    selection="$(awk 'NF { print; exit }' "$_rafex_runtime_java_selection")"
  fi
  if [[ -n "$local_tool" ]]; then
    resolved="$(mise where "$local_tool" 2>/dev/null | awk 'NF { print; exit }' || true)"
  elif [[ -n "$selection" ]]; then
    resolved="$(mise where "$selection" 2>/dev/null | awk 'NF { print; exit }' || true)"
  else
    resolved="$(mise where java 2>/dev/null | awk 'NF { print; exit }' || true)"
  fi
  [[ -n "$resolved" && -x "$resolved/bin/java" ]] || return 0
  canonical="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
  [[ "$canonical" == "$HOME/.local/share/java-runtimes/"* ]] || return 0
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

_rafex_runtime_sync_node_link() {
  local resolved canonical current temporary link="${HOME}/.local/share/node-runtimes/current-node"
  command -v mise >/dev/null 2>&1 || return 0
  resolved="$(mise where node 2>/dev/null | awk 'NF { print; exit }' || true)"
  [[ -n "$resolved" && -x "$resolved/bin/node" ]] || return 0
  canonical="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
  [[ "$canonical" == "$HOME/.local/share/node-runtimes/"* ]] || return 0
  if [[ -e "$link" && ! -L "$link" ]]; then
    printf 'runtime-use: no se reemplaza %s porque no es un enlace simbólico\n' "$link" >&2
    return 1
  fi
  current="$(readlink -f -- "$link" 2>/dev/null || true)"
  if [[ "$current" != "$canonical" ]]; then
    mkdir -p "$(dirname -- "$link")"
    temporary="${link}.tmp.$$"
    rm -f -- "$temporary"
    ln -s -- "$canonical" "$temporary"
    mv -Tf -- "$temporary" "$link"
  fi
}

_rafex_runtime_set_java_selection() {
  local selection="$1" temporary
  mkdir -p "$(dirname -- "$_rafex_runtime_java_selection")"
  temporary="${_rafex_runtime_java_selection}.tmp.$$"
  printf '%s\n' "$selection" > "$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$_rafex_runtime_java_selection"
}

_rafex_runtime_list_java() {
  if [[ -s "$_rafex_runtime_registry" ]]; then
    awk -F '\t' '$1 == "java" {
      provider=$2
      if (provider ~ /^graalvm-/) provider="graalvm"
      printf "java  %s-%s  %s\n", provider, $3, $4
    }' "$_rafex_runtime_registry"
  else
    mise ls --installed java
    mise ls --installed graalvm 2>/dev/null | awk 'NF { $1="java"; $2="graalvm-" $2; print }'
  fi
}

_rafex_runtime_registry_path() {
  local tool="$1" version="$2" provider registry_version
  [[ -s "$_rafex_runtime_registry" ]] || return 1
  provider=""; registry_version=""
  case "$tool" in
    java)
      case "$version" in
        temurin-*) provider="temurin"; registry_version="$version" ;;
        semeru-*) provider="semeru"; registry_version="$version" ;;
        graalvm-*) provider="graalvm-community"; registry_version="${version#graalvm-}" ;;
        *) return 1 ;;
      esac
      ;;
    node)
      provider="nodejs"; registry_version="$version" ;;
    *) return 1 ;;
  esac
  awk -F '\t' -v tool="$tool" -v provider="$provider" -v version="$registry_version" \
    '$1 == tool && $2 == provider && $3 == version { print $4; exit }' "$_rafex_runtime_registry"
}

_rafex_runtime_list_node() {
  if [[ -s "$_rafex_runtime_registry" ]] && grep -q $'^node\t' "$_rafex_runtime_registry"; then
    awk -F '\t' '$1 == "node" { printf "node  %s  %s\n", $3, $4 }' "$_rafex_runtime_registry"
  else
    mise ls --installed node
  fi
}

_rafex_runtime_missing_hint() {
  local tool="$1" version="$2"
  if [[ "$tool" == java && "$version" == graalvm-* ]]; then
    printf 'just install-java-runtime --provider graalvm-community --version %s --apply\n' "${version#graalvm-}"
  elif [[ "$tool" == java && "$version" == semeru-* ]]; then
    printf 'just install-java-runtime --provider semeru --version %s --image jdk --apply\n' "${version#semeru-}"
  elif [[ "$tool" == java ]]; then
    printf 'just install-java-runtime --provider temurin --version %s --image jdk --apply\n' "${version#temurin-}"
  else
    printf 'just install-node-runtime --version %s --apply\n' "$version"
  fi
}

_rafex_runtime_prompt_sync() {
  _rafex_runtime_sync_java_home || true
}

runtime-use() {
  local scope="global" action="${1:-}" tool version identifier
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
      if [[ $# -ge 2 && "$2" == java ]]; then
        _rafex_runtime_list_java
      elif [[ $# -ge 2 && "$2" == node ]]; then
        _rafex_runtime_list_node
      elif [[ $# -ge 2 ]]; then
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
  if [[ "$tool" == java && "$version" == graalvm-* ]]; then
    identifier="graalvm@${version#graalvm-}"
  else
    identifier="${tool}@${version}"
  fi
  if ! mise where "$identifier" >/dev/null 2>&1; then
    printf '%s no está instalado. Usa el instalador del repositorio:\n' "$identifier" >&2
    _rafex_runtime_missing_hint "$tool" "$version" >&2
    return 1
  fi
  if [[ -s "$_rafex_runtime_registry" ]]; then
    local registered_path resolved_path
    registered_path="$(_rafex_runtime_registry_path "$tool" "$version" || true)"
    resolved_path="$(mise where "$identifier" 2>/dev/null | awk 'NF { print; exit }' || true)"
    if [[ -z "$registered_path" || "$(readlink -f -- "$resolved_path" 2>/dev/null || printf '%s' "$resolved_path")" != "$(readlink -f -- "$registered_path" 2>/dev/null || printf '%s' "$registered_path")" ]]; then
      printf '%s no está registrado por los instaladores propios. Usa:\n' "$identifier" >&2
      _rafex_runtime_missing_hint "$tool" "$version" >&2
      return 1
    fi
  fi
  if [[ "$scope" == local ]]; then
    # mise usa el archivo local del proyecto por defecto.
    mise use "$identifier" || return
  else
    mise use --global "$identifier" || return
  fi
  eval "$(mise hook-env)"
  if [[ "$tool" == java ]]; then
    _rafex_runtime_set_java_selection "$identifier"
  else
    _rafex_runtime_sync_node_link || return
  fi
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

profile_block() {
  cat <<'EOF'
# Mantiene disponibles los shims de mise y JAVA_HOME en shells de login.
_rafex_mise_shims="${HOME}/.local/share/mise/shims"
_rafex_java_home="${HOME}/.local/share/java-runtimes/current-java"
if [ -d "$_rafex_mise_shims" ]; then
  case ":${PATH:-}:" in
    *:"$_rafex_mise_shims":*) ;;
    *) PATH="$_rafex_mise_shims${PATH:+:$PATH}" ;;
  esac
fi
if [ -e "$_rafex_java_home" ] || [ -L "$_rafex_java_home" ]; then
  JAVA_HOME="$_rafex_java_home"
fi
export PATH
export JAVA_HOME
unset _rafex_mise_shims _rafex_java_home
EOF
}

validate_selector_block() {
  local temporary
  temporary="$(mktemp)"
  selector_block > "$temporary"
  if ! bash -n "$temporary"; then
    rm -f -- "$temporary"
    die 'el bloque runtime-use generado no tiene sintaxis Bash válida'
  fi
  rm -f -- "$temporary"
}

check_markers() {
  local begin_count end_count
  begin_count="$(grep -Fxc "$BEGIN_MARKER" "$BASHRC" 2>/dev/null || true)"
  end_count="$(grep -Fxc "$END_MARKER" "$BASHRC" 2>/dev/null || true)"
  [[ "$begin_count" == "$end_count" ]] || die "$BASHRC contiene un bloque runtime-switcher incompleto"
  [[ "$begin_count" -le 1 ]] || die "$BASHRC contiene bloques runtime-switcher duplicados"
}

check_profile_markers() {
  local begin_count end_count
  begin_count="$(grep -Fxc '# BEGIN rafex runtime-switcher profile' "$PROFILE" 2>/dev/null || true)"
  end_count="$(grep -Fxc '# END rafex runtime-switcher profile' "$PROFILE" 2>/dev/null || true)"
  [[ "$begin_count" == "$end_count" ]] || die "$PROFILE contiene un bloque runtime-switcher profile incompleto"
  [[ "$begin_count" -le 1 ]] || die "$PROFILE contiene bloques runtime-switcher profile duplicados"
}

show_status() {
  local shell_context
  echo '═══ Selector de runtimes Bash ═══'
  printf 'bashrc=%s\n' "$BASHRC"
  printf 'profile=%s\n' "$PROFILE"
  printf 'java_home_link=%s\n' "$JAVA_HOME_LINK"
  printf 'JAVA_HOME=%s\n' "${JAVA_HOME:-ausente}"
  if [[ $- == *i* ]]; then
    shell_context='interactiva'
  elif [[ -n "${SSH_CONNECTION:-}" ]]; then
    shell_context='SSH no interactiva'
  else
    shell_context='no interactiva'
  fi
  printf 'shell_context=%s\n' "$shell_context"
  if [[ $- != *i* && -z "${JAVA_HOME:-}" ]]; then
    info 'esta comprobación no hereda .bashrc; JAVA_HOME se aplicará al abrir una shell interactiva o usar reload-bash'
  fi
  if [[ -f "$BASHRC" ]] && grep -Fq "$BEGIN_MARKER" "$BASHRC"; then
    ok "bloque runtime-use presente"
  else
    warn "bloque runtime-use ausente"
  fi
  if [[ -f "$PROFILE" ]] && grep -Fq '# BEGIN rafex runtime-switcher profile' "$PROFILE"; then
    ok "bloque de login presente en $PROFILE"
  else
    warn "bloque de login ausente en $PROFILE"
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

backup_file() {
  local target="$1" backup suffix=1
  [[ -e "$target" || -L "$target" ]] || return 0
  backup="${target}.bak.${STAMP}"
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${target}.bak.${STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  cp -a -- "$target" "$backup"
  info "respaldo creado: $backup"
}

sync_java_link() {
  local selection resolved canonical current temporary
  command -v mise >/dev/null 2>&1 || return 0
  selection=""
  if [[ -r "$JAVA_SELECTION_FILE" ]]; then
    selection="$(awk 'NF { print; exit }' "$JAVA_SELECTION_FILE")"
  fi
  if [[ -n "$selection" ]]; then
    resolved="$(mise where "$selection" 2>/dev/null | awk 'NF { print; exit }' || true)"
  else
    resolved="$(mise where java 2>/dev/null | awk 'NF { print; exit }' || true)"
  fi
  [[ -n "$resolved" && -x "$resolved/bin/java" ]] || return 0
  canonical="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
  [[ "$canonical" == "$HOME/.local/share/java-runtimes/"* ]] || {
    warn "no se adopta un Java fuera de ~/.local/share/java-runtimes"
    return 0
  }
  if [[ -e "$JAVA_HOME_LINK" && ! -L "$JAVA_HOME_LINK" ]]; then
    die "$JAVA_HOME_LINK existe pero no es un enlace simbólico"
  fi
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

write_profile() {
  local begin='# BEGIN rafex runtime-switcher profile'
  local end='# END rafex runtime-switcher profile'
  local temporary current expected
  check_profile_markers
  expected="$(profile_block)"
  if [[ -f "$PROFILE" ]]; then
    current="$(awk -v begin="$begin" -v end="$end" '
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      inside { print }
    ' "$PROFILE")"
    if grep -Fq "$begin" "$PROFILE" && [[ "$current" == "$expected" ]]; then
      ok "bloque de login ya está actualizado en $PROFILE"
      return 0
    fi
  fi
  backup_file "$PROFILE"
  temporary="$(mktemp)"
  if [[ -f "$PROFILE" ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      !inside { print }
    ' "$PROFILE" > "$temporary"
    chmod --reference="$PROFILE" "$temporary"
  else
    chmod 600 "$temporary"
  fi
  printf '\n%s\n%s\n%s\n' "$begin" "$expected" "$end" >> "$temporary"
  mkdir -p "$(dirname "$PROFILE")"
  mv -- "$temporary" "$PROFILE"
  ok "bloque de login instalado en $PROFILE"
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  validate_selector_block
  case "$ACTION" in
    check)
      show_status
      ;;
    plan)
      show_status
      info "[plan] respaldar y actualizar el bloque runtime-use en $BASHRC"
      info "[plan] respaldar y actualizar el entorno de login en $PROFILE"
      info "[plan] usar $JAVA_HOME_LINK como JAVA_HOME estable"
      info "[plan] sincronizar current-java con el Java seleccionado en mise"
      info "[plan] guardar la selección Java en $JAVA_SELECTION_FILE"
      ;;
    apply)
      write_bashrc
      write_profile
      sync_java_link
      ok "runtime-use listo; abre una nueva shell o ejecuta: source $BASHRC"
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
