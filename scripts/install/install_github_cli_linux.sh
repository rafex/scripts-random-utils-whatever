#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configura el repositorio APT oficial de GitHub CLI e instala `gh`.
# No configura autenticación ni almacena tokens.
set -Eeuo pipefail
umask 077

ACTION='check'
OS_TYPE="$(uname -s)"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR='/var/backups/rafex-github-cli'
KEY_URL='https://cli.github.com/packages/githubcli-archive-keyring.gpg'
KEY_SHA256='6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b'
EXPECTED_FINGERPRINTS=(
  '2C6106201985B60E6C7AC87323F3D4EA75716059'
  '7F38BBB59D064DBCB3D84D725612B36462313325'
)
KEYRING='/etc/apt/keyrings/githubcli-archive-keyring.gpg'
SOURCE_FILE='/etc/apt/sources.list.d/github-cli.list'

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
  install_github_cli_linux.sh --check
  install_github_cli_linux.sh --plan
  install_github_cli_linux.sh --apply

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Configurar el repositorio oficial e instalar gh
  -h, --help             Mostrar esta ayuda

La contraseña de sudo se solicita únicamente mediante `sudo -v`.
La autenticación de GitHub se realiza posteriormente con `gh auth login`.
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
  local checksum
  local fingerprints
  local expected

  [[ -f "$file" ]] || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  checksum="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$checksum" == "$KEY_SHA256" ]] || return 1
  fingerprints="$(key_fingerprints "$file" || true)"
  for expected in "${EXPECTED_FINGERPRINTS[@]}"; do
    if grep -Fxq "$expected" <<< "$fingerprints"; then
      return 0
    fi
  done
  return 1
}

source_content() {
  local architecture
  architecture="$(dpkg --print-architecture)"
  cat <<EOF
deb [arch=${architecture} signed-by=${KEYRING}] https://cli.github.com/packages stable main
EOF
}

check_repository() {
  local checksum=''
  echo
  echo -e "${BOLD}${CYAN}═══ GitHub CLI oficial ═══${RESET}"
  printf 'source=%s\n' "$SOURCE_FILE"
  if [[ -f "$SOURCE_FILE" ]] && grep -Fq "https://cli.github.com/packages stable main" "$SOURCE_FILE" &&
    grep -Fq "signed-by=${KEYRING}" "$SOURCE_FILE"; then
    ok 'repositorio oficial de GitHub CLI configurado'
  else
    warn "repositorio ausente o incompleto: $SOURCE_FILE"
  fi
  if [[ -f "$KEYRING" ]]; then
    checksum="$(sha256sum "$KEYRING" 2>/dev/null | awk '{print $1}' || true)"
    if key_is_valid "$KEYRING"; then
      ok "clave GitHub CLI verificada: ${checksum}"
    else
      warn "clave GitHub CLI ausente, modificada o con checksum inesperado: ${checksum:-desconocida}"
      printf 'fingerprints:\n%s\n' "$(key_fingerprints "$KEYRING" 2>/dev/null || true)"
    fi
  else
    warn "clave GitHub CLI ausente: $KEYRING"
  fi
  if package_installed gh; then
    gh --version 2>/dev/null | head -1 || dpkg-query -W -f='${Version}\n' gh
  else
    echo 'gh=missing'
  fi
  echo 'apt-policy:'
  apt-cache policy gh 2>/dev/null || true
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
  local temporary
  local checksum

  temporary="$(mktemp)"
  info 'descargando y verificando la clave de GitHub CLI'
  if ! wget --https-only --quiet --output-document="$temporary" "$KEY_URL"; then
    rm -f "$temporary"
    die "no se pudo descargar la clave desde $KEY_URL"
  fi
  checksum="$(sha256sum "$temporary" | awk '{print $1}')"
  if [[ "$checksum" != "$KEY_SHA256" ]]; then
    rm -f "$temporary"
    die "checksum SHA256 inesperado para la clave: $checksum"
  fi
  if [[ -f "$KEYRING" ]] && key_is_valid "$KEYRING"; then
    ok 'clave GitHub CLI ya estaba instalada y verificada'
  else
    backup_file "$KEYRING"
    sudo install -D -m 0644 "$temporary" "$KEYRING"
    ok "clave GitHub CLI instalada: $KEYRING"
  fi
  rm -f "$temporary"
}

write_managed_file() {
  local destination="$1"
  local content="$2"
  local temporary

  temporary="$(mktemp)"
  printf '%s' "$content" > "$temporary"
  if [[ -f "$destination" ]] && cmp -s "$temporary" "$destination"; then
    rm -f "$temporary"
    ok "sin cambios: $destination"
    return 0
  fi
  if [[ "$ACTION" == 'plan' ]]; then
    rm -f "$temporary"
    info "[plan] escribir $destination"
    return 0
  fi
  backup_file "$destination"
  sudo install -D -m 0644 "$temporary" "$destination"
  rm -f "$temporary"
  info "configurado: $destination"
}

install_github_cli() {
  if [[ "$ACTION" == 'plan' ]]; then
    info '[plan] sudo apt-get install -y gh'
  else
    sudo apt-get install -y gh
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
    echo -e "${BOLD}${CYAN}═══ Plan GitHub CLI ═══${RESET}"
    info '[plan] sudo -v'
    info '[plan] sudo apt-get update'
    info '[plan] instalar ca-certificates, wget y gnupg si faltan'
    info "[plan] verificar SHA256 $KEY_SHA256"
    info "[plan] escribir $KEYRING"
    info "[plan] escribir $SOURCE_FILE"
    install_github_cli
    exit 0
  fi

  sudo -v
  sudo apt-get update
  install_prerequisites
  install_key
  write_managed_file "$SOURCE_FILE" "$(source_content)"
  sudo apt-get update
  install_github_cli
  ok 'GitHub CLI instalado'
  check_repository
}

main "$@"
