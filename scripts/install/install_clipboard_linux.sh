#!/usr/bin/env bash
# v1.0.0 - Instala CopyQ y lo integra de forma idempotente en X11.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
readonly COPYQ_HELPER_SOURCE="$REPO_ROOT/scripts/system/clipboard_menu_linux.sh"
readonly COPYQ_HELPER_TARGET="$HOME/.local/bin/clipboard-menu.sh"
readonly I3_CONFIG="${I3_CONFIG:-$HOME/.config/i3/config}"
readonly OPENBOX_AUTOSTART="${OPENBOX_AUTOSTART:-$HOME/.config/openbox/autostart}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_clipboard_linux.sh --check
  install_clipboard_linux.sh --plan
  install_clipboard_linux.sh --apply
  install_clipboard_linux.sh --status

Instala CopyQ desde Debian, inicia una única instancia por sesión y añade
Super+Shift+V para abrir el historial. El historial permanece en el usuario.
EOF
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

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}"
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  [[ -f "$COPYQ_HELPER_SOURCE" ]] || die "falta el helper: $COPYQ_HELPER_SOURCE"
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

show_package() {
  local candidate
  if package_installed copyq; then
    ok 'copyq instalado'
  else
    candidate="$(package_candidate copyq)"
    printf '✗ copyq ausente (candidato: %s)\n' "${candidate:-(none)}"
  fi
}

backup_path() {
  local path="$1" backup="${1}.bak.${STAMP}"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -e "$backup" || -L "$backup" ]] || cp -a -- "$path" "$backup"
  info "respaldo creado: $backup"
}

install_helper() {
  local temporary
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $COPYQ_HELPER_TARGET"
    return 0
  fi
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$HOME/.local/bin"
  if [[ -f "$COPYQ_HELPER_TARGET" ]] && cmp -s "$COPYQ_HELPER_SOURCE" "$COPYQ_HELPER_TARGET"; then
    return 0
  fi
  backup_path "$COPYQ_HELPER_TARGET"
  temporary="$(mktemp "${COPYQ_HELPER_TARGET}.tmp.XXXXXX")"
  install -m 0755 "$COPYQ_HELPER_SOURCE" "$temporary"
  mv -f -- "$temporary" "$COPYQ_HELPER_TARGET"
  ok "helper instalado: $COPYQ_HELPER_TARGET"
}

replace_block() {
  local target="$1" begin="$2" end="$3" block_file="$4" mode="$5" temporary
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) }
      $0 == begin { emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
      END { if (!found) { print ""; emit() } }
    ' "$target" > "$temporary"
  else
    awk -v block_file="$block_file" 'function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) } BEGIN { emit() }' > "$temporary"
  fi
  if [[ -f "$target" ]] && cmp -s "$target" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  backup_path "$target"
  chmod "$mode" "$temporary"
  mv -f -- "$temporary" "$target"
}

configure_i3() {
  local block_file begin='# BEGIN rafex clipboard' end='# END rafex clipboard'
  [[ "$ACTION" == plan ]] && { info "[plan] actualizar $I3_CONFIG"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$I3_CONFIG")"
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex clipboard
exec_always --no-startup-id sh -c 'command -v copyq >/dev/null 2>&1 && ! pgrep -x copyq >/dev/null 2>&1 && exec copyq'
bindsym $mod+Shift+v exec --no-startup-id ~/.local/bin/clipboard-menu.sh --show
# END rafex clipboard
EOF
  replace_block "$I3_CONFIG" "$begin" "$end" "$block_file" 644
  rm -f -- "$block_file"
  ok 'CopyQ integrado en i3'
}

configure_openbox() {
  local block_file begin='# BEGIN rafex clipboard' end='# END rafex clipboard'
  [[ "$ACTION" == plan ]] && { info "[plan] actualizar $OPENBOX_AUTOSTART"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$OPENBOX_AUTOSTART")"
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex clipboard
if command -v copyq >/dev/null 2>&1 && ! pgrep -x copyq >/dev/null 2>&1; then
    copyq >/dev/null 2>&1 &
fi
# END rafex clipboard
EOF
  replace_block "$OPENBOX_AUTOSTART" "$begin" "$end" "$block_file" 755
  rm -f -- "$block_file"
  ok 'CopyQ integrado en Openbox'
}

show_status() {
  echo '═══ Portapapeles ThinkPad ═══'
  show_package
  if [[ -x "$COPYQ_HELPER_TARGET" ]]; then
    ok "helper presente: $COPYQ_HELPER_TARGET"
  else
    warn 'helper ausente'
  fi
  if [[ -f "$I3_CONFIG" ]] && grep -Fq '# BEGIN rafex clipboard' "$I3_CONFIG"; then
    ok 'bloque i3 presente'
  else
    warn 'bloque i3 ausente'
  fi
  if [[ -f "$OPENBOX_AUTOSTART" ]] && grep -Fq '# BEGIN rafex clipboard' "$OPENBOX_AUTOSTART"; then
    ok 'bloque Openbox presente'
  else
    warn 'bloque Openbox ausente'
  fi
}

apply_install() {
  local candidate
  sudo -v
  candidate="$(package_candidate copyq)"
  [[ -n "$candidate" && "$candidate" != '(none)' ]] || die 'copyq no tiene candidato APT; revisa las fuentes Debian'
  sudo apt-get update
  sudo apt-get install -y copyq
  install_helper
  configure_i3
  configure_openbox
  ok 'CopyQ instalado; usa Super+Shift+V para abrir su historial'
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check|status) show_status ;;
    plan)
      echo '═══ Plan portapapeles ThinkPad ═══'
      show_package
      info '[plan] instalar copyq desde Debian'
      install_helper
      configure_i3
      configure_openbox
      info '[plan] no modificar otros atajos ni guardar credenciales'
      ;;
    apply) apply_install ;;
  esac
}

main "$@"
