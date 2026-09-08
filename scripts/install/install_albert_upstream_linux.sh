#!/usr/bin/env bash
# v1.0.1 — Compila Albert v35.1.0 upstream en el espacio del usuario.
#
# Alternativa a install_albert_linux.sh (repositorio OBS): en el momento de
# escribir este script, la build de Albert publicada en OBS para
# Debian_Unstable pide libstdc++6 >= 16.2.0-2 y Debian sid todavía solo
# ofrece 16.2.0-1 (desfase temporal de paquetes). Compilar aquí mismo evita
# ese problema por completo: el binario queda enlazado contra el
# libstdc++6 que realmente está instalado en esta máquina, no el que asume
# el entorno de build de OBS.
set -Eeuo pipefail
umask 077

ACTION=check
VERSION=v35.1.0
EXPECTED_COMMIT=21d0b78dafc53d3ea9aebd139b26bf1ae8ea115b
REPO_URL=https://github.com/albertlauncher/albert.git
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/rafex/albert"
SOURCE_DIR="$DATA_ROOT/$VERSION-src"
BUILD_DIR="$SOURCE_DIR/build"
INSTALL_PREFIX="$HOME/.local"
BIN_TARGET="$INSTALL_PREFIX/bin/albert"
chosen=false

# Mismo paquete de dependencias que el Dockerfile de CI oficial
# (.docker/ubuntu.Dockerfile en albertlauncher/albert), con los dos únicos
# nombres que difieren en Debian: qt6-svg-dev (no libqt6svg6-dev) y sin
# libqt6opengl6-dev, que en Debian ya viene provisto por qt6-base-dev.
# Verificado en vivo con `apt-get install -s` en esta ThinkPad.
BUILD_PACKAGES=(
  git cmake g++ make ninja-build pkg-config
  libarchive-dev libgl1-mesa-dev libglvnd-dev
  libqalculate-dev qt6-base-dev libqt6sql6-sqlite qt6-svg-dev
  libxml2-utils python3-dev
  qt6-scxml-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools
  qtkeychain-qt6-dev qcoro-qt6-dev
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_albert_upstream_linux.sh --check|--plan|--apply|--status

Opciones:
  --check         comprobar Debian, dependencias y rutas sin modificar (default)
  --plan          mostrar compilación y binario previstos
  --apply         instalar dependencias, compilar v35.1.0 e instalar en ~/.local
  --status        mostrar versión y commit sin modificar
  --help          mostrar esta ayuda

La contraseña de sudo se solicita únicamente mediante `sudo -v`, y solo si
faltan dependencias de compilación por instalar vía APT.
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
  printf '═══ Albert upstream %s ═══\n' "$VERSION"
  if [[ -x "$BIN_TARGET" ]]; then
    printf 'usuario: %s — ' "$BIN_TARGET"
    "$BIN_TARGET" --version 2>&1 || true
  else
    printf 'usuario: no instalado (%s)\n' "$BIN_TARGET"
  fi
  if command -v albert >/dev/null 2>&1; then
    printf 'PATH: %s\n' "$(command -v albert)"
  else
    printf '%s\n' 'PATH: albert no encontrado'
  fi
  printf 'fuentes: %s\n' "$SOURCE_DIR"
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    printf 'commit: %s\n' "$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
  fi
  printf '%s\n' 'i3: sin integración; Ulauncher es el launcher administrado'
  if package_installed albert; then
    warn "el paquete albert de APT también está instalado; ~/.local/bin suele ir antes en \$PATH"
  fi
}

show_plan() {
  printf '═══ Plan Albert upstream %s ═══\n' "$VERSION"
  printf 'fuente oficial: %s (%s, commit %s)\n' "$REPO_URL" "$VERSION" "$EXPECTED_COMMIT"
  printf 'compilación: %s\n' "$BUILD_DIR"
  printf 'instalación: cmake --install (prefix %s)\n' "$INSTALL_PREFIX"
  printf 'binario: %s\n' "$BIN_TARGET"
  printf 'dependencias APT faltantes: %s\n' "$(show_missing_packages)"
  printf '%s\n' "No iniciará Albert, no tocará la configuración de i3 ni \$mod+space y no ejecutará sudo fuera de APT."
}

prepare_source() {
  mkdir -p -- "$DATA_ROOT"
  if [[ -e "$SOURCE_DIR" ]]; then
    [[ -d "$SOURCE_DIR/.git" ]] || die "la ruta de fuentes no es un repositorio Git: $SOURCE_DIR"
    [[ "$(git -C "$SOURCE_DIR" config --get remote.origin.url)" == "$REPO_URL" ]] \
      || die 'el origen Git de las fuentes no coincide con albertlauncher/albert'
    [[ -z "$(git -C "$SOURCE_DIR" status --porcelain --ignore-submodules=all)" ]] \
      || die 'las fuentes tienen cambios locales'
    git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$VERSION"
    git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
  else
    git clone --branch "$VERSION" --depth 1 "$REPO_URL" "$SOURCE_DIR"
  fi
  local commit
  commit=$(git -C "$SOURCE_DIR" rev-parse HEAD)
  [[ "$commit" == "$EXPECTED_COMMIT" ]] || die "commit inesperado para $VERSION: $commit"
  info 'sincronizando submódulos (i18n, lib/QHotkey, lib/QNotification, plugins/*)'
  git -C "$SOURCE_DIR" submodule update --init --recursive --depth 1
  ok "fuentes verificadas: $VERSION ($EXPECTED_COMMIT)"
}

build_albert() {
  cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
  cmake --build "$BUILD_DIR" -j"$(nproc)"
  [[ -x "$BUILD_DIR/bin/albert" ]] || die 'la compilación no produjo build/bin/albert'
}

install_albert() {
  cmake --install "$BUILD_DIR"
  [[ -x "$BIN_TARGET" ]] || die "la instalación no produjo $BIN_TARGET"
  ok "Albert $VERSION instalado en $BIN_TARGET"
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
      build_albert
      install_albert
      ;;
  esac
}

main "$@"
