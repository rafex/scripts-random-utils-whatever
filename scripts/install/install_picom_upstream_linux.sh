#!/usr/bin/env bash
# v1.0.1 — Compila Picom v13 upstream en el espacio del usuario.
set -Eeuo pipefail
umask 077

ACTION=check
VERSION=v13
EXPECTED_COMMIT=d87a5ba3af7a9ee3c4e040ee29b2dea7e9e46317
REPO_URL=https://github.com/yshui/picom.git
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/rafex/picom"
SOURCE_DIR="$DATA_ROOT/v13-src"
BUILD_DIR="$SOURCE_DIR/build"
BIN_TARGET="$HOME/.local/bin/picom"
CONFIG_SOURCE="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/picom.conf"
CONFIG_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/picom/picom.conf"
chosen=false

BUILD_PACKAGES=(
  build-essential git meson ninja-build pkg-config
  libconfig-dev libdbus-1-dev libegl-dev libev-dev libgl-dev
  libepoxy-dev libpcre2-dev libpixman-1-dev libx11-dev libx11-xcb-dev
  libxcb1-dev libxcb-composite0-dev libxcb-damage0-dev libxcb-glx0-dev
  libxcb-image0-dev libxcb-present-dev libxcb-randr0-dev
  libxcb-render0-dev libxcb-render-util0-dev libxcb-shape0-dev
  libxcb-util-dev libxcb-xfixes0-dev uthash-dev
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_picom_upstream_linux.sh --check|--plan|--apply|--status

Opciones:
  --check       comprobar Debian, dependencias y rutas sin modificar (default)
  --plan        mostrar compilación, binario y configuración previstos
  --apply       instalar dependencias, compilar v13 e instalar en ~/.local
  --status      mostrar versiones y configuración local
  --help        mostrar esta ayuda
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--apply|--status)
        [[ "$chosen" == false ]] || die 'Selecciona una sola acción'
        ACTION=${1#--}; chosen=true ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_base() {
  [[ "$(uname -s)" == Linux ]] || die 'Este instalador requiere Linux'
  (( EUID != 0 )) || die 'Ejecuta como usuario normal, no como root'
  [[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
  [[ -f "$CONFIG_SOURCE" ]] || die "falta configuración versionada: $CONFIG_SOURCE"
  for command_name in git meson ninja pkg-config; do
    command -v "$command_name" >/dev/null 2>&1 || warn "falta herramienta: $command_name"
  done
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

show_missing_packages() {
  local package_name missing=()
  for package_name in "${BUILD_PACKAGES[@]}"; do
    package_installed "$package_name" || missing+=("$package_name")
  done
  if ((${#missing[@]})); then
    printf '%s\n' "${missing[*]}"
  else
    printf '%s\n' '(ninguna)'
  fi
}

show_status() {
  printf '═══ Picom upstream v13 ═══\n'
  if [[ -x "$BIN_TARGET" ]]; then
    printf 'usuario: %s — ' "$BIN_TARGET"
    "$BIN_TARGET" --version || true
  else
    printf 'usuario: no instalado (%s)\n' "$BIN_TARGET"
  fi
  if command -v picom >/dev/null 2>&1; then
    printf 'PATH: %s — ' "$(command -v picom)"
    picom --version || true
  else
    printf '%s\n' 'PATH: picom no encontrado'
  fi
  printf 'fuentes: %s\n' "$SOURCE_DIR"
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    printf 'commit: %s\n' "$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
  fi
  printf 'config: %s\n' "$CONFIG_TARGET"
  if [[ -f "$CONFIG_TARGET" ]]; then
    grep -qF '# Managed by rafex install_picom_upstream_linux.sh' "$CONFIG_TARGET" \
      && printf '%s\n' 'configuración: administrada por Rafex' \
      || printf '%s\n' 'configuración: presente, origen no clasificado'
  fi
}

show_plan() {
  printf '═══ Plan Picom upstream v13 ═══\n'
  printf 'fuente oficial: %s (%s, commit %s)\n' "$REPO_URL" "$VERSION" "$EXPECTED_COMMIT"
  printf 'compilación: %s\n' "$BUILD_DIR"
  printf 'binario: %s\n' "$BIN_TARGET"
  printf 'configuración: %s\n' "$CONFIG_TARGET"
  printf 'dependencias APT faltantes: %s\n' "$(show_missing_packages)"
  printf '%s\n' 'No iniciará Picom, no cambiará i3/Openbox y no ejecutará sudo fuera de APT.'
}

prepare_source() {
  mkdir -p -- "$DATA_ROOT"
  if [[ -e "$SOURCE_DIR" ]]; then
    [[ -d "$SOURCE_DIR/.git" ]] || die "la ruta de fuentes no es un repositorio Git: $SOURCE_DIR"
    [[ "$(git -C "$SOURCE_DIR" config --get remote.origin.url)" == "$REPO_URL" ]] \
      || die 'el origen Git de las fuentes no coincide con yshui/picom'
    [[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ]] || die 'las fuentes tienen cambios locales'
    git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$VERSION"
    git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
  else
    git clone --branch "$VERSION" --depth 1 "$REPO_URL" "$SOURCE_DIR"
  fi
  local commit
  commit=$(git -C "$SOURCE_DIR" rev-parse HEAD)
  [[ "$commit" == "$EXPECTED_COMMIT" ]] || die "commit inesperado para $VERSION: $commit"
  ok "fuentes verificadas: $VERSION ($EXPECTED_COMMIT)"
}

build_picom() {
  if [[ -d "$BUILD_DIR" ]]; then
    meson setup --reconfigure "$BUILD_DIR" \
      --buildtype=release --prefix="$HOME/.local" \
      -Ddbus=true -Dopengl=true -Dregex=true -Dcompton=true -Dwith_docs=false
  else
    meson setup "$BUILD_DIR" \
      --buildtype=release --prefix="$HOME/.local" \
      -Ddbus=true -Dopengl=true -Dregex=true -Dcompton=true -Dwith_docs=false
  fi
  ninja -C "$BUILD_DIR"
  [[ -x "$BUILD_DIR/src/picom" ]] || die 'la compilación no produjo build/src/picom'
  [[ "$("$BUILD_DIR/src/picom" --version)" == "$VERSION" ]] \
    || die "la versión compilada no es $VERSION"
}

backup_file() {
  local source="$1"
  [[ -e "$source" ]] || return 0
  cp -p -- "$source" "$source.bak.$STAMP"
  info "respaldo: $source.bak.$STAMP"
}

install_results() {
  local temporary='' config_temporary='' bin_backup config_backup
  local had_bin=false had_config=false
  mkdir -p -- "${BIN_TARGET%/*}" "${CONFIG_TARGET%/*}"
  if [[ -e "$BIN_TARGET" ]]; then
    backup_file "$BIN_TARGET"
    bin_backup="$BIN_TARGET.bak.$STAMP"
    had_bin=true
  fi
  if [[ -e "$CONFIG_TARGET" ]]; then
    backup_file "$CONFIG_TARGET"
    config_backup="$CONFIG_TARGET.bak.$STAMP"
    had_config=true
  fi

  restore_install() {
    local status="$1"
    set +e
    [[ -z "$temporary" ]] || rm -f -- "$temporary"
    [[ -z "$config_temporary" ]] || rm -f -- "$config_temporary"
    if [[ "$had_bin" == true && -e "$bin_backup" ]]; then
      mv -f -- "$bin_backup" "$BIN_TARGET"
    else
      rm -f -- "$BIN_TARGET"
    fi
    if [[ "$had_config" == true && -e "$config_backup" ]]; then
      mv -f -- "$config_backup" "$CONFIG_TARGET"
    else
      rm -f -- "$CONFIG_TARGET"
    fi
    trap - ERR
    printf '✗ ERROR: la instalación quedó sin cambios; se restauraron los destinos previos.\n' >&2
    exit "$status"
  }

  trap 'restore_install "$?"' ERR
  temporary=$(mktemp "${BIN_TARGET%/*}/.picom.XXXXXX")
  config_temporary=$(mktemp "${CONFIG_TARGET%/*}/.picom.conf.XXXXXX")
  install -m 0755 -- "$BUILD_DIR/src/picom" "$temporary"
  install -m 0644 -- "$CONFIG_SOURCE" "$config_temporary"
  [[ "$("$temporary" --version)" == "$VERSION" ]] || die 'el binario compilado no supera la validación'
  grep -qF '# Managed by rafex install_picom_upstream_linux.sh' "$config_temporary" \
    || die 'la configuración fuente no contiene su marcador'
  mv -f -- "$temporary" "$BIN_TARGET"
  mv -f -- "$config_temporary" "$CONFIG_TARGET"
  trap - ERR
  ok "Picom $VERSION instalado en $BIN_TARGET"
  ok "configuración visual instalada en $CONFIG_TARGET"
  info 'Picom no se inició automáticamente; reinícialo solo después de revisar el resultado.'
}

main() {
  parse_args "$@"
  require_base
  case "$ACTION" in
    status) show_status ;;
    plan) show_plan ;;
    check)
      show_plan
      if command -v dpkg-query >/dev/null 2>&1; then
        ok 'entorno Debian consultable'
      else
        warn 'dpkg-query no está disponible; no se puede comprobar APT'
      fi
      ;;
    apply)
      command -v dpkg-query >/dev/null 2>&1 || die 'requiere Debian con dpkg-query'
      local missing
      missing=$(show_missing_packages)
      if [[ "$missing" != '(ninguna)' ]]; then
        command -v sudo >/dev/null 2>&1 || die 'falta sudo para dependencias de compilación'
        sudo -v
        sudo apt-get update
        # shellcheck disable=SC2086
        sudo apt-get install -y $missing
      fi
      prepare_source
      build_picom
      install_results
      ;;
  esac
}

main "$@"
