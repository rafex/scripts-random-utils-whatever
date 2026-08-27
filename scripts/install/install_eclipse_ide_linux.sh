#!/usr/bin/env bash
# shellcheck shell=bash
#
# Descarga e instala Eclipse IDE Java o Enterprise Java/Web desde eclipse.org.
# Obtiene la versión vigente mediante el scraper oficial del repositorio y
# verifica el SHA-512 publicado por Eclipse antes de instalar.
set -Eeuo pipefail
umask 077

ACTION='check'
PACKAGE='jee'
PREFIX=''
OS_TYPE="$(uname -s)"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR='/var/backups/rafex-eclipse-ide'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRAPER="${SCRIPT_DIR}/scrape_eclipse_packages.py"

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
  install_eclipse_ide_linux.sh --check [--package java|jee]
  install_eclipse_ide_linux.sh --plan [--package java|jee]
  install_eclipse_ide_linux.sh --apply [--package java|jee]

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Descargar, verificar e instalar Eclipse IDE
  --package <tipo>       java o jee (default: jee)
  --prefix <directorio>  Directorio de instalación (solo --apply)
  -h, --help             Mostrar esta ayuda

Paquetes:
  java                   Eclipse IDE for Java Developers
  jee                    Eclipse IDE for Enterprise Java and Web Developers

La contraseña de sudo se solicita únicamente mediante `sudo -v`.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --package)
        [[ $# -ge 2 ]] || die 'falta el valor de --package'
        PACKAGE="$2"
        shift 2
        ;;
      --prefix)
        [[ $# -ge 2 ]] || die 'falta el valor de --prefix'
        PREFIX="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  [[ "$PACKAGE" == 'java' || "$PACKAGE" == 'jee' ]] ||
    die "paquete no soportado: $PACKAGE (usa java o jee)"
}

require_debian() {
  [[ "$OS_TYPE" == 'Linux' ]] || die 'este script solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
  command -v python3 >/dev/null 2>&1 || die 'python3 no está disponible'
  command -v dpkg >/dev/null 2>&1 || die 'dpkg no está disponible'
  if [[ "$ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  fi
}

package_name() {
  [[ "$PACKAGE" == 'java' ]] && printf '%s\n' 'eclipse-java' || printf '%s\n' 'eclipse-jee'
}

default_prefix() {
  printf '/opt/%s\n' "$(package_name)"
}

install_prefix() {
  if [[ -n "$PREFIX" ]]; then
    printf '%s\n' "$PREFIX"
  else
    default_prefix
  fi
}

validate_prefix() {
  local prefix
  prefix="$(install_prefix)"
  [[ "$prefix" == /* ]] || die "--prefix debe ser una ruta absoluta: $prefix"
  [[ "$prefix" != */ && "$prefix" != *..* ]] ||
    die "--prefix no puede terminar en / ni contener ..: $prefix"
  case "$prefix" in
    /|/bin|/etc|/home|/lib|/lib64|/opt|/root|/sbin|/tmp|/usr|/var)
      die "--prefix apunta a un directorio protegido; usa un subdirectorio: $prefix"
      ;;
  esac
}

desktop_file() {
  printf '/usr/share/applications/%s.desktop\n' "$(package_name)"
}

launcher_name() {
  printf '/usr/local/bin/%s\n' "$(package_name)"
}

architecture_name() {
  case "$(dpkg --print-architecture)" in
    amd64) printf '%s\n' 'x86_64' ;;
    arm64) printf '%s\n' 'aarch64' ;;
    *) die "arquitectura Debian no soportada por Eclipse: $(dpkg --print-architecture)" ;;
  esac
}

package_installed() {
  local package="$1"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'
}

