#!/usr/bin/env bash
# shellcheck shell=bash
#
# Descarga e instala el paquete DEB oficial de RustDesk 1.4.9 para Debian amd64.
# El artefacto se verifica antes de entregarlo a APT y el servicio de acceso
# remoto queda deshabilitado salvo solicitud explícita.
set -Eeuo pipefail
umask 077

ACTION='check'
VERSION='1.4.9'
ARCHITECTURE='amd64'
ENABLE_SERVICE='no'
ASSET_NAME="rustdesk-${VERSION}-x86_64.deb"
DOWNLOAD_URL="https://github.com/rustdesk/rustdesk/releases/download/${VERSION}/${ASSET_NAME}"
EXPECTED_SHA256='7244ba47c40e804172044bfbe659467c54ce46554c98e78c8c0406f1d612fda3'
TEMP_DIR=''

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
  install_rustdesk_linux.sh --check
  install_rustdesk_linux.sh --plan
  install_rustdesk_linux.sh --apply
  install_rustdesk_linux.sh --status

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan|--dry-run       Mostrar el plan sin modificar nada
  --apply                Descargar, verificar e instalar el DEB oficial
  --status               Mostrar instalación y servicio local
  --version <versión>    Solo se admite la release fijada 1.4.9
  --enable-service       Dejar rustdesk.service habilitado y activo (solo apply)
  -h|--help              Mostrar esta ayuda

