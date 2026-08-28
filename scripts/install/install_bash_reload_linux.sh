#!/usr/bin/env bash
# shellcheck shell=bash
# Instala un comando para recargar Bash en la sesión actual.
set -Eeuo pipefail
umask 077

ACTION="check"
BASHRC="${BASHRC:-$HOME/.bashrc}"
RELOAD_BIN="${HOME}/.local/bin/reload-bash"

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
  install_bash_reload_linux.sh --check
  install_bash_reload_linux.sh --plan
  install_bash_reload_linux.sh --apply

Instala ~/.local/bin/reload-bash y una función reload-bash en ~/.bashrc.
Dentro de Bash, `reload-bash` vuelve a leer ~/.bashrc en la sesión actual.
Ejecutado como programa, reemplaza el proceso por un Bash login nuevo.
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

reload_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

sync_mise_java() {
  local mise_java_home stable_java_home current_java_home temporary_link
  command -v mise >/dev/null 2>&1 || return 0
  export MISE_ACTIVATE_AGGRESSIVE=1
  eval "$(mise activate bash)"
  eval "$(mise hook-env)"
  mise_java_home="$(mise where java 2>/dev/null || true)"
  if [[ -n "$mise_java_home" && -x "$mise_java_home/bin/java" ]]; then
    stable_java_home="$HOME/.local/share/java-runtimes/current-java"
    if [[ -e "$stable_java_home" && ! -L "$stable_java_home" ]]; then
      printf 'reload-bash: no se reemplaza %s porque no es un enlace simbólico\n' \
        "$stable_java_home" >&2
      return 1
    fi
    mkdir -p "$(dirname -- "$stable_java_home")"
    current_java_home="$(readlink -f -- "$stable_java_home" 2>/dev/null || true)"
    mise_java_home="$(readlink -f -- "$mise_java_home" 2>/dev/null || printf '%s' "$mise_java_home")"
    if [[ "$current_java_home" != "$mise_java_home" ]]; then
      temporary_link="${stable_java_home}.tmp.$$"
      rm -f -- "$temporary_link"
      ln -s -- "$mise_java_home" "$temporary_link"
      mv -Tf -- "$temporary_link" "$stable_java_home"
    fi
    export JAVA_HOME="$stable_java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
    hash -r
  fi
}

reload_bash() {
  local bashrc="${BASHRC:-$HOME/.bashrc}"
  [[ -r "$bashrc" ]] || return 0
  # shellcheck disable=SC1090
  source "$bashrc"
  # Actualiza JAVA_HOME y PATH en la shell que llamó a reload-bash.
  sync_mise_java
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  reload_bash
else
  exec bash -l
fi
EOF
}

bashrc_block() {
  cat <<'EOF'
# Recarga Bash en la sesión actual sin crear una shell anidada.
reload-bash() {
  source "$HOME/.local/bin/reload-bash"
}
EOF
}

mise_bashrc_block() {
  cat <<'EOF'
# JAVA_HOME estable; runtime-use actualiza el enlace current-java.
if command -v mise >/dev/null 2>&1; then
  export JAVA_HOME="$HOME/.local/share/java-runtimes/current-java"
fi
EOF
}

backup_path() {
  local target="$1" backup suffix=1 stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  [[ -e "$target" || -L "$target" ]] || return 0
  backup="${target}.bak.${stamp}"
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${target}.bak.${stamp}.${suffix}"
    suffix=$((suffix + 1))
  done
  cp -a -- "$target" "$backup"
  info "respaldo creado: $backup"
}

append_bashrc_block() {
  local begin='# BEGIN rafex reload-bash' end='# END rafex reload-bash' temporary
  if [[ -f "$BASHRC" ]] && grep -Fq "$begin" "$BASHRC"; then
    ok "bloque reload-bash ya presente en $BASHRC"
    return 0
  fi
  if [[ "$ACTION" == plan ]]; then
    info "[plan] agregar función reload-bash a $BASHRC"
    return 0
  fi
  mkdir -p "$(dirname "$BASHRC")"
  backup_path "$BASHRC"
  temporary="$(mktemp)"
  [[ -f "$BASHRC" ]] && cp -a -- "$BASHRC" "$temporary"
  printf '\n%s\n%s\n%s\n' "$begin" "$(bashrc_block)" "$end" >> "$temporary"
  mv -- "$temporary" "$BASHRC"
  chmod 600 "$BASHRC"
  ok "función reload-bash instalada en $BASHRC"
}

append_mise_block() {
  local begin='# BEGIN rafex reload-bash mise-java' end='# END rafex reload-bash mise-java'
  local legacy_export="export JAVA_HOME=\"\$_rafex_mise_java_home\""
  local temporary has_block=0 needs_replace=0
  if [[ -f "$BASHRC" ]] && grep -Fq "$begin" "$BASHRC"; then
    has_block=1
    if grep -Fq "$legacy_export" "$BASHRC"; then
      needs_replace=1
    else
      ok "bloque Java de mise ya presente en $BASHRC"
      return 0
    fi
  fi
  if [[ "$ACTION" == plan ]]; then
    if [[ "$needs_replace" -eq 1 ]]; then
      info "[plan] actualizar sincronización Java de mise en $BASHRC"
    else
      info "[plan] agregar sincronización Java de mise a $BASHRC"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$BASHRC")"
  backup_path "$BASHRC"
  temporary="$(mktemp)"
  if [[ "$has_block" -eq 1 ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      !inside { print }
    ' "$BASHRC" > "$temporary"
  elif [[ -f "$BASHRC" ]]; then
    cp -a -- "$BASHRC" "$temporary"
  fi
  printf '\n%s\n%s\n%s\n' "$begin" "$(mise_bashrc_block)" "$end" >> "$temporary"
  mv -- "$temporary" "$BASHRC"
  chmod 600 "$BASHRC"
  ok "sincronización Java de mise instalada en $BASHRC"
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die "este instalador requiere Linux"
  echo '═══ Recarga de Bash ═══'
  if [[ "$ACTION" == check ]]; then
    if [[ -x "$RELOAD_BIN" ]]; then
      ok "$RELOAD_BIN disponible"
    else
      warn "$RELOAD_BIN ausente"
    fi
    if grep -Fq '# BEGIN rafex reload-bash' "$BASHRC" 2>/dev/null; then
      ok "bloque presente en $BASHRC"
    else
      warn "bloque ausente en $BASHRC"
    fi
    return 0
  fi
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $RELOAD_BIN"
    append_bashrc_block
    append_mise_block
    return 0
  fi
  mkdir -p "$(dirname "$RELOAD_BIN")"
  backup_path "$RELOAD_BIN"
  reload_script > "$RELOAD_BIN"
  chmod 700 "$RELOAD_BIN"
  ok "comando instalado: $RELOAD_BIN"
  append_bashrc_block
  append_mise_block
  info "abre una nueva shell o ejecuta: reload-bash"
}

main "$@"
