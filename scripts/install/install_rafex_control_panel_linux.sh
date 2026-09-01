#!/usr/bin/env bash
# install_rafex_control_panel_linux.sh v1.0.0
# Instala el panel GTK3/PyGObject del perfil sin daemon root.
# shellcheck disable=SC2015
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION=check
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/scripts/system/rafex_control_panel.py"
PY_TARGET="$HOME/.local/bin/rafex-control-panel.py"
WRAPPER_TARGET="$HOME/.local/bin/rafex-control-panel.sh"
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
OPENBOX_RC="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/rc.xml"
OPENBOX_MENU="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/menu.xml"
STAMP="$(date +%Y%m%d_%H%M%S)"

PACKAGES=(python3 python3-gi gir1.2-gtk-3.0)
I3_BEGIN='# BEGIN rafex control panel'
I3_END='# END rafex control panel'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

while (($#)); do
  case "$1" in
    --check) ACTION=check;; --plan|--dry-run) ACTION=plan;; --apply) ACTION=apply;; --status) ACTION=status;;
    --help|-h) printf 'Uso: install_rafex_control_panel_linux.sh --check|--plan|--apply|--status\n'; exit 0;;
    *) die "opción desconocida: $1";;
  esac
  shift
done

install_files() {
  mkdir -p -- "$HOME/.local/bin"
  if [[ -e "$PY_TARGET" ]] && ! cmp -s "$SOURCE" "$PY_TARGET"; then backup "$PY_TARGET"; fi
  install -m 0755 -- "$SOURCE" "$PY_TARGET"
  if [[ -e "$WRAPPER_TARGET" ]] && ! grep -Fq 'rafex-control-panel.py' "$WRAPPER_TARGET"; then backup "$WRAPPER_TARGET"; fi
  cat > "$WRAPPER_TARGET" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec python3 "$HOME/.local/bin/rafex-control-panel.py" "$@"
EOF
  chmod 0755 "$WRAPPER_TARGET"
}

configure_i3() {
  local temporary block_file
  [[ -f "$I3_CONFIG" ]] || return 0
  block_file="$(mktemp)"
  cat > "$block_file" <<EOF
$I3_BEGIN
bindsym \$mod+Control+p exec --no-startup-id ~/.local/bin/rafex-control-panel.sh
for_window [class="RafexControlPanel"] floating enable, border pixel 0
$I3_END
EOF
  temporary="$(mktemp)"
  awk -v begin="$I3_BEGIN" -v end="$I3_END" -v block_file="$block_file" '
    function emit(  line) { while ((getline line < block_file) > 0) print line; close(block_file) }
    $0 == begin { emit(); inside=1; found=1; next }
    inside && $0 == end { inside=0; next }
    !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+\$mod\+Control\+p[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/\.local\/bin\/rafex-control-panel\.sh[[:space:]]*$/ { next }
    !inside { print }
    END { if (!found) { print ""; emit() } }
  ' "$I3_CONFIG" > "$temporary"
  rm -f -- "$block_file"
  if cmp -s "$I3_CONFIG" "$temporary"; then rm -f -- "$temporary"; return 0; fi
  backup "$I3_CONFIG"
  chmod --reference="$I3_CONFIG" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$I3_CONFIG"
}

configure_openbox() {
  local temporary
  [[ -f "$OPENBOX_RC" ]] || return 0
  if ! grep -Fq 'W-C-p' "$OPENBOX_RC"; then
    temporary="$(mktemp)"
    awk '/<keyboard>/ && !added { print; print "    <keybind key=\"W-C-p\"><action name=\"Execute\"><command>~/.local/bin/rafex-control-panel.sh</command></action></keybind>"; added=1; next } { print }' "$OPENBOX_RC" > "$temporary"
    backup "$OPENBOX_RC"
    chmod --reference="$OPENBOX_RC" "$temporary" 2>/dev/null || true
    mv -f -- "$temporary" "$OPENBOX_RC"
  fi
}

configure_menu() {
  local temporary
  [[ -f "$OPENBOX_MENU" ]] || return 0
  grep -Fq 'Panel de control Rafex' "$OPENBOX_MENU" && return 0
  temporary="$(mktemp)"
  awk '/<menu id="root-menu"/ && !added { print; print "    <item label=\"Panel de control Rafex\"><action name=\"Execute\"><command>~/.local/bin/rafex-control-panel.sh</command></action></item>"; added=1; next } { print }' "$OPENBOX_MENU" > "$temporary"
  backup "$OPENBOX_MENU"
  chmod --reference="$OPENBOX_MENU" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$OPENBOX_MENU"
}

show_status() {
  echo '═══ Panel de control Rafex ═══'
  [[ -x "$WRAPPER_TARGET" && -x "$PY_TARGET" ]] && ok 'panel instalado' || warn 'panel ausente'
  for p in "${PACKAGES[@]}"; do installed "$p" && ok "$p instalado" || warn "$p ausente"; done
  [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG" && ok 'atajo i3 Super+Control+P presente' || warn 'atajo i3 ausente'
  [[ -f "$OPENBOX_RC" ]] && grep -Fq 'W-C-p' "$OPENBOX_RC" && ok 'atajo Openbox Super+Control+P presente' || warn 'atajo Openbox ausente'
  info 'sin daemon root; APT continúa gestionándose con Synaptic o Just'
}

main() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo '═══ Comprobación panel Rafex ═══'
      for p in "${PACKAGES[@]}"; do installed "$p" && ok "$p instalado" || { candidate "$p" && ok "$p tiene candidato APT" || warn "sin candidato APT: $p"; }; done
      show_status
      ;;
    plan)
      echo '═══ Plan panel Rafex ═══'
      info '[plan] instalar Python3, PyGObject y GTK3 si faltan'
      info "[plan] instalar $PY_TARGET y $WRAPPER_TARGET"
      info '[plan] integrar Super+Control+P en i3 y Openbox y añadir entrada al menú'
      info '[plan] no crear daemon root ni permitir comandos arbitrarios'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      local apt_packages=() p
      for p in "${PACKAGES[@]}"; do if ! installed "$p"; then candidate "$p" || die "sin candidato APT: $p"; apt_packages+=("$p"); fi; done
      if ((${#apt_packages[@]})); then sudo -v; sudo apt-get update; sudo apt-get install -y "${apt_packages[@]}"; fi
      install_files
      configure_i3
      configure_openbox
      configure_menu
      ok 'panel instalado; ejecútalo como usuario con rafex-control-panel.sh'
      ;;
    status) show_status;;
  esac
}

main "$@"