install_prerequisites() {
  local packages=()
  package_installed ca-certificates || packages+=(ca-certificates)
  package_installed python3 || packages+=(python3)
  command -v wget >/dev/null 2>&1 || packages+=(wget)
  command -v tar >/dev/null 2>&1 || packages+=(tar)
  if [[ ! -x /usr/bin/java ]]; then
    packages+=(default-jre)
  fi
  [[ ${#packages[@]} -gt 0 ]] || return 0
  info "Paquetes auxiliares: ${packages[*]}"
  sudo apt-get install -y "${packages[@]}"
}

fetch_metadata() {
  local architecture="$1"
  python3 "$SCRAPER" --package "$PACKAGE" --architecture "$architecture"
}

metadata_field() {
  local metadata="$1"
  local field="$2"
  python3 -c 'import json, sys; print(json.load(sys.stdin)["packages"][sys.argv[1]][sys.argv[2]])' \
    "$PACKAGE" "$field" <<< "$metadata"
}

check_installation() {
  local prefix
  local launcher

  prefix="$(install_prefix)"
  launcher="$(launcher_name)"
  echo
  echo -e "${BOLD}${CYAN}═══ Eclipse IDE ${PACKAGE} ═══${RESET}"
  printf 'prefix=%s\n' "$prefix"
  printf 'desktop=%s\n' "$(desktop_file)"
  if [[ -x "$prefix/eclipse" ]]; then
    ok "Eclipse instalado: $prefix"
    "$prefix/eclipse" -version 2>&1 | head -5 || true
  else
    warn "Eclipse no está instalado en $prefix"
  fi
  if [[ -e "$(desktop_file)" ]]; then
    ok "lanzador de escritorio presente: $(desktop_file)"
  else
    warn "lanzador de escritorio ausente: $(desktop_file)"
  fi
  if [[ -x "$launcher" || -L "$launcher" ]]; then
    ok "lanzador de terminal presente: $launcher"
  else
    warn "lanzador de terminal ausente: $launcher"
  fi
}

backup_path() {
  local path="$1"
  local name
  name="${path#/}"
  name="${name//\//_}"
  sudo install -d -m 0755 "$BACKUP_DIR"
  printf '%s/%s.bak.%s\n' "$BACKUP_DIR" "$name" "$BACKUP_STAMP"
}

write_system_file() {
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
  if [[ -e "$destination" || -L "$destination" ]]; then
    sudo cp -a "$destination" "$(backup_path "$destination")"
  fi
  sudo install -D -m 0644 "$temporary" "$destination"
  rm -f -- "$temporary"
  info "configurado: $destination"
}

desktop_content() {
  local prefix="$1"
  local name
  local display_name
  name="$(package_name)"
  if [[ "$PACKAGE" == 'java' ]]; then
    display_name='Eclipse IDE for Java Developers'
  else
    display_name='Eclipse IDE for Enterprise Java and Web Developers'
  fi
  cat <<EOF
[Desktop Entry]
Type=Application
Name=${display_name}
Comment=Eclipse IDE
Exec=${prefix}/eclipse %F
Icon=${prefix}/icon.xpm
Terminal=false
Categories=Development;IDE;Java;
StartupWMClass=Eclipse
MimeType=text/x-java;text/x-java-source;application/x-java-archive;
EOF
}

launcher_content() {
  local prefix="$1"
  cat <<EOF
#!/usr/bin/env bash
exec "${prefix}/eclipse" "\$@"
EOF
}

install_archive() {
  local metadata="$1"
  local filename
  local download_url
  local checksum
  local archive
  local extract_dir
  local top_dir
  local prefix
  local temporary_desktop
  local temporary_launcher

  filename="$(metadata_field "$metadata" filename)"
  download_url="$(metadata_field "$metadata" direct_url)"
  checksum="$(metadata_field "$metadata" checksum)"
  prefix="$(install_prefix)"
  archive="$TEMP_DIR/$filename"
  extract_dir="$TEMP_DIR/extracted"

  info "descargando $filename desde Eclipse"
  wget --https-only --quiet --show-progress --output-document="$archive" "$download_url"
  if [[ "$(sha512sum "$archive" | awk '{print $1}')" != "$checksum" ]]; then
    die "SHA-512 inesperado para $filename"
  fi
  ok "SHA-512 verificado: $checksum"

  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  top_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$top_dir" && -x "$top_dir/eclipse" ]] ||
    die 'el archivo Eclipse no contiene un directorio ejecutable esperado'

  if [[ -e "$prefix" || -L "$prefix" ]]; then
    sudo cp -a "$prefix" "$(backup_path "$prefix")"
  fi
  sudo install -d -m 0755 "$(dirname "$prefix")"
  sudo rm -rf -- "$prefix"
  sudo mv "$top_dir" "$prefix"
  sudo chown -R root:root "$prefix"
  sudo chmod 0755 "$prefix/eclipse"

  temporary_desktop="$(mktemp)"
  desktop_content "$prefix" > "$temporary_desktop"
  sudo install -D -m 0644 "$temporary_desktop" "$(desktop_file)"
  rm -f -- "$temporary_desktop"

  temporary_launcher="$(mktemp)"
  launcher_content "$prefix" > "$temporary_launcher"
  sudo install -D -m 0755 "$temporary_launcher" "$(launcher_name)"
  rm -f -- "$temporary_launcher"
  ok "Eclipse instalado en $prefix"
}

main() {
  local architecture
  local metadata

  parse_args "$@"
  require_debian
  validate_prefix
  architecture="$(architecture_name)"

  if [[ "$ACTION" == 'check' ]]; then
    check_installation
    exit 0
  fi

  if [[ "$ACTION" == 'plan' ]]; then
    metadata="$(fetch_metadata "$architecture")"
    echo
    echo -e "${BOLD}${CYAN}═══ Plan Eclipse IDE ${PACKAGE} ═══${RESET}"
    info "versión detectada: $(metadata_field "$metadata" release)"
    info "archivo: $(metadata_field "$metadata" filename)"
    info "SHA-512: $(metadata_field "$metadata" checksum)"
    info '[plan] sudo -v'
    info '[plan] instalar ca-certificates, python3, wget, tar y default-jre si faltan'
    info "[plan] descargar y verificar $(metadata_field "$metadata" filename)"
    info "[plan] instalar en $(install_prefix)"
    info "[plan] crear $(desktop_file) y $(launcher_name)"
    exit 0
  fi

  sudo -v
  sudo apt-get update
  install_prerequisites
  metadata="$(fetch_metadata "$architecture")"
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf -- "$TEMP_DIR"' EXIT
  install_archive "$metadata"
  check_installation
}

main "$@"
