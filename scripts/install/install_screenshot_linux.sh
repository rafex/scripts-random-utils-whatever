#!/usr/bin/env bash
# v1.0.0 - Instala el backend maim y registra atajos X11 de captura.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
readonly SCREENSHOT_SOURCE="$REPO_ROOT/scripts/system/screenshot_linux.sh"
readonly SCREENSHOT_TARGET="$HOME/.local/bin/screenshot.sh"
readonly I3_CONFIG="${I3_CONFIG:-$HOME/.config/i3/config}"
readonly OPENBOX_RC="${OPENBOX_RC:-$HOME/.config/openbox/rc.xml}"

readonly -a PACKAGES=(maim xclip libnotify-bin x11-utils slop)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_screenshot_linux.sh --check
  install_screenshot_linux.sh --plan
  install_screenshot_linux.sh --apply
  install_screenshot_linux.sh --status

Instala maim/slop y registra: Super+P (pantalla), Print (pantalla),
Shift+Print (selección) y Ctrl+Print (ventana activa).
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
  [[ -f "$SCREENSHOT_SOURCE" ]] || die "falta el helper: $SCREENSHOT_SOURCE"
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'; }
package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

show_packages() {
  local package candidate
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      ok "$package instalado"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-16s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
}

backup_path() {
  local path="$1" backup="${1}.bak.${STAMP}"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -e "$backup" || -L "$backup" ]] || cp -a -- "$path" "$backup"
  info "respaldo creado: $backup"
}

install_helper() {
  local temporary
  if [[ "$ACTION" == plan ]]; then info "[plan] instalar $SCREENSHOT_TARGET"; return 0; fi
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$HOME/.local/bin"
  if [[ -f "$SCREENSHOT_TARGET" ]] && cmp -s "$SCREENSHOT_SOURCE" "$SCREENSHOT_TARGET"; then return 0; fi
  backup_path "$SCREENSHOT_TARGET"
  temporary="$(mktemp "${SCREENSHOT_TARGET}.tmp.XXXXXX")"
  install -m 0755 "$SCREENSHOT_SOURCE" "$temporary"
  mv -f -- "$temporary" "$SCREENSHOT_TARGET"
  ok "helper instalado: $SCREENSHOT_TARGET"
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
  if [[ -f "$target" ]] && cmp -s "$target" "$temporary"; then rm -f -- "$temporary"; return 0; fi
  backup_path "$target"
  chmod "$mode" "$temporary"
  mv -f -- "$temporary" "$target"
}

remove_i3_legacy() {
  local temporary
  [[ -f "$I3_CONFIG" ]] || return 0
  if ! grep -Eq "^[[:space:]]*bindsym[[:space:]]+\\\$mod\\+p[[:space:]]+exec.*maim" "$I3_CONFIG"; then return 0; fi
  backup_path "$I3_CONFIG"
  temporary="$(mktemp)"
  awk '!/^[[:space:]]*bindsym[[:space:]]+\$mod\+p[[:space:]]+exec.*maim/ { print }' "$I3_CONFIG" > "$temporary"
  chmod 644 "$temporary"
  mv -f -- "$temporary" "$I3_CONFIG"
  info 'binding legacy de maim eliminado'
}

remove_openbox_legacy() {
  local temporary
  [[ -f "$OPENBOX_RC" ]] || return 0
  if ! grep -Eq '^[[:space:]]*<keybind key="W-p">.*maim' "$OPENBOX_RC"; then return 0; fi
  backup_path "$OPENBOX_RC"
  temporary="$(mktemp)"
  awk '!/^[[:space:]]*<keybind key="W-p">.*maim/ { print }' "$OPENBOX_RC" > "$temporary"
  chmod 644 "$temporary"
  mv -f -- "$temporary" "$OPENBOX_RC"
  info 'binding legacy de maim eliminado de Openbox'
}

configure_i3() {
  local block_file begin='# BEGIN rafex screenshots' end='# END rafex screenshots'
  [[ "$ACTION" == plan ]] && { info "[plan] actualizar $I3_CONFIG"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$I3_CONFIG")"
  remove_i3_legacy
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex screenshots
bindsym $mod+p exec --no-startup-id ~/.local/bin/screenshot.sh --full
bindsym Print exec --no-startup-id ~/.local/bin/screenshot.sh --full
bindsym Shift+Print exec --no-startup-id ~/.local/bin/screenshot.sh --select
bindsym Ctrl+Print exec --no-startup-id ~/.local/bin/screenshot.sh --window
# END rafex screenshots
EOF
  replace_block "$I3_CONFIG" "$begin" "$end" "$block_file" 644
  rm -f -- "$block_file"
  ok 'capturas integradas en i3'
}

configure_openbox() {
  local block_file begin='<!-- BEGIN rafex screenshots -->' end='<!-- END rafex screenshots -->'
  [[ "$ACTION" == plan ]] && { info "[plan] actualizar $OPENBOX_RC"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$OPENBOX_RC")"
  remove_openbox_legacy
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
    <!-- BEGIN rafex screenshots -->
    <keybind key="W-p"><action name="Execute"><command>~/.local/bin/screenshot.sh --full</command></action></keybind>
    <keybind key="Print"><action name="Execute"><command>~/.local/bin/screenshot.sh --full</command></action></keybind>
    <keybind key="S-Print"><action name="Execute"><command>~/.local/bin/screenshot.sh --select</command></action></keybind>
    <keybind key="C-Print"><action name="Execute"><command>~/.local/bin/screenshot.sh --window</command></action></keybind>
    <!-- END rafex screenshots -->
EOF
  replace_block "$OPENBOX_RC" "$begin" "$end" "$block_file" 644
  rm -f -- "$block_file"
  ok 'capturas integradas en Openbox'
}

validate_candidates() {
  local package candidate missing=0
  for package in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done
  ((missing == 0)) || die 'uno o más paquetes de captura no tienen candidato APT'
}

show_status() {
  echo '═══ Capturador de pantalla ThinkPad ═══'
  show_packages
  if [[ -x "$SCREENSHOT_TARGET" ]]; then
    ok "helper presente: $SCREENSHOT_TARGET"
  else
    warn 'helper ausente'
  fi
  if [[ -f "$I3_CONFIG" ]] && grep -Fq '# BEGIN rafex screenshots' "$I3_CONFIG"; then
    ok 'bloque i3 presente'
  else
    warn 'bloque i3 ausente'
  fi
  if [[ -f "$OPENBOX_RC" ]] && grep -Fq '<!-- BEGIN rafex screenshots -->' "$OPENBOX_RC"; then
    ok 'bloque Openbox presente'
  else
    warn 'bloque Openbox ausente'
  fi
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check|status) show_status ;;
    plan)
      echo '═══ Plan capturador ThinkPad ═══'
      show_packages
      info '[plan] instalar maim, slop, xclip, x11-utils y libnotify-bin desde Debian'
      install_helper
      configure_i3
      configure_openbox
      info '[plan] guardar PNG bajo HOME y no usar sudo durante la captura'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
      sudo -v
      sudo apt-get update
      validate_candidates
      sudo apt-get install -y "${PACKAGES[@]}"
      install_helper
      configure_i3
      configure_openbox
      ok 'capturador instalado; usa Print, Shift+Print o Ctrl+Print'
      ;;
  esac
}

main "$@"
