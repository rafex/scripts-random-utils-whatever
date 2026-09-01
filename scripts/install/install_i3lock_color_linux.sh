#!/usr/bin/env bash
# install_i3lock_color_linux.sh v1.0.0
# Compila i3lock-color en paralelo sin sustituir el i3lock de Debian.
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

BUILD_PACKAGES=(git autoconf gcc make pkg-config libpam0g-dev libcairo2-dev
  libfontconfig1-dev libxcb-composite0-dev libev-dev libx11-xcb-dev libxcb-xkb-dev
  libxcb-xinerama0-dev libxcb-randr0-dev libxcb-image0-dev libxcb-util-dev
  libxcb-xrm-dev libxkbcommon-dev libxkbcommon-x11-dev libjpeg-dev libgif-dev)

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

show_status() {
  echo "═══ i3lock-color ${VERSION} ═══"
  [[ -x "$TARGET" ]] && ok "binario paralelo presente: $TARGET" || warn 'i3lock-color no está instalado'
  if command -v i3lock >/dev/null 2>&1; then ok "i3lock oficial se conserva: $(command -v i3lock)"; fi
  [[ -x "$WRAPPER_TARGET" ]] && ok "wrapper lock-screen presente: $WRAPPER_TARGET" || warn "wrapper lock-screen ausente: $WRAPPER_TARGET"
  info 'xss-lock no se modifica; la sustitución automática requiere una decisión posterior'
}

main() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo "═══ Comprobación i3lock-color ${VERSION} ═══"
      local p missing=()
      for p in "${BUILD_PACKAGES[@]}"; do installed "$p" || missing+=("$p"); done
      ((${#missing[@]} == 0)) && ok 'dependencias de compilación instaladas' || warn "dependencias pendientes: ${missing[*]}"
      show_status
      ;;
    plan)
      echo "═══ Plan i3lock-color ${VERSION} ═══"
      info '[plan] instalar dependencias de compilación disponibles mediante APT'
      info "[plan] clonar tag ${VERSION} bajo $SOURCE_ROOT"
      info '[plan] compilar con el método oficial del proyecto'
      info "[plan] instalar solo $TARGET; no tocar /usr/bin/i3lock ni xss-lock"
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      local apt_packages=() p
      for p in "${BUILD_PACKAGES[@]}"; do
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
      ok "i3lock-color instalado en paralelo: $TARGET"
      ;;
    status) show_status;;
  esac
}

main "$@"
