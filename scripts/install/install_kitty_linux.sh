#!/usr/bin/env bash
# shellcheck shell=bash
# v1.0.0 — Instala Kitty x86_64 desde el release oficial, sin root.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
ARCHIVE_INPUT=""
ACTION_CHOSEN=false

readonly VERSION="0.48.2"
readonly ARCHIVE_NAME="kitty-${VERSION}-x86_64.txz"
readonly DOWNLOAD_URL="https://github.com/kovidgoyal/kitty/releases/download/v${VERSION}/${ARCHIVE_NAME}"
readonly EXPECTED_SHA256="967a1958e7fc67b495d279c0963bcd1a0482097151817ce6506fabc822689af7"
readonly DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/rafex/kitty"
readonly INSTALL_ROOT="$DATA_ROOT/$VERSION"
readonly MARKER="$INSTALL_ROOT/.rafex-kitty-managed"
readonly MANIFEST="$DATA_ROOT/installed.env"
readonly DOWNLOAD_ROOT="$DATA_ROOT/downloads"
readonly BIN_ROOT="${HOME}/.local/bin"
readonly KITTY_LINK="$BIN_ROOT/kitty"
readonly KITTEN_LINK="$BIN_ROOT/kitten"
readonly DESKTOP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly DESKTOP_FILE="$DESKTOP_ROOT/rafex-kitty.desktop"

TMP_DIRS=()
TMP_FILES=()

cleanup() {
  local path
  for path in "${TMP_FILES[@]-}"; do
    [[ -n "$path" ]] && rm -f -- "$path"
  done
  for path in "${TMP_DIRS[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_kitty_linux.sh [opción]

Opciones:
  --check              comprueba el entorno y el archivo local sin modificar
  --plan               muestra el plan sin descargar ni instalar
  --apply              descarga si hace falta e instala Kitty en ~/.local
  --status             muestra el estado de la instalación administrada
  --archive <archivo>  utiliza un artefacto local explícito
  --help               muestra esta ayuda

La versión está fijada al release oficial de Kitty 0.48.2.
EOF
}

