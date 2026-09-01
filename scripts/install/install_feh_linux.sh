#!/usr/bin/env bash
# install_feh_linux.sh v1.0.0
# Instala feh y unifica el fondo del perfil ThinkPad en i3 y Openbox.
# shellcheck disable=SC2015
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION=check
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
HELPER_SOURCE="$REPO_ROOT/scripts/system/set_wallpaper_linux.sh"
HELPER_TARGET="$HOME/.local/bin/rafex-wallpaper.sh"
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
OPENBOX_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/autostart"
BEGIN='# BEGIN rafex feh wallpaper'
END='# END rafex feh wallpaper'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() { printf 'Uso: install_feh_linux.sh --check|--plan|--apply|--status\n'; }
parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check;; --plan|--dry-run) ACTION=plan;; --apply) ACTION=apply;; --status) ACTION=status;;
      --help|-h) usage; exit 0;; *) die "opción desconocida: $1";;
    esac
    shift
  done
}

require_platform() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
}
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy "$1" | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" || -L "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

replace_block() {
  local target="$1" block_file="$2" temporary
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$BEGIN" -v end="$END" -v block_file="$block_file" '
      function emit(  line) { while ((getline line < block_file) > 0) print line; close(block_file) }
      $0 == begin { emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
      END { if (!found) { print ""; emit() } }
    ' "$target" > "$temporary"
    if cmp -s "$target" "$temporary"; then rm -f -- "$temporary"; return 0; fi
    backup "$target"
    chmod --reference="$target" "$temporary" 2>/dev/null || true
  else
    mkdir -p -- "$(dirname -- "$target")"
    cat "$block_file" > "$temporary"
  fi
  mv -f -- "$temporary" "$target"
}

remove_unmarked_openbox_feh() {
  local target="$1" temporary
  [[ -f "$target" ]] || return 0
  temporary="$(mktemp)"
  awk '
    /if command -v feh .*Imágenes\/FondosDePantalla\/wallpaper\.jpg/ { skip=1; next }
    /if \[ -x .*rafex-wallpaper\.sh/ { skip=1; next }
    skip && /^[[:space:]]*fi[[:space:]]*$/ { skip=0; next }
    !skip { print }
  ' "$target" > "$temporary"
  if cmp -s "$target" "$temporary"; then rm -f -- "$temporary"; return 0; fi
  backup "$target"
  chmod --reference="$target" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$target"
}

install_helper() {
  [[ -f "$HELPER_SOURCE" ]] || die "falta $HELPER_SOURCE"
  mkdir -p -- "$(dirname -- "$HELPER_TARGET")"
  [[ ! -e "$HELPER_TARGET" || -L "$HELPER_TARGET" ]] || { cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" || backup "$HELPER_TARGET"; }
  install -m 0755 -- "$HELPER_SOURCE" "$HELPER_TARGET"
}

configure_integrations() {
  local block_file
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex feh wallpaper
exec_always --no-startup-id ~/.local/bin/rafex-wallpaper.sh
# END rafex feh wallpaper
EOF
  replace_block "$I3_CONFIG" "$block_file"
  remove_unmarked_openbox_feh "$OPENBOX_AUTOSTART"
  replace_block "$OPENBOX_AUTOSTART" "$block_file"
  rm -f -- "$block_file"
}

show_status() {
  echo '═══ feh y fondo ThinkPad ═══'
  installed feh && ok 'feh instalado' || warn 'feh no está instalado'
  [[ -x "$HELPER_TARGET" ]] && ok "helper presente: $HELPER_TARGET" || warn "helper ausente: $HELPER_TARGET"
  [[ -f "$I3_CONFIG" ]] && grep -Fq "$BEGIN" "$I3_CONFIG" && ok 'fondo integrado en i3' || warn 'fondo no integrado en i3'
  [[ -f "$OPENBOX_AUTOSTART" ]] && grep -Fq "$BEGIN" "$OPENBOX_AUTOSTART" && ok 'fondo integrado en Openbox' || warn 'fondo no integrado en Openbox'
}

main() {
  parse_args "$@"; require_platform
  case "$ACTION" in
    check)
      echo '═══ Comprobación feh ═══'
      installed feh && ok 'feh instalado' || { candidate feh && ok 'feh tiene candidato APT' || warn 'feh no tiene candidato APT'; }
      show_status;;
    plan)
      echo '═══ Plan feh ═══'
      installed feh && info '[plan] conservar feh' || info '[plan] instalar feh mediante APT'
      info "[plan] instalar $HELPER_TARGET y actualizar i3/Openbox";;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      if ! installed feh; then candidate feh || die 'feh no tiene candidato APT'; sudo -v; sudo apt-get update; sudo apt-get install -y feh; fi
      install_helper; configure_integrations; ok 'feh instalado e integrado';;
    status) show_status;;
  esac
}
main "$@"
