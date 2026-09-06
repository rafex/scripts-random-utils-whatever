#!/usr/bin/env bash
# v1.0.0 — Compila Albert v35.1.0 upstream en el espacio del usuario.
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
I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
I3_BEGIN='# BEGIN rafex albert'
I3_END='# END rafex albert'
STAMP="$(date +%Y%m%d_%H%M%S)"
CONFIGURE_I3=0
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
  install_albert_upstream_linux.sh --check|--plan|--apply|--status [--i3-shortcut]

Opciones:
  --check         comprobar Debian, dependencias y rutas sin modificar (default)
  --plan          mostrar compilación, binario y atajo de i3 previstos
  --apply         instalar dependencias, compilar v35.1.0 e instalar en ~/.local
  --status        mostrar versión, commit e i3 sin modificar
  --i3-shortcut   junto con --apply, agrega bindsym $mod+a en i3
                  (no toca $mod+space; solo para probar Albert)
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
      --i3-shortcut) CONFIGURE_I3=1 ;;
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
  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG"; then
    printf '%s\n' 'i3: atajo $mod+a configurado'
  else
    printf '%s\n' 'i3: sin atajo de prueba (usa --apply --i3-shortcut)'
  fi
  if package_installed albert; then
    warn 'el paquete albert de APT también está instalado; ~/.local/bin suele ir antes en $PATH'
  fi
}

show_plan() {
  printf '═══ Plan Albert upstream %s ═══\n' "$VERSION"
  printf 'fuente oficial: %s (%s, commit %s)\n' "$REPO_URL" "$VERSION" "$EXPECTED_COMMIT"
  printf 'compilación: %s\n' "$BUILD_DIR"
  printf 'instalación: cmake --install (prefix %s)\n' "$INSTALL_PREFIX"
  printf 'binario: %s\n' "$BIN_TARGET"
  printf 'dependencias APT faltantes: %s\n' "$(show_missing_packages)"
  if [[ "$CONFIGURE_I3" -eq 1 ]]; then
    printf "agregar bindsym \$mod+a (Albert) en %s\n" "$I3_CONFIG"
  fi
  printf '%s\n' 'No iniciará Albert, no tocará $mod+space y no ejecutará sudo fuera de APT.'
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

backup_colocated() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 0
  cp -a -- "$file" "$file.bak.$STAMP"
  info "respaldo: $file.bak.$STAMP"
}

# Parchea (idempotente, con respaldo colocado) un bloque BEGIN/END en un
# archivo ya desplegado -mismo mecanismo que install_albert_linux.sh usa
# para su propio atajo en i3, con las mismas marcas BEGIN/END, así que
# cualquiera de los dos instaladores (OBS o esta compilación) administra el
# mismo bloque sin duplicarlo.
replace_block() {
  local target="$1" begin="$2" end="$3" block_file="$4" temporary
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function emit(line) { while ((getline line < block_file) > 0) print line; close(block_file) }
      $0 == begin { if (!found) emit(); inside=1; found=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
      END { if (!found) { print ""; emit() } }
    ' "$target" > "$temporary"
    if cmp -s "$target" "$temporary"; then
      rm -f -- "$temporary"
      return 0
    fi
    backup_colocated "$target"
    chmod --reference="$target" "$temporary" 2>/dev/null || true
  else
    mkdir -p -- "$(dirname -- "$target")"
    cat "$block_file" > "$temporary"
  fi
  mv -f -- "$temporary" "$target"
}

configure_i3_shortcut() {
  [[ "$CONFIGURE_I3" -eq 1 ]] || return 0
  [[ -f "$I3_CONFIG" ]] || { warn "no se encontró $I3_CONFIG; omitiendo atajo de prueba"; return 0; }
  local block
  block="$(mktemp)"
  cat > "$block" <<EOF
$I3_BEGIN
bindsym \$mod+a exec --no-startup-id $BIN_TARGET show
$I3_END
EOF
  replace_block "$I3_CONFIG" "$I3_BEGIN" "$I3_END" "$block"
  rm -f -- "$block"
  ok "atajo de prueba \$mod+a configurado en $I3_CONFIG (recarga i3 con \$mod+Shift+r)"
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
      configure_i3_shortcut
      ;;
  esac
}

main "$@"
