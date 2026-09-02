#!/usr/bin/env bash
# install_eww_linux.sh v1.1.1
# Compila EWW fijado para X11 e instala los widgets Rafex sin reservar espacio.
# shellcheck disable=SC2015
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

ACTION=check
VERSION="v0.6.0"
TIME_INCOMPAT_VERSION="0.3.34"
TIME_COMPAT_VERSION="0.3.36"
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_ROOT="$HOME/.local/share/rafex/eww/${VERSION}-src"
TARGET="$HOME/.local/bin/eww"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"
YUCK_SOURCE="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/eww/eww.yuck"
THEME_SOURCE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes"
WIDGETS_SOURCE="$REPO_ROOT/scripts/system/eww_widgets_linux.sh"
ACTIONS_SOURCE="$REPO_ROOT/scripts/system/eww_actions_linux.sh"
WIDGETS_TARGET="$HOME/.local/bin/eww-widgets.sh"
ACTIONS_TARGET="$HOME/.local/bin/eww-actions.sh"
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
OPENBOX_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/autostart"
OPENBOX_RC="${XDG_CONFIG_HOME:-$HOME/.config}/openbox/rc.xml"
I3_BEGIN="# BEGIN rafex eww"
I3_END="# END rafex eww"
OPENBOX_BEGIN="# BEGIN rafex eww"
OPENBOX_END="# END rafex eww"
OPENBOX_RC_BEGIN="    <!-- BEGIN rafex eww -->"
OPENBOX_RC_END="    <!-- END rafex eww -->"

BUILD_PACKAGES=(git cargo rustc build-essential pkg-config libgtk-3-dev libpango1.0-dev
  libdbusmenu-gtk3-dev libcairo2-dev libglib2.0-dev libgdk-pixbuf-2.0-dev playerctl)

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
      --help|-h) printf 'Uso: install_eww_linux.sh --check|--plan|--apply|--status\n'; exit 0;;
      *) die "opción desconocida: $1";;
    esac
    shift
  done
}

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" || -L "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

install_managed_file() {
  local source="$1" target="$2" mode="$3" temporary
  [[ -f "$source" ]] || die "falta el archivo administrado: $source"
  mkdir -p -- "$(dirname -- "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    backup "$target"
  fi
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  cp -- "$source" "$temporary"
  chmod "$mode" "$temporary"
  mv -f -- "$temporary" "$target"
}

write_config() {
  local scss_source
  [[ -f "$YUCK_SOURCE" ]] || die "falta la configuración Yuck del perfil: $YUCK_SOURCE"
  mkdir -p -- "$CONFIG_ROOT"
  if [[ -e "$CONFIG_ROOT/eww.yuck" ]] && ! grep -Fq 'BEGIN rafex EWW dashboard' "$CONFIG_ROOT/eww.yuck"; then
    warn 'se conservará un respaldo de la configuración EWW no administrada'
  fi
  install_managed_file "$YUCK_SOURCE" "$CONFIG_ROOT/eww.yuck" 600
  scss_source="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/themes/current/eww.scss"
  if [[ ! -f "$scss_source" ]]; then
    scss_source="$THEME_SOURCE_ROOT/nord/eww.scss"
  fi
  install_managed_file "$scss_source" "$CONFIG_ROOT/eww.scss" 600
}

replace_block() {
  local target="$1" begin="$2" end="$3" block_file="$4" temporary
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) }
      $0 == begin { emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
      END { if (!found) { print ""; emit() } }
    ' "$target" > "$temporary"
    if cmp -s "$target" "$temporary"; then
      rm -f -- "$temporary"
      return 0
    fi
    backup "$target"
    chmod --reference="$target" "$temporary" 2>/dev/null || true
  else
    mkdir -p -- "$(dirname -- "$target")"
    cat "$block_file" > "$temporary"
  fi
  mv -f -- "$temporary" "$target"
}

replace_openbox_keyboard_block() {
  local block_file="$1" temporary
  [[ -f "$OPENBOX_RC" ]] || return 0
  if grep -Fq "$OPENBOX_RC_BEGIN" "$OPENBOX_RC"; then
    replace_block "$OPENBOX_RC" "$OPENBOX_RC_BEGIN" "$OPENBOX_RC_END" "$block_file"
    return 0
  fi
  temporary="$(mktemp)"
  awk -v block_file="$block_file" '
    function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) }
    /^[[:space:]]*<\/keyboard>[[:space:]]*$/ { emit() }
    { print }
  ' "$OPENBOX_RC" > "$temporary"
  if cmp -s "$OPENBOX_RC" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  backup "$OPENBOX_RC"
  chmod --reference="$OPENBOX_RC" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$OPENBOX_RC"
}

