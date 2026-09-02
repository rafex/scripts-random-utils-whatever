#!/usr/bin/env bash
# install_i3lock_color_linux.sh v1.2.2
# Compila i3lock-color y lo activa mediante el wrapper del perfil.
# shellcheck disable=SC2015
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

ACTION=check
VERSION="2.12.c.5"
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_ROOT="$HOME/.local/share/rafex/i3lock-color/${VERSION}-src"
TARGET="$HOME/.local/bin/i3lock-color"
WRAPPER_SOURCE="$REPO_ROOT/scripts/system/lock_screen_linux.sh"
WRAPPER_TARGET="$HOME/.local/bin/lock-screen.sh"
I3_CONFIG="${I3LOCK_COLOR_I3_CONFIG:-$HOME/.config/i3/config}"
OPENBOX_RC="${I3LOCK_COLOR_OPENBOX_RC:-$HOME/.config/openbox/rc.xml}"
OPENBOX_AUTOSTART="${I3LOCK_COLOR_OPENBOX_AUTOSTART:-$HOME/.config/openbox/autostart}"

BUILD_PACKAGES=(git autoconf gcc make pkg-config libpam0g-dev libcairo2-dev
  libfontconfig1-dev libxcb-composite0-dev libev-dev libx11-xcb-dev libxcb-xkb-dev
  libxcb-xinerama0-dev libxcb-randr0-dev libxcb-image0-dev libxcb-util-dev
  libxcb-xrm-dev libxkbcommon-dev libxkbcommon-x11-dev libjpeg-dev libgif-dev)
RUNTIME_PACKAGES=(imagemagick x11-utils)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --check) ACTION=check;;
    --plan|--dry-run) ACTION=plan;;
    --apply) ACTION=apply;;
    --status) ACTION=status;;
    --help|-h) printf 'Uso: install_i3lock_color_linux.sh --check|--plan|--apply|--status\n'; exit 0;;
    *) die "opción desconocida: $1";;
  esac
  shift
done

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

has_legacy_i3_lock_binding() {
  [[ -f "$I3_CONFIG" ]] || return 1
  awk -v begin='# BEGIN rafex i3lock-color' -v end='# END rafex i3lock-color' \
    -v legacy_prefix='bindsym $mod+Shift+l exec --no-startup-id ' '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function is_legacy_lock_binding(line, clean) {
      clean=trim(line)
      if (index(clean, legacy_prefix) != 1) return 0
      clean=substr(clean, length(legacy_prefix) + 1)
      return index(clean, "~/.local/bin/lock-screen.sh") == 1 ||
        index(clean, "$HOME/.local/bin/lock-screen.sh") == 1 ||
        index(clean, "i3lock") == 1
    }
    $0 == begin { inside=1; next }
    $0 == end { inside=0; next }
    !inside && is_legacy_lock_binding($0) { found=1 }
    END { exit found ? 0 : 1 }
  ' "$I3_CONFIG"
}

show_status() {
  echo "═══ i3lock-color ${VERSION} ═══"
  [[ -x "$TARGET" ]] && ok "binario paralelo presente: $TARGET" || warn 'i3lock-color no está instalado'
  if command -v i3lock >/dev/null 2>&1; then ok "i3lock oficial se conserva: $(command -v i3lock)"; fi
  [[ -x "$WRAPPER_TARGET" ]] && ok "wrapper lock-screen presente: $WRAPPER_TARGET" || warn "wrapper lock-screen ausente: $WRAPPER_TARGET"
  local legacy_i3_binding=0
  has_legacy_i3_lock_binding && legacy_i3_binding=1 || true
  if [[ -f "$I3_CONFIG" ]] &&
    grep -Fq -- 'exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.local/bin/lock-screen.sh --mode image' "$I3_CONFIG" &&
    grep -Fq -- "bindsym \$mod+Shift+l exec --no-startup-id ~/.local/bin/lock-screen.sh --mode image" "$I3_CONFIG" &&
    ((legacy_i3_binding == 0)); then
    ok 'i3 usa el wrapper i3lock-color en modo imagen para el atajo y xss-lock'
  elif ((legacy_i3_binding)); then
    warn 'i3 conserva un binding legacy de Super+Shift+L; ejecuta --apply para eliminar el duplicado'
  else
    warn 'i3 todavía no usa el modo imagen del wrapper'
  fi
  if [[ -f "$OPENBOX_AUTOSTART" ]] &&
    grep -Fq -- "xss-lock --transfer-sleep-lock -- \"\$HOME/.local/bin/lock-screen.sh\" --mode image &" "$OPENBOX_AUTOSTART"; then
    ok 'Openbox usa el wrapper i3lock-color en modo imagen mediante xss-lock'
  else
    info 'Openbox no tiene autoinicio administrado por i3lock-color'
  fi
  info 'i3lock oficial se conserva únicamente como respaldo'
}