require_user_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "$(uname -m)" == x86_64 ]] || die 'este instalador requiere arquitectura x86_64'
  (( EUID != 0 )) || die 'ejecuta el instalador como usuario normal, no como root'
  [[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
}

require_commands() {
  local command_name
  for command_name in curl sha256sum tar file awk sed mkdir mktemp mv ln readlink install stat; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando requerido: $command_name"
  done
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--apply|--status)
        [[ "$ACTION_CHOSEN" == false ]] || die 'selecciona una sola acción'
        ACTION="${1#--}"
        ACTION_CHOSEN=true
        ;;
      --archive)
        (($# >= 2)) || die '--archive requiere un archivo'
        [[ -z "$ARCHIVE_INPUT" ]] || die '--archive solo puede aparecer una vez'
        ARCHIVE_INPUT="$2"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "opción no reconocida: $1"
        ;;
    esac
    shift
  done
}

archive_sha256() {
  sha256sum -- "$1" | awk '{ print $1; exit }'
}

validate_archive_path() {
  local archive="$1"
  [[ -f "$archive" ]] || die "no existe un archivo regular: $archive"
  [[ ! -L "$archive" ]] || die "no se aceptan enlaces simbólicos como archivo de release: $archive"
  [[ "$(stat -c '%u' "$archive" 2>/dev/null || printf -1)" == "$EUID" ]] \
    || die "el archivo debe pertenecer al usuario actual: $archive"
}

validate_archive() {
  local archive="$1" member members archive_hash
  validate_archive_path "$archive"
  archive_hash="$(archive_sha256 "$archive")"
  [[ "$archive_hash" == "$EXPECTED_SHA256" ]] \
    || die "SHA-256 incorrecto para $ARCHIVE_NAME: $archive_hash"

  members="$(tar -tJf "$archive")" || die 'el archivo no es un tar.xz legible'
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    case "$member" in
      /*|../*|*/../*|*/..|*\\*) die "ruta insegura dentro del archivo: $member" ;;
      bin/*|lib/|lib/kitty/*|share/*) ;;
      *) die "ruta inesperada dentro del archivo: $member" ;;
    esac
  done <<< "$members"

  grep -Fqx 'bin/kitty' <<< "$members" || die 'el release no contiene bin/kitty'
  grep -Fqx 'bin/kitten' <<< "$members" || die 'el release no contiene bin/kitten'

  # El release oficial no necesita enlaces ni nodos especiales para funcionar.
  tar -tvJf "$archive" \
    | awk 'substr($0, 1, 1) != "d" && substr($0, 1, 1) != "-" { bad=1 } END { exit(bad ? 1 : 0) }' \
    || die 'el archivo contiene enlaces o nodos especiales no permitidos'
  ok "artefacto verificado: $ARCHIVE_NAME"
}

xdg_download_dir() {
  if command -v xdg-user-dir >/dev/null 2>&1; then
    xdg-user-dir DOWNLOAD 2>/dev/null || true
  fi
}

find_local_archive() {
  local directory candidate
  local -a directories=()
  [[ -n "${XDG_DOWNLOAD_DIR:-}" ]] && directories+=("$XDG_DOWNLOAD_DIR")
  directory="$(xdg_download_dir)"
  [[ -n "$directory" ]] && directories+=("$directory")
  directories+=("$HOME/Descargas" "$HOME/Downloads")

  for directory in "${directories[@]}"; do
    candidate="$directory/$ARCHIVE_NAME"
    if [[ -f "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_archive() {
  local found
  if [[ -n "$ARCHIVE_INPUT" ]]; then
    validate_archive_path "$ARCHIVE_INPUT"
    printf '%s\n' "$ARCHIVE_INPUT"
    return 0
  fi
  if found="$(find_local_archive)"; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

show_install_state() {
  if [[ -f "$MARKER" ]]; then
    printf 'versión: %s\n' "$(sed -n 's/^version=//p' "$MARKER" | head -n 1)"
    printf 'instalación: %s\n' "$INSTALL_ROOT"
    printf 'SHA-256: %s\n' "$(sed -n 's/^archive_sha256=//p' "$MARKER" | head -n 1)"
  else
    printf 'instalación administrada: no instalada\n'
  fi
  if [[ -L "$KITTY_LINK" ]]; then
    printf 'kitty: %s -> %s\n' "$KITTY_LINK" "$(readlink "$KITTY_LINK")"
  else
    printf 'kitty: enlace no administrado\n'
  fi
  if [[ -L "$KITTEN_LINK" ]]; then
    printf 'kitten: %s -> %s\n' "$KITTEN_LINK" "$(readlink "$KITTEN_LINK")"
  else
    printf 'kitten: enlace no administrado\n'
  fi
  if [[ -f "$DESKTOP_FILE" ]]; then
    grep -Fq 'X-Rafex-Managed=true' "$DESKTOP_FILE" \
      && printf 'lanzador: %s\n' "$DESKTOP_FILE" \
      || printf 'lanzador: existe uno no administrado en %s\n' "$DESKTOP_FILE"
  else
    printf 'lanzador: no instalado\n'
  fi
  if command -v kitty >/dev/null 2>&1; then
    printf 'PATH: %s\n' "$(command -v kitty)"
  fi
}

show_plan() {
  local archive='no encontrado'
  if archive="$(resolve_archive 2>/dev/null)"; then
    archive="disponible: $archive"
  fi
  printf '═══ Kitty upstream %s ═══\n' "$VERSION"
  printf 'fuente: %s\n' "$DOWNLOAD_URL"
  printf 'SHA-256 esperado: %s\n' "$EXPECTED_SHA256"
  printf 'artefacto local: %s\n' "$archive"
  printf 'instalación: %s\n' "$INSTALL_ROOT"
  printf 'enlaces: %s y %s\n' "$KITTY_LINK" "$KITTEN_LINK"
  printf 'lanzador: %s\n' "$DESKTOP_FILE"
  printf '%s\n' 'No usa sudo, no modifica APT, no reemplaza Kitty del sistema y no inicia una terminal automáticamente.'
}

download_archive() {
  local temporary target
  mkdir -p -- "$DOWNLOAD_ROOT"
  chmod 700 -- "$DATA_ROOT" "$DOWNLOAD_ROOT"
  target="$DOWNLOAD_ROOT/$ARCHIVE_NAME"
  temporary="$(mktemp "$DOWNLOAD_ROOT/.${ARCHIVE_NAME}.XXXXXX")"
  TMP_FILES+=("$temporary")
  info "descargando $ARCHIVE_NAME desde el release oficial" >&2
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    "$DOWNLOAD_URL" -o "$temporary" \
    || die 'no se pudo descargar el release oficial'
  validate_archive "$temporary" >&2
  mv -f -- "$temporary" "$target"
  ok "artefacto guardado en $target" >&2
  printf '%s\n' "$target"
}

validate_payload() {
  local root="$1" version_output
  [[ -f "$root/bin/kitty" && ! -L "$root/bin/kitty" && -x "$root/bin/kitty" ]] \
    || die 'el payload no contiene un binario kitty regular y ejecutable'
  [[ -f "$root/bin/kitten" && ! -L "$root/bin/kitten" && -x "$root/bin/kitten" ]] \
    || die 'el payload no contiene un binario kitten regular y ejecutable'
  [[ -f "$root/share/icons/hicolor/256x256/apps/kitty.png" ]] \
    || die 'el payload no contiene el icono de Kitty esperado'
  file "$root/bin/kitty" | grep -Eqi 'ELF[^,]*64-bit[^,]*x86-64' \
    || die 'bin/kitty no es un ejecutable ELF x86_64'
  version_output="$("$root/bin/kitty" --version 2>/dev/null || true)"
  [[ "$version_output" == *"$VERSION"* ]] \
    || die 'el binario no reporta la versión fijada de Kitty'
}

write_marker() {
  local root="$1" archive_hash temporary
  archive_hash="$(archive_sha256 "$2")"
  temporary="$(mktemp "$root/.rafex-kitty-managed.XXXXXX")"
  TMP_FILES+=("$temporary")
  printf 'version=%s\narchive_sha256=%s\nsource_url=%s\n' \
    "$VERSION" "$archive_hash" "$DOWNLOAD_URL" > "$temporary"
  chmod 600 -- "$temporary"
  mv -f -- "$temporary" "$root/.rafex-kitty-managed"
}

atomic_link() {
  local target="$1" link="$2" temporary
  if [[ -e "$link" || -L "$link" ]]; then
    [[ -L "$link" && "$(readlink "$link")" == "$target" ]] \
      || die "el destino ya existe y no es un enlace administrado: $link"
    return 0
  fi
  temporary="$(mktemp "${link}.XXXXXX")"
  TMP_FILES+=("$temporary")
  rm -f -- "$temporary"
  ln -s -- "$target" "$temporary"
  mv -f -- "$temporary" "$link"
}

write_desktop_file() {
  local temporary
  if [[ -e "$DESKTOP_FILE" || -L "$DESKTOP_FILE" ]]; then
    [[ -f "$DESKTOP_FILE" && ! -L "$DESKTOP_FILE" ]] \
      || die "el lanzador ya existe y no es un archivo administrado: $DESKTOP_FILE"
    grep -Fq 'X-Rafex-Managed=true' "$DESKTOP_FILE" \
      || die "el lanzador existente no está administrado por Rafex: $DESKTOP_FILE"
  fi
  temporary="$(mktemp "$DESKTOP_ROOT/.rafex-kitty.desktop.XXXXXX")"
  TMP_FILES+=("$temporary")
  cat > "$temporary" <<EOF
[Desktop Entry]
Type=Application
Name=Kitty (Rafex)
Comment=Terminal Kitty ${VERSION}
Exec=${KITTY_LINK}
TryExec=${KITTY_LINK}
Icon=${INSTALL_ROOT}/share/icons/hicolor/256x256/apps/kitty.png
Terminal=false
Categories=System;TerminalEmulator;
StartupWMClass=kitty
X-Rafex-Managed=true
EOF
  chmod 644 -- "$temporary"
  mv -f -- "$temporary" "$DESKTOP_FILE"
}

write_manifest() {
  local archive="$1" archive_hash temporary
  archive_hash="$(archive_sha256 "$archive")"
  temporary="$(mktemp "$DATA_ROOT/.installed.env.XXXXXX")"
  TMP_FILES+=("$temporary")
  printf 'version=%s\narchive=%s\narchive_sha256=%s\ninstall_root=%s\n' \
    "$VERSION" "$archive" "$archive_hash" "$INSTALL_ROOT" > "$temporary"
  chmod 600 -- "$temporary"
  mv -f -- "$temporary" "$MANIFEST"
}

install_payload() {
  local archive="$1" stage archive_hash
  archive_hash="$(archive_sha256 "$archive")"
  mkdir -p -- "$DATA_ROOT" "$BIN_ROOT" "$DESKTOP_ROOT"
  chmod 700 -- "$DATA_ROOT"

  if [[ -d "$INSTALL_ROOT" ]]; then
    [[ -f "$MARKER" ]] || die "la instalación existente no está administrada: $INSTALL_ROOT"
    [[ "$(sed -n 's/^archive_sha256=//p' "$MARKER" | head -n 1)" == "$archive_hash" ]] \
      || die "ya existe una instalación administrada con otro checksum; no se sobrescribirá"
    ok "Kitty $VERSION ya está instalado con el checksum esperado"
  else
    [[ ! -e "$INSTALL_ROOT" && ! -L "$INSTALL_ROOT" ]] \
      || die "la ruta de instalación ya existe y no está administrada: $INSTALL_ROOT"
    stage="$(mktemp -d "$DATA_ROOT/.staging.XXXXXX")"
    TMP_DIRS+=("$stage")
    tar -xJf "$archive" -C "$stage" --no-same-owner --no-same-permissions
    validate_payload "$stage"
    write_marker "$stage" "$archive"
    mv -- "$stage" "$INSTALL_ROOT"
    ok "Kitty $VERSION instalado en $INSTALL_ROOT"
  fi

  atomic_link "$INSTALL_ROOT/bin/kitty" "$KITTY_LINK"
  atomic_link "$INSTALL_ROOT/bin/kitten" "$KITTEN_LINK"
  write_desktop_file
  write_manifest "$archive"
  ok 'enlaces y lanzador publicados de forma idempotente'
}

main() {
  local archive
  parse_args "$@"
  require_user_linux
  require_commands
  case "$ACTION" in
    check)
      show_plan
      if archive="$(resolve_archive 2>/dev/null)"; then
        validate_archive "$archive"
      else
        warn "no se encontró $ARCHIVE_NAME en Descargas; --apply lo descargará desde la URL fijada"
      fi
      ;;
    plan)
      show_plan
      ;;
    status)
      show_install_state
      ;;
    apply)
      archive="$(resolve_archive 2>/dev/null || download_archive)"
      validate_archive "$archive"
      install_payload "$archive"
      ;;
  esac
}

main "$@"
