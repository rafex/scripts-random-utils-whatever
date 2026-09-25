#!/usr/bin/env bash
# v1.0.0 - Instala mdcat x86_64 desde el release oficial en ~/.local.
set -Eeuo pipefail
umask 077

ACTION='check'
readonly VERSION='2.7.1'
readonly ASSET="mdcat-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
readonly RELEASE_URL="https://github.com/swsnr/mdcat/releases/download/mdcat-${VERSION}"
readonly DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/rafex/mdcat"
readonly BIN_DIR="${HOME}/.local/bin"
readonly INSTALL_DIR="${DATA_ROOT}/${VERSION}"
readonly LINK_PATH="${BIN_DIR}/mdcat"
TEMP_DIR=''

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  install_mdcat_linux.sh --check
  install_mdcat_linux.sh --plan
  install_mdcat_linux.sh --apply
  install_mdcat_linux.sh --status

Instala mdcat x86_64 desde el release oficial en ~/.local/share/rafex/mdcat.
No usa sudo ni modifica paquetes, servicios o archivos de configuración.
EOF
}

parse_args() {
  [[ $# -le 1 ]] || die 'selecciona una sola acción'
  if [[ $# -eq 1 ]]; then
    case "$1" in
      --check|--plan|--apply|--status) ACTION="${1#--}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  fi
}

require_platform() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "$(uname -m)" == x86_64 ]] || die 'mdcat está configurado para ThinkPad x86_64'
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die 'HOME no apunta a un directorio existente'
  for command_name in curl tar b2sum install; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando: $command_name"
  done
}

installed_version() {
  if [[ -x "$LINK_PATH" ]]; then
    "$LINK_PATH" --version 2>/dev/null | sed -n '1p' || true
  fi
}

show_status() {
  printf 'versión objetivo=%s\n' "$VERSION"
  printf 'instalación=%s\n' "$INSTALL_DIR"
  printf 'enlace=%s\n' "$LINK_PATH"
  if [[ -x "$LINK_PATH" ]]; then
    info "versión detectada: $(installed_version)"
  else
    warn 'mdcat no está instalado en la ruta administrada'
  fi
  if [[ -L "$LINK_PATH" ]]; then
    printf 'destino=%s\n' "$(readlink -- "$LINK_PATH")"
  fi
}

verify_archive() {
  local archive="$1" checksums="$2" expected actual
  expected="$(awk -v asset="$ASSET" '$NF == asset { print $1; exit }' "$checksums")"
  [[ "$expected" =~ ^[[:xdigit:]]{128}$ ]] \
    || die "B2SUMS.txt no contiene un checksum válido para $ASSET"
  actual="$(b2sum -- "$archive" | awk '{ print $1 }')"
  [[ "${actual,,}" == "${expected,,}" ]] || die 'BLAKE2b-512 incorrecto; se cancela la instalación'
}

extract_binary() {
  local archive="$1" destination="$2" member
  member="$(tar -tzf "$archive" | awk '
    { name=$0; sub(/^\.\//, "", name) }
    !found && (name == "mdcat" || name ~ /\/mdcat$/) { print $0; found=1 }
  ')"
  [[ -n "$member" ]] || die 'el archivo oficial no contiene el binario mdcat'
  tar -xOzf "$archive" -- "$member" > "$destination"
  [[ -s "$destination" ]] || die 'el binario extraído está vacío'
  chmod 0755 -- "$destination"
}

apply_installation() {
  local archive checksums staged_binary
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafex-mdcat.XXXXXX")"
  archive="$TEMP_DIR/$ASSET"
  checksums="$TEMP_DIR/B2SUMS.txt"
  staged_binary="$TEMP_DIR/mdcat"

  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    -o "$archive" "${RELEASE_URL}/${ASSET}"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    -o "$checksums" "${RELEASE_URL}/B2SUMS.txt"
  verify_archive "$archive" "$checksums"
  extract_binary "$archive" "$staged_binary"
  "$staged_binary" --version >/dev/null 2>&1 \
    || die 'el binario descargado no pudo ejecutarse'

  if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
    die "el destino ya existe; se conserva sin cambios: $INSTALL_DIR"
  fi
  if [[ -e "$LINK_PATH" && ! -L "$LINK_PATH" ]]; then
    die "el destino existe y no es un enlace simbólico; se conserva: $LINK_PATH"
  fi
  if [[ -L "$LINK_PATH" ]]; then
    local current_target
    current_target="$(readlink -- "$LINK_PATH")"
    [[ "$current_target" == "$DATA_ROOT/"* ]] \
      || die "el enlace pertenece a otra instalación; se conserva: $LINK_PATH"
  fi

  install -d -m 0755 -- "$DATA_ROOT" "$BIN_DIR"
  install -d -m 0755 -- "$INSTALL_DIR"
  install -m 0755 -- "$staged_binary" "$INSTALL_DIR/mdcat"
  printf '%s\n' "version=$VERSION" 'source=swsnr/mdcat official release' > "$INSTALL_DIR/.rafex-managed"
  ln -sfn -- "$INSTALL_DIR/mdcat" "$LINK_PATH"
  ok "mdcat $VERSION instalado en $INSTALL_DIR"
  if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    warn "$BIN_DIR no está en PATH; puedes ejecutar $LINK_PATH"
  fi
}

main() {
  parse_args "$@"
  require_platform
  case "$ACTION" in
    check)
      echo '═══ mdcat para ThinkPad ═══'
      show_status
      info "release fijado: ${RELEASE_URL}/${ASSET}"
      ;;
    status) show_status ;;
    plan)
      echo '═══ Plan de instalación mdcat ═══'
      printf 'versión=%s\n' "$VERSION"
      printf 'origen=%s/%s\n' "$RELEASE_URL" "$ASSET"
      printf 'destino=%s\n' "$INSTALL_DIR"
      printf 'comando=%s\n' "$LINK_PATH"
      info 'descargar, verificar BLAKE2b-512 y dejar un enlace local en ~/.local/bin'
      ;;
    apply) apply_installation ;;
  esac
}

main "$@"