install_helpers() {
  install_managed_file "$WIDGETS_SOURCE" "$WIDGETS_TARGET" 700
  install_managed_file "$ACTIONS_SOURCE" "$ACTIONS_TARGET" 700
}

configure_integrations() {
  local i3_block openbox_block openbox_rc_block
  i3_block="$(mktemp)"
  cat > "$i3_block" <<'EOF'
# BEGIN rafex eww
exec_always --no-startup-id sh -c 'if [ -x "$HOME/.local/bin/eww-widgets.sh" ]; then "$HOME/.local/bin/eww-widgets.sh" --open dashboard >/dev/null 2>&1; fi'
bindsym $mod+Control+w exec --no-startup-id ~/.local/bin/eww-widgets.sh --toggle dashboard
# END rafex eww
EOF
  replace_block "$I3_CONFIG" "$I3_BEGIN" "$I3_END" "$i3_block"

  openbox_block="$(mktemp)"
  cat > "$openbox_block" <<'EOF'
# BEGIN rafex eww
if [ -x "$HOME/.local/bin/eww-widgets.sh" ]; then
    "$HOME/.local/bin/eww-widgets.sh" --open dashboard >/dev/null 2>&1 &
fi
# END rafex eww
EOF
  replace_block "$OPENBOX_AUTOSTART" "$OPENBOX_BEGIN" "$OPENBOX_END" "$openbox_block"

  openbox_rc_block="$(mktemp)"
  cat > "$openbox_rc_block" <<'EOF'
    <!-- BEGIN rafex eww -->
    <keybind key="W-C-w"><action name="Execute"><command>~/.local/bin/eww-widgets.sh --toggle dashboard</command></action></keybind>
    <!-- END rafex eww -->
EOF
  replace_openbox_keyboard_block "$openbox_rc_block"
  rm -f -- "$i3_block" "$openbox_block" "$openbox_rc_block"
}

