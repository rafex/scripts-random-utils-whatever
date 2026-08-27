#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configura el repositorio APT oficial de VSCodium e instala el paquete codium.
# No instala extensiones ni importa configuraciones de VS Code.
set -Eeuo pipefail
umask 077

ACTION='check'
OS_TYPE="$(uname -s)"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR='/var/backups/rafex-vscodium'
KEY_URL='https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg'
EXPECTED_FINGERPRINT='1302DE60231889FE1EBACADC54678CF75A278D9C'
KEYRING='/usr/share/keyrings/vscodium-archive-keyring.gpg'
SOURCE_FILE='/etc/apt/sources.list.d/vscodium.sources'
REPOSITORY_URI='https://download.vscodium.com/debs'

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
  install_vscodium_linux.sh --check
  install_vscodium_linux.sh --plan
  install_vscodium_linux.sh --apply

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Configurar el repositorio e instalar codium
  -h, --help             Mostrar esta ayuda

La contraseña de sudo se solicita únicamente mediante `sudo -v`.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_debian() {
  [[ "$OS_TYPE" == 'Linux' ]] || die 'este script solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
  command -v dpkg >/dev/null 2>&1 || die 'dpkg no está disponible'
  if [[ "$ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  fi
}

package_installed() {
  local package="$1"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'
}

backup_file() {
  local file="$1"
  local relative
  local encoded
  local destination

  [[ -e "$file" ]] || return 0
  relative="${file#/}"
  encoded="${relative//\//_}"
  destination="$BACKUP_DIR/${encoded}.bak.${BACKUP_STAMP}"
  sudo install -d -m 0755 "$BACKUP_DIR"
  sudo cp -a "$file" "$destination"
  info "respaldo: $destination"
}

key_fingerprints() {
  local file="$1"
  local gpg_home

  command -v gpg >/dev/null 2>&1 || return 1
  gpg_home="$(mktemp -d)"
  GNUPGHOME="$gpg_home" gpg --batch --no-options --no-default-keyring \
    --show-keys --with-colons "$file" 2>/dev/null |
    awk -F: '$1 == "fpr" { print toupper($10) }'
  rm -rf -- "$gpg_home"
}

key_is_valid() {
  local file="$1"
  local fingerprints

  [[ -f "$file" ]] || return 1
  fingerprints="$(key_fingerprints "$file" || true)"
  grep -Fxq "$EXPECTED_FINGERPRINT" <<< "$fingerprints"
}

source_content() {
  local architecture
  architecture="$(dpkg --print-architecture)"
  case "$architecture" in
    amd64|arm64) ;;
    *) die "arquitectura no soportada por el repositorio VSCodium: $architecture" ;;
  esac
  cat <<EOF
Types: deb
URIs: ${REPOSITORY_URI}
Suites: vscodium
Components: main
Architectures: ${architecture}
Signed-By: ${KEYRING}
EOF
}

check_repository() {
  local fingerprints=''
  echo
  echo -e "${BOLD}${CYAN}═══ VSCodium DEB oficial ═══${RESET}"
  printf 'source=%s\n' "$SOURCE_FILE"
  if [[ -f "$SOURCE_FILE" ]] && grep -Fq "URIs: ${REPOSITORY_URI}" "$SOURCE_FILE" &&
    grep -Fq "Signed-By: ${KEYRING}" "$SOURCE_FILE"; then
    ok 'repositorio VSCodium configurado'
  else
    warn "repositorio VSCodium ausente o incompleto: $SOURCE_FILE"
  fi
  if [[ -f "$KEYRING" ]]; then
    fingerprints="$(key_fingerprints "$KEYRING" 2>/dev/null || true)"
    if key_is_valid "$KEYRING"; then
      ok "clave VSCodium verificada: $EXPECTED_FINGERPRINT"
    else
      warn "clave VSCodium ausente o con huella inesperada"
      printf 'fingerprints:\n%s\n' "$fingerprints"
    fi
  else
    warn "clave VSCodium ausente: $KEYRING"
  fi
  if package_installed codium; then
    codium --version 2>/dev/null | head -1 || dpkg-query -W -f='${Version}\n' codium
  else
    echo 'codium=missing'
  fi
  echo 'apt-policy:'
  apt-cache policy codium 2>/dev/null || true
}

install_prerequisites() {
  local packages=()
  package_installed ca-certificates || packages+=(ca-certificates)
  command -v wget >/dev/null 2>&1 || packages+=(wget)
  command -v gpg >/dev/null 2>&1 || packages+=(gnupg)
  [[ ${#packages[@]} -gt 0 ]] || return 0
  info "Paquetes auxiliares: ${packages[*]}"
  sudo apt-get install -y "${packages[@]}"
}

install_key() {
  local temporary_ascii
  local temporary_binary

  temporary_ascii="$(mktemp)"
  temporary_binary="$(mktemp)"
  info 'descargando y verificando la clave de VSCodium'
  if ! wget --https-only --quiet --output-document="$temporary_ascii" "$KEY_URL"; then
    die "no se pudo descargar la clave desde $KEY_URL"
  fi
  if ! key_is_valid "$temporary_ascii"; then
    die "huella de clave VSCodium inesperada; se esperaba $EXPECTED_FINGERPRINT"
  fi
  if ! gpg --batch --yes --dearmor --output "$temporary_binary" "$temporary_ascii"; then
    die 'no se pudo convertir la clave VSCodium al formato de keyring'
  fi

  if [[ -f "$KEYRING" ]] && key_is_valid "$KEYRING"; then
    ok 'clave VSCodium ya estaba instalada y verificada'
  else
    backup_file "$KEYRING"
    sudo install -D -m 0644 "$temporary_binary" "$KEYRING"
    ok "clave VSCodium instalada: $KEYRING"
  fi
  rm -f -- "$temporary_ascii" "$temporary_binary"
}

write_managed_file() {
  local destination="$1"
  local content="$2"
  local temporary

  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  if [[ -f "$destination" ]] && cmp -s "$temporary" "$destination"; then
    rm -f -- "$temporary"
    ok "sin cambios: $destination"
    return 0
  fi
  if [[ "$ACTION" == 'plan' ]]; then
    rm -f -- "$temporary"
    info "[plan] escribir $destination"
    return 0
  fi
  backup_file "$destination"
  sudo install -D -m 0644 "$temporary" "$destination"
  rm -f -- "$temporary"
  info "configurado: $destination"
}

install_vscodium() {
  if [[ "$ACTION" == 'plan' ]]; then
    info '[plan] sudo apt-get install -y codium'
  else
    sudo apt-get install -y codium
  fi
}

main() {
  parse_args "$@"
  require_debian

  if [[ "$ACTION" == 'check' ]]; then
    check_repository
    exit 0
  fi

  if [[ "$ACTION" == 'plan' ]]; then
    echo
    echo -e "${BOLD}${CYAN}═══ Plan VSCodium DEB ═══${RESET}"
    info '[plan] sudo -v'
    info '[plan] sudo apt-get update'
    info '[plan] instalar ca-certificates, wget y gnupg si faltan'
    info "[plan] verificar huella $EXPECTED_FINGERPRINT"
    info "[plan] escribir $KEYRING"
    info "[plan] escribir $SOURCE_FILE"
    install_vscodium
    exit 0
  fi

  sudo -v
  sudo apt-get update
  install_prerequisites
  install_key
  write_managed_file "$SOURCE_FILE" "$(source_content)"
  sudo apt-get update
  install_vscodium
  ok 'VSCodium DEB instalado'
  check_repository
}

main "$@"
