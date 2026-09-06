#!/usr/bin/env bash
# shellcheck shell=bash
#
# Descarga e instala el paquete DEB oficial de Ulauncher 5.16.1 (arch-
# independiente) publicado en GitHub. El artefacto se verifica (tamaño +
# SHA-256 + metadatos DEB) antes de entregarlo a APT. Opcionalmente agrega
# un atajo de prueba en i3 ($mod+u) sin tocar $mod+space.
set -Eeuo pipefail
umask 077

ACTION='check'
VERSION='5.16.1'
ARCHITECTURE='all'
ASSET_NAME="ulauncher_${VERSION}_all.deb"
DOWNLOAD_URL="https://github.com/Ulauncher/Ulauncher/releases/download/${VERSION}/${ASSET_NAME}"
EXPECTED_SHA256='7212d846c8519615e55f99790ac7f6267e5cc812f0da4b4a6d3afe89ddc12b9f'
EXPECTED_SIZE_BYTES='1862092'
TEMP_DIR=''
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

I3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
I3_BEGIN='# BEGIN rafex ulauncher'
I3_END='# END rafex ulauncher'
CONFIGURE_I3=0

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
  install_ulauncher_linux.sh --check
  install_ulauncher_linux.sh --plan
  install_ulauncher_linux.sh --apply [--i3-shortcut]
  install_ulauncher_linux.sh --status

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan|--dry-run       Mostrar el plan sin modificar nada
  --apply                Descargar, verificar e instalar el DEB oficial
  --status                Mostrar la instalación local
  --version <versión>    Solo se admite la release fijada 5.16.1
  --i3-shortcut           Junto con --apply, agrega bindsym $mod+u en i3
                          (no toca $mod+space; solo para probar Ulauncher)
  -h|--help               Mostrar esta ayuda

