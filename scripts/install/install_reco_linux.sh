#!/usr/bin/env bash
# install_reco_linux.sh v1.0.0
# Descarga, compila e instala Reco desde el repositorio oficial en ~/.local.
set -Eeuo pipefail
umask 077
export PATH="${PATH:-}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ACTION=check
readonly REPO_URL='https://github.com/ryonakano/reco.git'
readonly BRANCH='main'
readonly REPO_DIR="${RECO_SOURCE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/src/reco}"
readonly PREFIX="${RECO_PREFIX:-$HOME/.local}"
readonly BUILD_DIR="$REPO_DIR/builddir"
readonly APP_ID='com.github.ryonakano.reco'
readonly -a PACKAGES=(
  blueprint-compiler build-essential ca-certificates gettext git ninja-build
  libadwaita-1-dev libgee-0.8-dev libglib2.0-dev
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgtk-4-dev
  meson pkg-config valac gstreamer1.0-libav gstreamer1.0-plugins-good
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_reco_linux.sh --check|--plan|--apply|--update|--status

Compila Reco desde https://github.com/ryonakano/reco y lo instala en ~/.local.
Meson descarga las dependencias fuente libryokucha y live-chart usando los
wraps fijados por el repositorio de Reco.

Opciones:
  --check       Revisar plataforma, herramientas y estado sin modificar nada
  --plan        Mostrar las acciones de instalación o actualización
  --apply       Descargar (o sincronizar) main, compilar e instalar Reco
  --update      Avanzar el checkout local de forma segura y recompilar
  --status      Mostrar commit del código y disponibilidad del ejecutable
  --help, -h    Mostrar esta ayuda

--apply y --update instalan dependencias Debian mediante sudo APT. Reco y su
escritorio se instalan sin privilegios en el prefijo de usuario ~/.local.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --update) ACTION=update ;;
      --status) ACTION=status ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux.'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución.'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}."
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get.'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query.'
  if [[ "$ACTION" == apply || "$ACTION" == update ]]; then
    [[ "$EUID" -ne 0 ]] || die 'ejecuta el instalador como usuario normal.'
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para instalar las dependencias Debian.'
  fi
}

is_package_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" == 'install ok installed' ]]
}

check_packages() {
  local package missing=0
  for package in "${PACKAGES[@]}"; do
    if is_package_installed "$package"; then
      printf '✓ %s\n' "$package"
    else
      printf '✗ %s (faltante)\n' "$package"
      missing=1
    fi
  done
  return "$missing"
}

source_checkout_exists() {
  [[ -d "$REPO_DIR/.git" ]]
}

check_checkout_clean() {
  git -C "$REPO_DIR" diff --quiet --ignore-submodules -- ||
    die "hay cambios rastreados sin guardar en $REPO_DIR; guárdalos antes de actualizar."
  git -C "$REPO_DIR" diff --cached --quiet --ignore-submodules -- ||
    die "hay cambios preparados en $REPO_DIR; guárdalos antes de actualizar."
}

install_dependencies() {
  info 'actualizando índices APT e instalando dependencias de compilación y ejecución.'
  sudo -v
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${PACKAGES[@]}"
}

sync_source() {
  if source_checkout_exists; then
    check_checkout_clean
    info "actualizando $REPO_DIR desde origin/$BRANCH con fast-forward."
    git -C "$REPO_DIR" fetch --prune origin "$BRANCH"
    git -C "$REPO_DIR" merge --ff-only "origin/$BRANCH"
  else
    if [[ -e "$REPO_DIR" ]]; then
      die "$REPO_DIR existe pero no es un checkout Git de Reco; muévelo o indica RECO_SOURCE_DIR."
    fi
    mkdir -p -- "$(dirname -- "$REPO_DIR")"
    info "clonando la rama $BRANCH del repositorio oficial de Reco."
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
  fi
  [[ "$(git -C "$REPO_DIR" remote get-url origin)" == "$REPO_URL" ]] ||
    die "el checkout tiene un remoto inesperado; esperado: $REPO_URL."
  [[ "$(git -C "$REPO_DIR" branch --show-current)" == "$BRANCH" ]] ||
    die "el checkout no está en la rama $BRANCH; no se cambiará de rama automáticamente."
}

build_install() {
  mkdir -p -- "$PREFIX"
  if [[ -f "$BUILD_DIR/meson-private/coredata.dat" ]]; then
    meson configure "$BUILD_DIR" --prefix="$PREFIX" -Dgranite=disabled -Duse_submodule=true
  else
    meson setup "$BUILD_DIR" --prefix="$PREFIX" -Dgranite=disabled -Duse_submodule=true
  fi
  meson compile -C "$BUILD_DIR"
  meson install -C "$BUILD_DIR"
  ok "Reco compilado e instalado en $PREFIX."
}

show_check() {
  printf '═══ Reco desde código fuente ═══\n'
  printf 'repositorio=%s\nprefijo=%s\n' "$REPO_DIR" "$PREFIX"
  if check_packages; then ok 'dependencias Debian completas.'; else warn 'faltan dependencias; --apply las instalará.'; fi
  if source_checkout_exists; then
    printf 'commit=%s\n' "$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    printf 'remoto=%s\n' "$(git -C "$REPO_DIR" remote get-url origin)"
  else
    warn 'el repositorio de Reco todavía no está clonado.'
  fi
  if [[ -x "$PREFIX/bin/$APP_ID" ]]; then
    ok "ejecutable disponible: $PREFIX/bin/$APP_ID"
  else
    warn 'Reco no está instalado en el prefijo configurado.'
  fi
}

show_status() {
  if source_checkout_exists; then
    printf 'commit=%s\n' "$(git -C "$REPO_DIR" log -1 --format='%h %s (%cI)')"
    printf 'rama=%s\n' "$(git -C "$REPO_DIR" branch --show-current)"
  else
    printf 'código_fuente=ausente (%s)\n' "$REPO_DIR"
  fi
  if [[ -x "$PREFIX/bin/$APP_ID" ]]; then
    printf 'ejecutable=%s\n' "$PREFIX/bin/$APP_ID"
  else
    printf 'ejecutable=ausente\n'
    return 1
  fi
  if [[ -f "$PREFIX/share/applications/$APP_ID.desktop" ]]; then
    printf 'lanzador=%s/share/applications/%s.desktop\n' "$PREFIX" "$APP_ID"
  else
    warn 'no se encontró el lanzador de escritorio en el prefijo.'
  fi
}

main() {
  parse_args "$@"
  require_linux_debian
  case "$ACTION" in
    check) show_check ;;
    status) show_status ;;
    plan)
      info "instalar dependencias Debian: ${PACKAGES[*]}"
      info "clonar o actualizar $REPO_URL (rama $BRANCH) en $REPO_DIR"
      info "compilar con Meson y publicar el ejecutable y lanzador en $PREFIX"
      info 'usa --update para traer cambios posteriores de main con fast-forward.'
      info 'no se modificará ningún archivo en modo plan.'
      ;;
    apply|update)
      install_dependencies
      sync_source
      build_install
      ok "ejecuta Reco con: $APP_ID"
      ;;
  esac
}

main "$@"
