#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configura el repositorio APT oficial de Mozilla e instala Firefox DEB nativo.
# No instala ni elimina Firefox ESR automáticamente.
set -Eeuo pipefail
umask 077

ACTION="check"
OS_TYPE="$(uname -s)"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR='/var/backups/rafex-mozilla-firefox'
KEY_URL='https://packages.mozilla.org/apt/repo-signing-key.gpg'
EXPECTED_FINGERPRINT='35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3'
KEYRING='/etc/apt/keyrings/packages.mozilla.org.asc'
SOURCE_FILE='/etc/apt/sources.list.d/mozilla.sources'
PREFERENCES_FILE='/etc/apt/preferences.d/mozilla-firefox'

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
  install_firefox_mozilla_linux.sh --check
  install_firefox_mozilla_linux.sh --plan
  install_firefox_mozilla_linux.sh --apply

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Configurar Mozilla APT e instalar Firefox DEB nativo
  -h, --help             Mostrar esta ayuda

Instala el paquete `firefox` desde packages.mozilla.org. No instala ni
elimina `firefox-esr` automáticamente. La contraseña de sudo se solicita
únicamente mediante `sudo -v`.
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
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
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

key_fingerprint() {
  local file="$1"
  command -v gpg >/dev/null 2>&1 || return 1
  gpg --batch --no-options --no-default-keyring --show-keys --with-colons "$file" 2>/dev/null |
    awk -F: '$1 == "fpr" { print toupper($10); exit }'
}

source_content() {
  cat <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $KEYRING
EOF
}

preferences_content() {
  cat <<'EOF'
Package: firefox
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox-l10n-*
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
}

check_repository() {
  local fingerprint=''
  echo
  echo -e "${BOLD}${CYAN}═══ Firefox DEB de Mozilla ═══${RESET}"
  printf 'source=%s\n' "$SOURCE_FILE"
  if [[ -f "$SOURCE_FILE" ]] && grep -Fq 'URIs: https://packages.mozilla.org/apt' "$SOURCE_FILE" &&
    grep -Fq "Signed-By: $KEYRING" "$SOURCE_FILE"; then
    ok 'repositorio Mozilla configurado'
  else
    warn "repositorio Mozilla ausente o incompleto: $SOURCE_FILE"
  fi
  if [[ -f "$KEYRING" ]]; then
    fingerprint="$(key_fingerprint "$KEYRING" || true)"
    if [[ "$fingerprint" == "$EXPECTED_FINGERPRINT" ]]; then
      ok "clave Mozilla verificada: $fingerprint"
    else
      warn "huella de clave ausente o incorrecta: ${fingerprint:-desconocida}"
    fi
  else
    warn "clave Mozilla ausente: $KEYRING"
  fi
  if package_installed firefox; then
    printf 'firefox='; firefox --version 2>/dev/null || dpkg-query -W -f='${Version}\n' firefox
  else
    echo 'firefox=missing'
  fi
  if package_installed firefox-esr; then
    warn 'firefox-esr está instalado; este script no lo elimina automáticamente'
  else
    echo 'firefox-esr=not-installed'
  fi
  if command -v apt-cache >/dev/null 2>&1; then
    echo 'apt-policy:'
    apt-cache policy firefox 2>/dev/null || true
  fi
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
  local fingerprint

  temporary="$(mktemp)"
  info "descargando y verificando la clave de Mozilla"
  if ! wget --https-only --quiet --output-document="$temporary" "$KEY_URL"; then
    rm -f "$temporary"
    die "no se pudo descargar la clave desde $KEY_URL"
  fi
  fingerprint="$(key_fingerprint "$temporary" || true)"
  if [[ "$fingerprint" != "$EXPECTED_FINGERPRINT" ]]; then
    rm -f "$temporary"
    die "huella de clave inesperada: ${fingerprint:-desconocida}"
  fi

  if [[ -f "$KEYRING" ]] && [[ "$(key_fingerprint "$KEYRING" || true)" == "$EXPECTED_FINGERPRINT" ]]; then
    ok 'clave Mozilla ya estaba instalada y verificada'
  else
    backup_file "$KEYRING"
    sudo install -D -m 0644 "$temporary" "$KEYRING"
    ok "clave Mozilla instalada: $KEYRING"
  fi
  rm -f "$temporary"
}

write_managed_file() {
  local destination="$1"
  local content="$2"
  local temporary

  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
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

install_firefox() {
  local locale_package='firefox-l10n-es-mx'
  local packages=(firefox)

  if apt-cache show "$locale_package" >/dev/null 2>&1; then
    packages+=("$locale_package")
  else
    warn "paquete de idioma no disponible: $locale_package"
  fi
  if [[ "$ACTION" == 'plan' ]]; then
    info "[plan] sudo apt-get install -y ${packages[*]}"
  else
    sudo apt-get install -y "${packages[@]}"
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
    echo -e "${BOLD}${CYAN}═══ Plan Firefox DEB de Mozilla ═══${RESET}"
    info '[plan] sudo -v'
    info '[plan] sudo apt-get update'
    info '[plan] instalar ca-certificates, wget y gnupg si faltan'
    info "[plan] verificar huella $EXPECTED_FINGERPRINT"
    info "[plan] escribir $KEYRING"
    info "[plan] escribir $SOURCE_FILE"
    info "[plan] escribir $PREFERENCES_FILE"
    install_firefox
    exit 0
  fi

  sudo -v
  sudo apt-get update
  install_prerequisites
  install_key
  write_managed_file "$SOURCE_FILE" "$(source_content)"
  write_managed_file "$PREFERENCES_FILE" "$(preferences_content)"
  sudo apt-get update
  install_firefox
  ok 'Firefox DEB nativo de Mozilla instalado'
  check_repository
}

main "$@"
