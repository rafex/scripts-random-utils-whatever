#!/usr/bin/env bash
# install_ratmenu_linux.sh v1.1.0
# Instala ratmenu y lo integra como menú activo sin eliminar 9menu.
# shellcheck disable=SC2015,SC2016
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION=check
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/scripts/system/rafex_ratmenu_linux.sh"
TARGET="$HOME/.local/bin/rafex-ratmenu.sh"
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
OPENBOX_RC="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/rc.xml"
OPENBOX_MENU="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/menu.xml"
OPENBOX_ROOT_BEGIN='        <!-- BEGIN rafex ratmenu root -->'
OPENBOX_ROOT_END='        <!-- END rafex ratmenu root -->'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check;;
      --plan|--dry-run) ACTION=plan;;
      --apply) ACTION=apply;;
      --status) ACTION=status;;
      --help|-h) printf 'Uso: install_ratmenu_linux.sh --check|--plan|--apply|--status\n'; exit 0;;
      *) die "opción desconocida: $1";;
    esac
    shift
  done
}

installed() { dpkg-query -W -f='${Status}' ratmenu 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy ratmenu | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

install_helper() {
  mkdir -p -- "$(dirname -- "$TARGET")"
  if [[ -e "$TARGET" ]] && ! cmp -s "$SOURCE" "$TARGET"; then backup "$TARGET"; fi
  install -m 0755 -- "$SOURCE" "$TARGET"
}

replace_in_file() {
  local file="$1" temporary
  [[ -f "$file" ]] || return 0
  temporary="$(mktemp)"
  sed -e 's#9menu -popup -label "ThinkPad" -file ~/.config/9menu/laptop.menu#~/.local/bin/rafex-ratmenu.sh#g' \
      -e 's#9menu -popup -label "ThinkPad" -file \$HOME/.config/9menu/laptop.menu#~/.local/bin/rafex-ratmenu.sh#g' \
      "$file" > "$temporary"
  if cmp -s "$file" "$temporary"; then rm -f -- "$temporary"; return 0; fi
  backup "$file"
  chmod --reference="$file" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$file"
}

configure_openbox_menu() {
  local file="$OPENBOX_MENU" temporary
  [[ -f "$file" ]] || return 0
  if grep -Fq 'Panel de control Rafex' "$file"; then return 0; fi
  temporary="$(mktemp)"
  awk '
    /<menu id="root-menu"/ && !added {
      print
      print "    <item label=\"Panel de control Rafex\"><action name=\"Execute\"><command>~/.local/bin/rafex-control-panel.sh</command></action></item>"
      added=1
      next
    }
    { print }
  ' "$file" > "$temporary"
  backup "$file"
  chmod --reference="$file" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$file"
}

configure_openbox_root_menu() {
  local file="$OPENBOX_RC" temporary
  [[ -f "$file" ]] || return 0
  temporary="$(mktemp)"
  if grep -Fq "$OPENBOX_ROOT_BEGIN" "$file"; then
    awk -v begin="$OPENBOX_ROOT_BEGIN" -v end="$OPENBOX_ROOT_END" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      trim($0) == trim(begin) {
        if (!found) {
          print begin
          print "    <action name=\"Execute\"><command>~/.local/bin/rafex-ratmenu.sh</command></action>"
        }
        found=1
        inside=1
        next
      }
      inside && trim($0) == trim(end) { inside=0; next }
      !inside { print }
      END { if (!found) exit 42 }
    ' "$file" > "$temporary"
  else
    awk '
      /<context name="Root">/ { in_root=1 }
      in_root && /<action name="ShowMenu"><menu>root-menu<\/menu><\/action>/ {
          print "        <!-- BEGIN rafex ratmenu root -->"
          print "        <action name=\"Execute\"><command>~/.local/bin/rafex-ratmenu.sh</command></action>"
          print "        <!-- END rafex ratmenu root -->"
        found=1
        next
      }
      /<\/context>/ && in_root { in_root=0 }
      { print }
      END { if (!found) exit 42 }
    ' "$file" > "$temporary" || {
      rm -f -- "$temporary"
      warn 'no se encontró el menú raíz de Openbox; no se modificó rc.xml'
      return 0
    }
  fi
  if cmp -s "$file" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  backup "$file"
  chmod --reference="$file" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$file"
  ok 'menú raíz de Openbox migrado a ratmenu'
}

show_status() {
  echo '═══ Ratmenu ThinkPad ═══'
  installed && ok 'ratmenu instalado' || warn 'ratmenu no está instalado'
  [[ -x "$TARGET" ]] && ok "helper presente: $TARGET" || warn "helper ausente: $TARGET"
  [[ -x "$HOME/.local/bin/9menu" || -x /usr/bin/9menu ]] && ok '9menu se conserva como respaldo' || warn '9menu no está disponible'
  [[ -f "$I3_CONFIG" ]] && grep -Fq 'rafex-ratmenu.sh' "$I3_CONFIG" && ok 'i3 usa ratmenu' || warn 'i3 aún no usa ratmenu'
  [[ -f "$OPENBOX_RC" ]] && grep -Fq 'rafex-ratmenu.sh' "$OPENBOX_RC" && ok 'Openbox usa ratmenu' || warn 'Openbox aún no usa ratmenu'
  [[ -f "$OPENBOX_RC" ]] && grep -Fq 'BEGIN rafex ratmenu root' "$OPENBOX_RC" && ok 'el menú raíz de Openbox usa ratmenu' || warn 'el menú raíz de Openbox aún usa su menú nativo'
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo '═══ Comprobación ratmenu ═══'
      installed && ok 'ratmenu instalado' || { candidate && ok 'ratmenu tiene candidato APT' || warn 'ratmenu no tiene candidato APT'; }
      show_status
      ;;
    plan)
      echo '═══ Plan ratmenu ═══'
      installed && info '[plan] conservar ratmenu' || info '[plan] instalar ratmenu mediante APT'
      info "[plan] instalar $TARGET"
      info '[plan] migrar i3, el menú raíz de Openbox y los accesos conocidos a ratmenu; conservar 9menu como fallback'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      if ! installed; then
        candidate || die 'ratmenu no tiene candidato APT'
        sudo -v
        sudo apt-get update
        sudo apt-get install -y ratmenu
      fi
      install_helper
      replace_in_file "$I3_CONFIG"
      replace_in_file "$OPENBOX_RC"
      replace_in_file "$OPENBOX_MENU"
      configure_openbox_menu
      configure_openbox_root_menu
      ok 'ratmenu activo; 9menu y su configuración se conservaron como respaldo'
      ;;
    status) show_status;;
  esac
}

main "$@"