prepare_lockfile() {
  local time_versions
  [[ -f "$SOURCE_ROOT/Cargo.lock" ]] || return 0
  time_versions="$(awk '
    /^\[\[package\]\]$/ { in_time = 0 }
    /^name = "time"$/ { in_time = 1; next }
    in_time && /^version = / { gsub(/"/, "", $3); print $3; in_time = 0 }
  ' "$SOURCE_ROOT/Cargo.lock")"
  if grep -Fqx "$TIME_INCOMPAT_VERSION" <<<"$time_versions"; then
    info "actualizando dependencia incompatible time ${TIME_INCOMPAT_VERSION} → ${TIME_COMPAT_VERSION}"
    (cd "$SOURCE_ROOT" && cargo update -p "time@${TIME_INCOMPAT_VERSION}" --precise "$TIME_COMPAT_VERSION")
    time_versions="$(awk '
      /^\[\[package\]\]$/ { in_time = 0 }
      /^name = "time"$/ { in_time = 1; next }
      in_time && /^version = / { gsub(/"/, "", $3); print $3; in_time = 0 }
    ' "$SOURCE_ROOT/Cargo.lock")"
  fi
  if grep -Fqx "$TIME_INCOMPAT_VERSION" <<<"$time_versions"; then
    die "Cargo no actualizó time ${TIME_INCOMPAT_VERSION}; no se inicia la compilación"
  fi
  if grep -Fqx "$TIME_COMPAT_VERSION" <<<"$time_versions"; then
    ok "dependencia time compatible confirmada: ${TIME_COMPAT_VERSION}"
  fi
}

show_status() {
  echo "═══ EWW ${VERSION} ThinkPad ═══"
  if [[ -x "$TARGET" ]]; then
    ok "binario local: $TARGET"
    ok "versión: $($TARGET --version 2>/dev/null | head -n 1)"
  elif command -v eww >/dev/null 2>&1; then
    ok "eww disponible: $(eww --version 2>/dev/null | head -n 1)"
  else
    warn 'eww no está instalado'
  fi
  [[ -f "$CONFIG_ROOT/eww.yuck" && -f "$CONFIG_ROOT/eww.scss" ]] && ok "configuración dashboard: $CONFIG_ROOT" || warn 'configuración EWW ausente'
  [[ -x "$WIDGETS_TARGET" ]] && ok "helper widgets: $WIDGETS_TARGET" || warn 'helper widgets ausente'
  [[ -x "$ACTIONS_TARGET" ]] && ok "helper acciones: $ACTIONS_TARGET" || warn 'helper acciones ausente'
  installed playerctl && ok 'playerctl instalado' || warn 'playerctl no está instalado'
  [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG" && ok 'autostart/atajo i3 administrado' || warn 'i3 sin integración EWW'
  [[ -f "$OPENBOX_AUTOSTART" ]] && grep -Fq "$OPENBOX_BEGIN" "$OPENBOX_AUTOSTART" && ok 'autostart Openbox administrado' || warn 'Openbox sin autostart EWW'
  [[ -f "$OPENBOX_RC" ]] && grep -Fq "$OPENBOX_RC_BEGIN" "$OPENBOX_RC" && ok 'atajo Openbox administrado' || warn 'Openbox sin atajo EWW'
  if [[ -n "${DISPLAY:-}" && -x "$TARGET" ]]; then
    "$TARGET" ping >/dev/null 2>&1 && ok 'daemon EWW responde' || info 'daemon EWW detenido'
  else
    info 'sin DISPLAY o binario; no se intenta iniciar EWW'
  fi
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo "═══ Comprobación EWW ${VERSION} ═══"
      local missing=() p
      for p in "${BUILD_PACKAGES[@]}"; do installed "$p" || missing+=("$p"); done
      ((${#missing[@]} == 0)) && ok 'dependencias de compilación y playerctl instaladas' || warn "dependencias pendientes: ${missing[*]}"
      for p in "${BUILD_PACKAGES[@]}"; do installed "$p" || { candidate "$p" || warn "sin candidato APT: $p"; }; done
      show_status
      ;;
    plan)
      echo "═══ Plan EWW ${VERSION} ═══"
      info '[plan] instalar dependencias de compilación y playerctl disponibles mediante APT'
      info "[plan] clonar ${VERSION} bajo $SOURCE_ROOT"
      info '[plan] compilar con --no-default-features --features x11'
      info "[plan] instalar $TARGET, helpers y dashboard en $CONFIG_ROOT"
      info '[plan] integrar autostart y Super+Control+W en i3/Openbox'
      info '[plan] usar windowtype desktop, stacking bg y sin reserve'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      local apt_packages=() p
      for p in "${BUILD_PACKAGES[@]}"; do
        if ! installed "$p"; then candidate "$p" || die "sin candidato APT: $p"; apt_packages+=("$p"); fi
      done
      if ((${#apt_packages[@]})); then sudo -v; sudo apt-get update; sudo apt-get install -y "${apt_packages[@]}"; fi
      command -v git >/dev/null 2>&1 || die 'falta git'
      command -v cargo >/dev/null 2>&1 || die 'falta cargo'
      mkdir -p -- "$(dirname -- "$SOURCE_ROOT")" "$HOME/.local/bin"
      if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
        git clone --branch "$VERSION" --depth 1 https://github.com/elkowar/eww.git "$SOURCE_ROOT"
      fi
      prepare_lockfile
      (cd "$SOURCE_ROOT" && cargo build --release --no-default-features --features x11)
      [[ -x "$SOURCE_ROOT/target/release/eww" ]] || die 'la compilación no produjo target/release/eww'
      if [[ -e "$TARGET" ]] && ! cmp -s "$SOURCE_ROOT/target/release/eww" "$TARGET"; then backup "$TARGET"; fi
      install -m 0755 -- "$SOURCE_ROOT/target/release/eww" "$TARGET"
      install_helpers
      write_config
      configure_integrations
      if [[ -n "${DISPLAY:-}" ]]; then
        "$WIDGETS_TARGET" --reload || warn 'no se pudo recargar la ventana EWW existente; prueba eww-widgets --reload desde la sesión gráfica'
      fi
      ok "EWW ${VERSION} instalado; usa eww-widgets --open dashboard o Super+Control+W"
      ;;
    status) show_status ;;
  esac
}

main "$@"
