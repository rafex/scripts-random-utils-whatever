#!/usr/bin/env bash
# shellcheck shell=bash
#
# Instala Mosh/tmux en Debian y Mosh/tmux/Kitty en macOS.
# Configura el portapapeles OSC 52 sin aceptar ni almacenar contraseñas.
set -Eeuo pipefail
umask 077

ACTION="check"
OS_TYPE="$(uname -s)"
TMUX_CONFIG="${TMUX_CONFIG:-$HOME/.tmux.conf}"
KITTY_CONFIG_DIR="${KITTY_CONFIG_DIRECTORY:-$HOME/.config/kitty}"
KITTY_CONFIG="$KITTY_CONFIG_DIR/kitty.conf"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

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
  install_mosh_tmux_kitty_unix.sh --check
  install_mosh_tmux_kitty_unix.sh --plan
  install_mosh_tmux_kitty_unix.sh --apply

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Instalar paquetes y configurar archivos
  -h, --help             Mostrar esta ayuda

En Debian instala Mosh, tmux y la definición terminfo de Kitty para permitir
sesiones remotas con `TERM=xterm-kitty`. En macOS instala Mosh, tmux y Kitty
mediante Homebrew. La contraseña de sudo, cuando sea necesaria, se solicita
solamente mediante `sudo -v`.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_supported_os() {
  case "$OS_TYPE" in
    Linux|Darwin) ;;
    *) die "sistema operativo no soportado: $OS_TYPE" ;;
  esac
  [[ "$EUID" -ne 0 ]] || die "ejecuta el script como el usuario normal, no como root"
}

backup_file() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  cp -a "$file" "${file}.bak.${BACKUP_STAMP}"
  info "respaldo creado: ${file}.bak.${BACKUP_STAMP}"
}

append_managed_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local block="$4"
  local temporary

  if [[ -f "$file" ]] && grep -Fq "$begin" "$file"; then
    ok "configuración ya presente: $file"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] agregar configuración a $file"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  backup_file "$file"
  temporary="$(mktemp)"
  if [[ -f "$file" ]]; then
    cp -p "$file" "$temporary"
  fi
  printf '\n%s\n%s\n%s\n' "$begin" "$block" "$end" >> "$temporary"
  mv "$temporary" "$file"
  chmod 600 "$file"
  ok "configuración instalada: $file"
}

tmux_block() {
  cat <<'EOF'
# Copiar selección de tmux al portapapeles del terminal mediante OSC 52.
set -ag terminal-features ",xterm-kitty:RGB"
set -ga terminal-overrides ",xterm-kitty:Tc"
set -g set-clipboard on
set -g history-limit 100000
set -g mouse on
setw -g mode-keys vi
bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
bind-key -T copy-mode y send-keys -X copy-selection-and-cancel
EOF
}

kitty_block() {
  cat <<'EOF'
# Permitir que programas remotos escriban al portapapeles mediante OSC 52.
# Las lecturas solicitan confirmación para no exponer el portapapeles.
clipboard_control write-clipboard write-primary read-clipboard-ask read-primary-ask
EOF
}

install_debian() {
  command -v sudo >/dev/null 2>&1 || \
    die "sudo no está instalado; ejecuta configure_sudo_linux.sh como root primero"
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] sudo -v"
    info "[plan] sudo apt-get update"
    info "[plan] sudo apt-get install -y mosh tmux kitty-terminfo ncurses-bin"
    return 0
  fi
  sudo -v
  sudo apt-get update
  sudo apt-get install -y mosh tmux kitty-terminfo ncurses-bin
}

install_macos() {
  command -v brew >/dev/null 2>&1 || \
    die "Homebrew no está instalado; instálalo desde https://brew.sh"
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] brew install mosh tmux"
    info "[plan] brew install --cask kitty"
    return 0
  fi
  brew install mosh tmux
  if brew list --cask kitty >/dev/null 2>&1; then
    ok "Kitty ya está instalado"
  else
    brew install --cask kitty
  fi
}

check_commands() {
  echo
  echo -e "${BOLD}${CYAN}═══ Estado Mosh/tmux/Kitty ═══${RESET}"
  printf 'os=%s\n' "$OS_TYPE"
  for command_name in mosh tmux; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=%s (%s)\n' "$command_name" available "$(command -v "$command_name")"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    if command -v kitty >/dev/null 2>&1 || [[ -d /Applications/kitty.app ]]; then
      echo 'kitty=available'
    else
      echo 'kitty=missing'
    fi
  else
    if command -v mosh-server >/dev/null 2>&1; then
      echo 'mosh-server=available'
    else
      echo 'mosh-server=missing'
    fi
    if command -v infocmp >/dev/null 2>&1 && infocmp -x xterm-kitty >/dev/null 2>&1; then
      echo 'kitty-terminfo=available'
    else
      warn "kitty-terminfo ausente: tmux no puede usar TERM=xterm-kitty"
    fi
  fi
  if [[ -f "$TMUX_CONFIG" ]] && grep -Fq '# BEGIN mosh-tmux-kitty' "$TMUX_CONFIG"; then
    ok "bloque de portapapeles tmux presente"
  else
    warn "bloque de portapapeles tmux ausente: $TMUX_CONFIG"
  fi
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    if [[ -f "$KITTY_CONFIG" ]] && grep -Fq '# BEGIN mosh-tmux-kitty' "$KITTY_CONFIG"; then
      ok "bloque de portapapeles Kitty presente"
    else
      warn "bloque de portapapeles Kitty ausente: $KITTY_CONFIG"
    fi
  fi
}

check_firewall() {
  [[ "$OS_TYPE" == "Linux" ]] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "UFW está activo; permite UDP 60000:61000 para Mosh si la conexión falla"
  elif systemctl is-active --quiet nftables.service 2>/dev/null; then
    warn "nftables está activo; permite UDP 60000:61000 para Mosh si la conexión falla"
  else
    info "no se detectó un firewall local activo"
  fi
}

configure_files() {
  append_managed_block "$TMUX_CONFIG" \
    '# BEGIN mosh-tmux-kitty clipboard' \
    '# END mosh-tmux-kitty clipboard' \
    "$(tmux_block)"
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    append_managed_block "$KITTY_CONFIG" \
      '# BEGIN mosh-tmux-kitty clipboard' \
      '# END mosh-tmux-kitty clipboard' \
      "$(kitty_block)"
  fi
}

main() {
  parse_args "$@"
  require_supported_os

  if [[ "$ACTION" == "check" ]]; then
    check_commands
    check_firewall
    exit 0
  fi

  if [[ "$OS_TYPE" == "Linux" ]]; then
    install_debian
  else
    install_macos
  fi
  configure_files
  check_commands
  check_firewall
  ok "Mosh, tmux y portapapeles preparados"
}

main "$@"
