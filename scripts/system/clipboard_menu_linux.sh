#!/usr/bin/env bash
# v1.0.0 - Acceso seguro al historial de CopyQ desde i3 u Openbox.
set -Eeuo pipefail
umask 077
export LC_ALL=C

ACTION="show"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  clipboard_menu_linux.sh --show
  clipboard_menu_linux.sh --menu
  clipboard_menu_linux.sh --status

Abre el historial visual de CopyQ o su menú de bandeja. El proceso se inicia
solo si falta y nunca requiere sudo.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --show) ACTION="show" ;;
      --menu) ACTION="menu" ;;
      --status|--check) ACTION="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_user_session() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal'
  command -v copyq >/dev/null 2>&1 ||
    die 'CopyQ no está instalado; ejecuta just install-clipboard --apply'
}

copyq_running() {
  pgrep -u "$(id -u)" -x copyq >/dev/null 2>&1
}

start_copyq() {
  local attempt=0
  if ! copyq_running; then
    (copyq >/dev/null 2>&1 &)
  fi
  while ((attempt < 20)); do
    if copyq info config >/dev/null 2>&1; then return 0; fi
    attempt=$((attempt + 1))
    sleep 0.1
  done
  die 'CopyQ no respondió; revisa la sesión X11 y ejecuta copyq desde una terminal'
}

show_status() {
  printf '═══ Portapapeles CopyQ ═══\n'
  if command -v copyq >/dev/null 2>&1; then
    ok "CopyQ disponible: $(copyq --version 2>/dev/null | head -n 1 || true)"
  else
    warn 'CopyQ no está instalado'
  fi
  if copyq_running; then
    ok 'servidor CopyQ activo'
  else
    warn 'servidor CopyQ detenido'
  fi
  printf 'config=%s\n' "$HOME/.config/copyq"
  printf 'datos=%s\n' "$HOME/.local/share/copyq"
  [[ -n "${DISPLAY:-}" ]] || info 'DISPLAY ausente: no se intenta abrir la interfaz'
}

main() {
  parse_args "$@"
  require_user_session
  case "$ACTION" in
    status) show_status ;;
    show)
      [[ -n "${DISPLAY:-}" ]] || die 'no existe DISPLAY; ejecuta esto dentro de la sesión gráfica'
      start_copyq
      copyq show
      ;;
    menu)
      [[ -n "${DISPLAY:-}" ]] || die 'no existe DISPLAY; ejecuta esto dentro de la sesión gráfica'
      start_copyq
      copyq menu
      ;;
  esac
}

main "$@"
