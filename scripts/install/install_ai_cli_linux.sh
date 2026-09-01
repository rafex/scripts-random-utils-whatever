#!/usr/bin/env bash
# v1.0.0 - Instala Codex CLI y Claude Code con un prefijo npm del usuario.
set -Eeuo pipefail
umask 077

NPM_PREFIX="${HOME}/.local/share/npm-global"
USER_BIN="${HOME}/.local/bin"
export PATH="${USER_BIN}:${NPM_PREFIX}/bin:${HOME}/.local/share/node-runtimes/current-node/bin:${PATH:-}"

ACTION="check"
NPM_COMMAND=""
NODE_COMMAND=""

CLI_PACKAGES=(
  '@openai/codex'
  '@anthropic-ai/claude-code'
)
CLI_COMMANDS=(codex claude)

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso:
  install_ai_cli_linux.sh --check
  install_ai_cli_linux.sh --plan
  install_ai_cli_linux.sh --apply
  install_ai_cli_linux.sh --status

Instala Codex CLI y Claude Code con npm como usuario normal. No inicia sesión,
no recibe tokens y no ejecuta los comandos de autenticación.
EOF
}

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

find_node() {
  local candidate node_dir
  if candidate="$(command -v node 2>/dev/null)"; then
    NODE_COMMAND="$candidate"
    return 0
  fi
  for candidate in \
    "${HOME}/.local/share/node-runtimes/current-node/bin/node" \
    "${HOME}/.local/share/mise/shims/node" \
    "${HOME}/.local/bin/node"; do
    if [[ -x "$candidate" ]]; then
      NODE_COMMAND="$candidate"
      node_dir="$(dirname -- "$candidate")"
      export PATH="${node_dir}:${PATH}"
      return 0
    fi
  done
  return 1
}

find_npm() {
  local candidate
  if candidate="$(command -v npm 2>/dev/null)"; then
    NPM_COMMAND="$candidate"
    return 0
  fi
  for candidate in \
    "${HOME}/.local/share/node-runtimes/current-node/bin/npm" \
    "${HOME}/.local/share/mise/shims/npm" \
    "${HOME}/.local/bin/npm"; do
    if [[ -x "$candidate" ]]; then
      NPM_COMMAND="$candidate"
      return 0
    fi
  done
  return 1
}

require_node_npm() {
  find_node || die 'no se encontró Node.js; instala primero el runtime Node propio'
  find_npm || die 'no se encontró npm junto al runtime Node activo'
  "$NODE_COMMAND" --version >/dev/null \
    || die 'el binario Node.js no puede ejecutarse'
  "$NPM_COMMAND" --version >/dev/null \
    || die 'el binario npm no puede ejecutarse'
}

cli_path() {
  local command_name="$1"
  if [[ -x "${NPM_PREFIX}/bin/${command_name}" ]]; then
    printf '%s\n' "${NPM_PREFIX}/bin/${command_name}"
  elif command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
  else
    return 1
  fi
}

show_cli_status() {
  local command_name path version
  for command_name in "${CLI_COMMANDS[@]}"; do
    if path="$(cli_path "$command_name" 2>/dev/null)"; then
    version="$("$path" --version 2>/dev/null || true)"
      printf '✓ %s: %s%s\n' "$command_name" "$path" \
        "${version:+ (${version//$'\n'/ })}"
    else
      warn "$command_name no está instalado"
    fi
  done
}

show_status() {
  printf '═══ CLIs de IA locales ═══\n'
  printf 'prefijo npm=%s\n' "$NPM_PREFIX"
  if find_node; then
    printf 'node=%s\n' "$NODE_COMMAND"
    "$NODE_COMMAND" --version 2>/dev/null || true
  else
    warn 'Node.js no está disponible en esta shell'
  fi
  if find_npm; then
    printf 'npm=%s\n' "$NPM_COMMAND"
    "$NPM_COMMAND" --version 2>/dev/null || true
  else
    warn 'npm no está disponible en esta shell'
  fi
  show_cli_status
  info 'la autenticación se realiza aparte con codex --login o claude'
}

show_plan() {
  require_node_npm
  printf '═══ Plan CLIs de IA ═══\n'
  info "usar npm sin sudo con prefijo $NPM_PREFIX"
  info 'instalar @openai/codex y @anthropic-ai/claude-code desde npm'
  info "crear enlaces de codex y claude en $USER_BIN"
  info 'no iniciar autenticación ni guardar tokens'
  info 'no se escribirá nada en modo plan'
}

install_link() {
  local command_name="$1"
  local source="${NPM_PREFIX}/bin/${command_name}"
  local target="${USER_BIN}/${command_name}"
  [[ -x "$source" ]] || die "npm no creó el comando $command_name"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" && "$(readlink -f -- "$target" 2>/dev/null || true)" == \
      "$(readlink -f -- "$source" 2>/dev/null || true)" ]]; then
      ok "$command_name ya está enlazado en $target"
    else
      die "$target ya existe y no pertenece a este instalador; no se sobrescribe"
    fi
    return
  fi
  ln -s -- "$source" "$target"
  ok "comando disponible: $target"
}

apply_installation() {
  require_node_npm
  mkdir -p -- "$NPM_PREFIX" "$USER_BIN"
  info "instalando CLIs con npm en $NPM_PREFIX"
  NPM_CONFIG_PREFIX="$NPM_PREFIX" \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    "$NPM_COMMAND" install --global --no-audit --no-fund "${CLI_PACKAGES[@]}"
  install_link codex
  install_link claude
  ok 'Codex CLI y Claude Code instalados sin sudo'
  info 'autenticación manual pendiente: codex --login / claude'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux_debian
  case "$ACTION" in
    check)
      printf '═══ Check CLIs de IA ═══\n'
      require_node_npm
      show_cli_status
      ;;
    plan) show_plan ;;
    apply) apply_installation ;;
    status) show_status ;;
  esac
}

main "$@"