replace_i3_lock_block() {
  local begin='# BEGIN rafex i3lock-color' end='# END rafex i3lock-color'
  local temporary block_file
  [[ "$ACTION" == plan ]] && { info "[plan] activar i3lock-color en $I3_CONFIG"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$I3_CONFIG")"
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex i3lock-color
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.local/bin/lock-screen.sh --mode image
bindsym $mod+Shift+l exec --no-startup-id ~/.local/bin/lock-screen.sh --mode image
# END rafex i3lock-color
EOF
  temporary="$(mktemp)"
  if [[ -f "$I3_CONFIG" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" -v legacy_xss='exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork' -v legacy_binding='bindsym $mod+Shift+l exec --no-startup-id i3lock -c 000000' \
      -v legacy_prefix='bindsym $mod+Shift+l exec --no-startup-id ' '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      function is_legacy_lock_binding(line, clean) {
        clean=trim(line)
        if (index(clean, legacy_prefix) != 1) return 0
        clean=substr(clean, length(legacy_prefix) + 1)
        return index(clean, "~/.local/bin/lock-screen.sh") == 1 ||
          index(clean, "$HOME/.local/bin/lock-screen.sh") == 1 ||
          index(clean, "i3lock") == 1
      }
      function emit(line) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
      $0 == begin { emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      # Skip the previous managed block after emitting its canonical version.
      inside { next }
      !inside && ($0 == legacy_xss || $0 == legacy_binding) { next }
      # Remove only old Super+Shift+L lock bindings; preserve every other user binding.
      !inside && is_legacy_lock_binding($0) { next }
      { print }
      END { if (!found) { print ""; emit() } }
    ' "$I3_CONFIG" > "$temporary"
  else
    awk -v block_file="$block_file" 'function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) } BEGIN { emit() }' > "$temporary"
  fi
  if [[ -f "$I3_CONFIG" ]] && cmp -s "$I3_CONFIG" "$temporary"; then
    rm -f -- "$block_file" "$temporary"
    return 0
  fi
  backup "$I3_CONFIG"
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$I3_CONFIG"
  rm -f -- "$block_file"
  ok "i3 configurado para usar i3lock-color: $I3_CONFIG"
}

replace_openbox_autostart() {
  local begin='# BEGIN rafex i3lock-color' end='# END rafex i3lock-color'
  local temporary block_file
  [[ "$ACTION" == plan ]] && { info "[plan] activar xss-lock con i3lock-color en $OPENBOX_AUTOSTART"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p "$(dirname -- "$OPENBOX_AUTOSTART")"
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# BEGIN rafex i3lock-color
if [ -x "$HOME/.local/bin/lock-screen.sh" ] && command -v xss-lock >/dev/null 2>&1; then
    xss-lock --transfer-sleep-lock -- "$HOME/.local/bin/lock-screen.sh" --mode image &
fi
# END rafex i3lock-color
EOF
  temporary="$(mktemp)"
  if [[ -f "$OPENBOX_AUTOSTART" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      function emit(line) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
      trim($0) == begin { emit(); inside=1; found=1; next }
      inside && trim($0) == end { inside=0; next }
      !inside && $0 ~ /^[[:space:]]*if command -v xss-lock[[:space:]]+.*&& command -v i3lock[[:space:]]+.*; then[[:space:]]*$/ { legacy=1; next }
      legacy && $0 ~ /^[[:space:]]*xss-lock[[:space:]]+--transfer-sleep-lock[[:space:]]+--[[:space:]]+i3lock[[:space:]]+--nofork[[:space:]]*&[[:space:]]*$/ { next }
      legacy && $0 ~ /^[[:space:]]*fi[[:space:]]*$/ { legacy=0; next }
      { print }
      END { if (!found) { print ""; emit() } }
    ' "$OPENBOX_AUTOSTART" > "$temporary"
  else
    awk -v block_file="$block_file" 'function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) } BEGIN { emit() }' > "$temporary"
  fi
  if [[ -f "$OPENBOX_AUTOSTART" ]] && cmp -s "$OPENBOX_AUTOSTART" "$temporary"; then
    rm -f -- "$block_file" "$temporary"
    return 0
  fi
  backup "$OPENBOX_AUTOSTART"
  chmod 0755 "$temporary"
  mv -f -- "$temporary" "$OPENBOX_AUTOSTART"
  rm -f -- "$block_file"
  ok "Openbox configurado para usar i3lock-color: $OPENBOX_AUTOSTART"
}

replace_openbox_keybind() {
  local begin='<!-- BEGIN rafex i3lock-color -->' end='<!-- END rafex i3lock-color -->'
  local temporary block_file
  [[ "$ACTION" == plan ]] && { info "[plan] añadir atajo de bloqueo i3lock-color en $OPENBOX_RC"; return 0; }
  [[ "$ACTION" == apply ]] || return 0
  [[ -f "$OPENBOX_RC" ]] || return 0
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
    <!-- BEGIN rafex i3lock-color -->
    <keybind key="W-Shift-l"><action name="Execute"><command>~/.local/bin/lock-screen.sh --mode image</command></action></keybind>
    <!-- END rafex i3lock-color -->
EOF
  temporary="$(mktemp)"
  if ! awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function emit(line) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }
    trim($0) == begin { inside=1; found=1; next }
    inside && trim($0) == end { inside=0; next }
    trim($0) == "</keyboard>" && !inserted { emit(); inserted=1 }
    { print }
    END { if (!inserted) exit 42 }
  ' "$OPENBOX_RC" > "$temporary"; then
    rm -f -- "$block_file" "$temporary"
    warn "no se encontró </keyboard> en $OPENBOX_RC; se omitió el atajo de Openbox"
    return 0
  fi
  if [[ -f "$OPENBOX_RC" ]] && cmp -s "$OPENBOX_RC" "$temporary"; then
    rm -f -- "$block_file" "$temporary"
    return 0
  fi
  backup "$OPENBOX_RC"
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$OPENBOX_RC"
  rm -f -- "$block_file"
  ok "atajo Openbox configurado para usar i3lock-color: $OPENBOX_RC"
}

main() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo "═══ Comprobación i3lock-color ${VERSION} ═══"
      local p missing=()
      for p in "${BUILD_PACKAGES[@]}" "${RUNTIME_PACKAGES[@]}"; do installed "$p" || missing+=("$p"); done
      ((${#missing[@]} == 0)) && ok 'dependencias de compilación y runtime instaladas' || warn "dependencias pendientes: ${missing[*]}"
      show_status
      ;;
    plan)
      echo "═══ Plan i3lock-color ${VERSION} ═══"
      info '[plan] instalar dependencias de compilación y runtime disponibles mediante APT'
      info "[plan] clonar tag ${VERSION} bajo $SOURCE_ROOT"
      info '[plan] compilar con el método oficial del proyecto'
      info "[plan] instalar $TARGET y activar el wrapper en i3/Openbox mediante xss-lock"
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      local apt_packages=() p
      for p in "${BUILD_PACKAGES[@]}" "${RUNTIME_PACKAGES[@]}"; do
        if ! installed "$p"; then candidate "$p" || die "sin candidato APT: $p"; apt_packages+=("$p"); fi
      done
      if ((${#apt_packages[@]})); then sudo -v; sudo apt-get update; sudo apt-get install -y "${apt_packages[@]}"; fi
      mkdir -p -- "$(dirname -- "$SOURCE_ROOT")" "$HOME/.local/bin"
      if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
        git clone --branch "$VERSION" --depth 1 https://github.com/Raymo111/i3lock-color.git "$SOURCE_ROOT"
      fi
      (cd "$SOURCE_ROOT" && ./build.sh)
      local built=''
      if [[ -x "$SOURCE_ROOT/i3lock" ]]; then built="$SOURCE_ROOT/i3lock"; else built="$(find "$SOURCE_ROOT" -maxdepth 3 -type f -name i3lock -perm -u+x -print -quit)"; fi
      [[ -n "$built" ]] || die 'la compilación no produjo un binario i3lock'
      [[ ! -e "$TARGET" || ! -L "$TARGET" ]] || die "el destino no puede ser enlace simbólico: $TARGET"
      [[ -e "$TARGET" ]] && ! cmp -s "$built" "$TARGET" && backup "$TARGET"
      install -m 0755 -- "$built" "$TARGET"
      [[ -f "$WRAPPER_SOURCE" ]] || die "falta $WRAPPER_SOURCE"
      if [[ -e "$WRAPPER_TARGET" ]] && ! cmp -s "$WRAPPER_SOURCE" "$WRAPPER_TARGET"; then backup "$WRAPPER_TARGET"; fi
      install -m 0755 -- "$WRAPPER_SOURCE" "$WRAPPER_TARGET"
      replace_i3_lock_block
      replace_openbox_autostart
      replace_openbox_keybind
      ok "i3lock-color instalado y activado: $TARGET"
      ;;
    status) show_status;;
  esac
}

main "$@"