El paquete se descarga desde GitHub oficial (asset arch-independiente
"all"), se verifica por tamaño + SHA-256 + metadatos DEB, y se instala
mediante APT para que resuelva las dependencias de Ulauncher.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --status) ACTION='status'; shift ;;
      --i3-shortcut) CONFIGURE_I3=1; shift ;;
      --version)
        [[ $# -ge 2 ]] || die 'falta el valor de --version'
        VERSION="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  [[ "$VERSION" == '5.16.1' ]] ||
    die "versión no soportada: $VERSION; esta implementación está fijada en 5.16.1"
}

require_debian() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este instalador solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
  command -v dpkg >/dev/null 2>&1 || die 'dpkg no está disponible'
  command -v dpkg-query >/dev/null 2>&1 || die 'dpkg-query no está disponible'
  command -v dpkg-deb >/dev/null 2>&1 || die 'dpkg-deb no está disponible'
  command -v sha256sum >/dev/null 2>&1 || die 'sha256sum no está disponible'
  if [[ "$ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' ulauncher 2>/dev/null | grep -q 'install ok installed'
}

installed_version() {
  dpkg-query -W -f='${Version}\n' ulauncher 2>/dev/null
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
  echo -e "${BOLD}${CYAN}═══ Ulauncher ${VERSION} ═══${RESET}"
  printf 'release=%s\n' "$VERSION"
  printf 'architecture=%s\n' "$ARCHITECTURE"
  printf 'asset=%s\n' "$ASSET_NAME"
  printf 'source=%s\n' "$DOWNLOAD_URL"
  printf 'sha256=%s\n' "$EXPECTED_SHA256"

  if package_installed; then
    current_version="$(installed_version)"
    ok "paquete ulauncher instalado: $current_version"
    if [[ "$current_version" == "$VERSION" ]]; then
      ok "versión fijada ${VERSION} presente"
    elif dpkg --compare-versions "$current_version" gt "$VERSION"; then
      warn "hay una versión más nueva instalada: $current_version"
    else
      warn "la versión instalada es anterior a la fijada: $current_version"
    fi
  else
    warn 'paquete ulauncher no está instalado'
  fi

  if command -v ulauncher >/dev/null 2>&1; then
    printf 'binario=%s\n' "$(command -v ulauncher)"
  else
    printf 'binario=ausente\n'
  fi

  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG"; then
    ok 'atajo de prueba $mod+u configurado en i3'
  else
    warn 'sin atajo de prueba en i3 (usa --apply --i3-shortcut para agregarlo)'
  fi

  if systemctl --user is-active --quiet ulauncher.service 2>/dev/null; then
    ok 'ulauncher.service activo (ulauncher-toggle funcionará)'
  else
    warn 'ulauncher.service no está activo; ulauncher-toggle no tiene nada que mostrar (usa --apply para iniciarlo)'
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
  echo -e "${BOLD}${CYAN}═══ Check Ulauncher ${VERSION} ═══${RESET}"
  check_dependencies
  check_local_installation
}

show_plan() {
  echo -e "${BOLD}${CYAN}═══ Plan Ulauncher ${VERSION} ═══${RESET}"
  info "descargar $ASSET_NAME desde la release oficial"
  info "verificar tamaño ${EXPECTED_SIZE_BYTES} bytes y SHA-256 $EXPECTED_SHA256"
  info "verificar Package=ulauncher, Version=${VERSION} y Architecture=${ARCHITECTURE}"
  info 'instalar el DEB local con sudo apt-get; APT resolverá dependencias Debian'
  info 'systemctl --user enable --now ulauncher.service (el paquete trae el daemon, pero no lo arranca solo)'
  if [[ "$CONFIGURE_I3" -eq 1 ]]; then
    info "agregar bindsym \$mod+u (Ulauncher) en $I3_CONFIG"
    info "agregar exec --no-startup-id systemctl --user start ulauncher.service en $I3_CONFIG"
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
  tool="$(download_tool)" || die 'no hay curl ni wget para descargar Ulauncher'
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
  local actual_size actual_sha256 package version architecture
  [[ -s "$asset" ]] || die 'el artefacto descargado está vacío'
  actual_size="$(stat -c%s "$asset")"
  [[ "$actual_size" == "$EXPECTED_SIZE_BYTES" ]] ||
    die "tamaño inesperado: ${actual_size} bytes (se esperaban ${EXPECTED_SIZE_BYTES})"
  actual_sha256="$(sha256sum "$asset" | awk '{print $1}')"
  [[ "$actual_sha256" == "$EXPECTED_SHA256" ]] ||
    die "SHA-256 inesperado: $actual_sha256"
  ok "tamaño y SHA-256 verificados: $actual_sha256"

  package="$(dpkg-deb -f "$asset" Package)"
  version="$(dpkg-deb -f "$asset" Version)"
  architecture="$(dpkg-deb -f "$asset" Architecture)"
  [[ "$package" == 'ulauncher' ]] || die "paquete inesperado: $package"
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
    ok "ulauncher ${VERSION} ya está instalado; no se descarga de nuevo"
    return 1
  fi
  if dpkg --compare-versions "$current_version" gt "$VERSION"; then
    warn "se conserva la versión más nueva ya instalada: $current_version"
    return 1
  fi
  info "se actualizará Ulauncher desde $current_version a $VERSION"
  return 0
}

install_ulauncher() {
  local asset
  should_install || return 0
  TEMP_DIR="$(mktemp -d -t rafex-ulauncher.XXXXXX)"
  trap 'rm -rf -- "$TEMP_DIR"' EXIT
  asset="$TEMP_DIR/$ASSET_NAME"
  download_asset "$asset"
  verify_asset "$asset"
  info 'instalando DEB verificado mediante APT'
  sudo apt-get install -y "$asset"
  ok "Ulauncher ${VERSION} instalado"
  check_local_installation
}

# El paquete trae ulauncher.service (WantedBy=graphical-session.target), pero
# en una sesión i3 sin ese target activo (sin GNOME/systemd-logind de por
# medio) nunca arranca solo: ulauncher-toggle fallaría con
# "org.freedesktop.DBus.Error.ServiceUnknown" porque no hay ningún daemon
# escuchando. Lo habilitamos y arrancamos explícitamente para esta sesión.
enable_ulauncher_service() {
  systemctl --user daemon-reload 2>/dev/null || true
  if systemctl --user enable --now ulauncher.service; then
    ok 'ulauncher.service habilitado e iniciado'
  else
    warn 'no se pudo iniciar ulauncher.service; ulauncher-toggle no funcionará hasta resolverlo'
  fi
}

backup_colocated() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 0
  cp -a -- "$file" "$file.bak.$BACKUP_STAMP"
  info "respaldo: $file.bak.$BACKUP_STAMP"
}

# Parchea (idempotente, con respaldo colocado) un bloque BEGIN/END en un
# archivo ya desplegado -mismo mecanismo que install_eww_linux.sh usa para
# su propio atajo en i3-, sin tocar nada fuera del bloque marcado.
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
exec --no-startup-id systemctl --user start ulauncher.service
bindsym \$mod+u exec --no-startup-id ulauncher-toggle
$I3_END
EOF
  replace_block "$I3_CONFIG" "$I3_BEGIN" "$I3_END" "$block"
  rm -f -- "$block"
  ok "atajo de prueba \$mod+u configurado en $I3_CONFIG (recarga i3 con \$mod+Shift+r)"
}

main() {
  parse_args "$@"
  require_debian

  case "$ACTION" in
    check) show_check ;;
    plan) show_plan ;;
    status) check_local_installation ;;
    apply)
      sudo -v
      install_prerequisites
      install_ulauncher
      enable_ulauncher_service
      configure_i3_shortcut
      ;;
  esac
}

main "$@"