El paquete se descarga desde GitHub oficial, se verifica con SHA-256 y se
instala mediante APT. El servicio RustDesk se detiene y deshabilita por defecto;
usa --enable-service únicamente si necesitas acceso desatendido.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --status) ACTION='status'; shift ;;
      --enable-service) ENABLE_SERVICE='yes'; shift ;;
      --version)
        [[ $# -ge 2 ]] || die 'falta el valor de --version'
        VERSION="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  [[ "$VERSION" == '1.4.9' ]] ||
    die "versión no soportada: $VERSION; esta implementación está fijada en 1.4.9"
}

require_debian() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este instalador solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
  command -v apt-cache >/dev/null 2>&1 || die 'apt-cache no está disponible'
  command -v dpkg >/dev/null 2>&1 || die 'dpkg no está disponible'
  command -v dpkg-query >/dev/null 2>&1 || die 'dpkg-query no está disponible'
  command -v dpkg-deb >/dev/null 2>&1 || die 'dpkg-deb no está disponible'
  command -v sha256sum >/dev/null 2>&1 || die 'sha256sum no está disponible'
  if [[ "$ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' rustdesk 2>/dev/null | grep -q 'install ok installed'
}

installed_version() {
  dpkg-query -W -f='${Version}\n' rustdesk 2>/dev/null
}

download_tool() {
  if command -v curl >/dev/null 2>&1; then
    printf '%s\n' curl
  elif command -v wget >/dev/null 2>&1; then
    printf '%s\n' wget
  else
    return 1
  fi
}

check_local_installation() {
  local current_version=''
  echo
  echo -e "${BOLD}${CYAN}═══ RustDesk ${VERSION} ═══${RESET}"
  printf 'release=%s\n' "$VERSION"
  printf 'architecture=%s\n' "$ARCHITECTURE"
  printf 'asset=%s\n' "$ASSET_NAME"
  printf 'source=%s\n' "$DOWNLOAD_URL"
  printf 'sha256=%s\n' "$EXPECTED_SHA256"

  if package_installed; then
    current_version="$(installed_version)"
    ok "paquete rustdesk instalado: $current_version"
    if [[ "$current_version" == "$VERSION" ]]; then
      ok "versión fijada ${VERSION} presente"
    elif dpkg --compare-versions "$current_version" gt "$VERSION"; then
      warn "hay una versión más nueva instalada: $current_version"
    else
      warn "la versión instalada es anterior a la fijada: $current_version"
    fi
  else
    warn 'paquete rustdesk no está instalado'
  fi

  if command -v rustdesk >/dev/null 2>&1; then
    printf 'binario=%s\n' "$(command -v rustdesk)"
    rustdesk --version 2>/dev/null | head -1 || true
  else
    printf 'binario=ausente\n'
  fi

  if systemctl list-unit-files rustdesk.service >/dev/null 2>&1; then
    printf 'servicio=presente\n'
    printf 'servicio-habilitado=%s\n' "$(systemctl is-enabled rustdesk.service 2>/dev/null || true)"
    printf 'servicio-activo=%s\n' "$(systemctl is-active rustdesk.service 2>/dev/null || true)"
  else
    printf 'servicio=ausente\n'
  fi
  if [[ "$ENABLE_SERVICE" == 'yes' ]]; then
    info 'modo solicitado: rustdesk.service quedará habilitado y activo tras --apply'
  else
    info 'modo seguro: rustdesk.service debe quedar deshabilitado e inactivo'
  fi
}

check_dependencies() {
  local tool
  tool="$(download_tool || true)"
  if [[ -n "$tool" ]]; then
    ok "descargador disponible: $tool"
  else
    warn 'no se encontró curl ni wget; --apply instalará curl desde Debian'
  fi
  ok 'herramientas de paquete y SHA-256 disponibles'
}

show_check() {
  echo -e "${BOLD}${CYAN}═══ Check RustDesk ${VERSION} ═══${RESET}"
  check_dependencies
  if [[ "$(dpkg --print-architecture)" == "$ARCHITECTURE" ]]; then
    ok "arquitectura Debian compatible: $ARCHITECTURE"
  else
    warn "arquitectura actual: $(dpkg --print-architecture); se requiere $ARCHITECTURE"
  fi
  check_local_installation
}

show_plan() {
  echo -e "${BOLD}${CYAN}═══ Plan RustDesk ${VERSION} ═══${RESET}"
  info "descargar $ASSET_NAME desde la release oficial"
  info "verificar SHA-256 $EXPECTED_SHA256"
  info 'verificar Package=rustdesk, Version=1.4.9 y Architecture=amd64'
  info 'instalar el DEB local con sudo apt-get; APT resolverá dependencias Debian'
  if [[ "$ENABLE_SERVICE" == 'yes' ]]; then
    info 'habilitar e iniciar rustdesk.service de forma explícita'
  else
    info 'detener y deshabilitar rustdesk.service después de instalar'
  fi
  info 'no se escribirá nada en modo plan'
}

install_prerequisites() {
  local packages=()
  dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -q 'install ok installed' ||
    packages+=(ca-certificates)
  if ! download_tool >/dev/null 2>&1; then
    packages+=(curl)
  fi
  [[ ${#packages[@]} -gt 0 ]] || return 0
  info "instalando dependencias auxiliares: ${packages[*]}"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

download_asset() {
  local destination="$1"
  local tool
  tool="$(download_tool)" || die 'no hay curl ni wget para descargar RustDesk'
  info "descargando $ASSET_NAME desde GitHub oficial"
  if [[ "$tool" == 'curl' ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
      --silent --show-error --output "$destination" "$DOWNLOAD_URL"
  else
    wget --https-only --quiet --show-progress --output-document="$destination" \
      "$DOWNLOAD_URL"
  fi
}

verify_asset() {
  local asset="$1"
  local actual_sha256 package version architecture
  [[ -s "$asset" ]] || die 'el artefacto descargado está vacío'
  actual_sha256="$(sha256sum "$asset" | awk '{print $1}')"
  [[ "$actual_sha256" == "$EXPECTED_SHA256" ]] ||
    die "SHA-256 inesperado: $actual_sha256"
  ok "SHA-256 verificado: $actual_sha256"

  package="$(dpkg-deb -f "$asset" Package)"
  version="$(dpkg-deb -f "$asset" Version)"
  architecture="$(dpkg-deb -f "$asset" Architecture)"
  [[ "$package" == 'rustdesk' ]] || die "paquete inesperado: $package"
  [[ "$version" == "$VERSION" ]] || die "versión inesperada en el DEB: $version"
  [[ "$architecture" == "$ARCHITECTURE" ]] ||
    die "arquitectura inesperada en el DEB: $architecture"
  ok "metadatos DEB verificados: $package $version $architecture"
}

should_install() {
  local current_version
  package_installed || return 0
  current_version="$(installed_version)"
  if [[ "$current_version" == "$VERSION" ]]; then
    ok "rustdesk ${VERSION} ya está instalado; no se descarga de nuevo"
    return 1
  fi
  if dpkg --compare-versions "$current_version" gt "$VERSION"; then
    warn "se conserva la versión más nueva ya instalada: $current_version"
    return 1
  fi
  info "se actualizará RustDesk desde $current_version a $VERSION"
  return 0
}

install_rustdesk() {
  local asset
  should_install || return 0
  TEMP_DIR="$(mktemp -d -t rafex-rustdesk.XXXXXX)"
  trap 'rm -rf -- "$TEMP_DIR"' EXIT
  asset="$TEMP_DIR/$ASSET_NAME"
  download_asset "$asset"
  verify_asset "$asset"
  info 'instalando DEB verificado mediante APT'
  sudo apt-get install -y "$asset"
  ok "RustDesk ${VERSION} instalado"
  check_local_installation
}

configure_service() {
  command -v systemctl >/dev/null 2>&1 || {
    warn 'systemctl no está disponible; no se pudo ajustar rustdesk.service'
    return 0
  }
  systemctl list-unit-files rustdesk.service >/dev/null 2>&1 || {
    warn 'rustdesk.service no fue instalado por el DEB'
    return 0
  }
  if [[ "$ENABLE_SERVICE" == 'yes' ]]; then
    sudo systemctl enable --now rustdesk.service
    ok 'rustdesk.service habilitado y activo por solicitud explícita'
  else
    sudo systemctl disable --now rustdesk.service
    ok 'rustdesk.service detenido y deshabilitado; RustDesk se abrirá manualmente'
  fi
}

main() {
  parse_args "$@"
  require_debian
  [[ "$(dpkg --print-architecture)" == "$ARCHITECTURE" ]] ||
    die "esta release solo está preparada para Debian $ARCHITECTURE"

  case "$ACTION" in
    check) show_check ;;
    plan) show_plan ;;
    status) check_local_installation ;;
    apply)
      sudo -v
      install_prerequisites
      install_rustdesk
      configure_service
      ;;
  esac
}

main "$@"
