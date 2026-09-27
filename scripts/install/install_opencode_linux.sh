#!/usr/bin/env bash
# v1.0.0 — Instala OpenCode oficial para el usuario de la ThinkPad, sin root.
set -Eeuo pipefail
umask 077

export PATH="${HOME}/.local/bin:${PATH:-}"

ACTION='check'
ACTION_SELECTED=false
REQUESTED_VERSION=''
ORIGINAL="${HOME}/.opencode/bin/opencode"
ACTIVE="${HOME}/.local/bin/opencode"
INSTALLER_URL='https://opencode.ai/install'
LOCK_DIR="${HOME}/.opencode/.rafex-install.lock"
BACKUP_DIR=''
STAGE=''
RESTORE=false
ORIGINAL_PRESENT=false
ACTIVE_PRESENT=false

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_opencode_linux.sh --check
  install_opencode_linux.sh --plan
  install_opencode_linux.sh --status
  install_opencode_linux.sh --apply [--version X.Y.Z]

Instala OpenCode desde https://opencode.ai/install en:
  ~/.opencode/bin/opencode   instalación oficial
  ~/.local/bin/opencode      copia administrada por el perfil Rafex

No usa sudo, no configura credenciales y no modifica PATH ni archivos de shell.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--status|--apply)
        [[ "$ACTION_SELECTED" == false ]] || die 'selecciona una sola acción'
        ACTION="${1#--}"
        ACTION_SELECTED=true
        ;;
      --version)
        (($# >= 2)) || die '--version requiere X.Y.Z'
        [[ -z "$REQUESTED_VERSION" ]] || die '--version no puede repetirse'
        REQUESTED_VERSION="${2#v}"
        [[ "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
          die 'la versión debe tener el formato X.Y.Z'
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el instalador como usuario normal, no como root'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] ||
    die 'este instalador requiere Debian o un derivado compatible'
  [[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
}

require_commands() {
  local command_name
  for command_name in bash cmp cp date env head install mkdir mktemp mv rm rmdir tr; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando: $command_name"
  done
  if [[ "$ACTION" == apply ]]; then
    command -v curl >/dev/null 2>&1 || die 'falta el comando: curl'
  fi
}

validate_directory_path() {
  local path="$1"
  if [[ -L "$path" ]]; then
    die "no se acepta un enlace simbólico en la ruta administrada: $path"
  fi
}

validate_binary_path() {
  local path="$1"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ ! -L "$path" ]] || die "no se acepta un enlace simbólico: $path"
  [[ -f "$path" && -x "$path" && -O "$path" ]] ||
    die "el archivo existe pero no es un binario ejecutable propio: $path"
}

prepare_paths() {
  validate_directory_path "${HOME}/.opencode"
  validate_directory_path "${HOME}/.opencode/bin"
  validate_directory_path "${HOME}/.local"
  validate_directory_path "${HOME}/.local/bin"
  validate_binary_path "$ORIGINAL"
  validate_binary_path "$ACTIVE"
  [[ -f "$ORIGINAL" ]] && ORIGINAL_PRESENT=true
  [[ -f "$ACTIVE" ]] && ACTIVE_PRESENT=true
}

binary_version() {
  local path="$1" output
  output="$("$path" --version 2>/dev/null | head -n 1 | tr -d '\r')" || return 1
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$output"
}

show_binary() {
  local label="$1" path="$2" version
  if [[ -f "$path" ]]; then
    version="$(binary_version "$path" 2>/dev/null || printf 'invalid')"
    printf '%s=%s (%s)\n' "$label" "$path" "$version"
  else
    printf '%s=missing\n' "$label"
  fi
}

show_status() {
  local resolved
  echo '═══ OpenCode — ThinkPad ═══'
  printf 'source=%s\n' "$INSTALLER_URL"
  show_binary official "$ORIGINAL"
  show_binary rafex "$ACTIVE"
  if resolved="$(command -v opencode 2>/dev/null)"; then
    printf 'path=%s\n' "$resolved"
  else
    printf 'path=missing\n'
  fi
  if [[ -d "$HOME/.opencode" ]]; then
    printf 'backup_root=%s\n' "$HOME/.opencode"
  fi
}

show_plan() {
  printf '═══ Plan OpenCode ═══\n'
  info "descargar el instalador oficial por HTTPS desde $INSTALLER_URL"
  info 'validar su sintaxis antes de ejecutarlo'
  info "instalar la versión ${REQUESTED_VERSION:-estable seleccionada por el proveedor}"
  info "sincronizar la copia Rafex en $ACTIVE"
  info 'crear un respaldo privado y no modificar credenciales ni PATH'
}

backup_existing() {
  local stamp
  mkdir -p -- "${HOME}/.opencode"
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="$(mktemp -d "${HOME}/.opencode/rafex-install-${stamp}.XXXXXX")"
  if [[ "$ORIGINAL_PRESENT" == true ]]; then
    cp -p -- "$ORIGINAL" "$BACKUP_DIR/original"
  fi
  if [[ "$ACTIVE_PRESENT" == true ]]; then
    cp -p -- "$ACTIVE" "$BACKUP_DIR/active"
  fi
}

restore_existing() {
  if [[ "$ORIGINAL_PRESENT" == true ]]; then
    install -m 755 -- "$BACKUP_DIR/original" "$ORIGINAL"
  else
    rm -f -- "$ORIGINAL"
  fi
  if [[ "$ACTIVE_PRESENT" == true ]]; then
    install -m 755 -- "$BACKUP_DIR/active" "$ACTIVE"
  else
    rm -f -- "$ACTIVE"
  fi
}

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$RESTORE" == true && -n "$BACKUP_DIR" ]]; then
    warn 'la instalación falló; restaurando los binarios anteriores'
    restore_existing || rc=1
  fi
  [[ -z "$STAGE" ]] || rm -f -- "$STAGE"
  [[ -z "$LOCK_DIR" ]] || rmdir -- "$LOCK_DIR" 2>/dev/null || true
  exit "$rc"
}

apply_installation() {
  local installer installed
  command -v curl >/dev/null 2>&1 || die 'curl es necesario para --apply'
  mkdir -p -- "${HOME}/.opencode" "${HOME}/.local/bin"
  mkdir -- "$LOCK_DIR" 2>/dev/null ||
    die 'actualización bloqueada; revisa si otra instalación sigue activa'
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  backup_existing
  installer="$(mktemp "${HOME}/.opencode/.rafex-installer.XXXXXX")"
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 "$INSTALLER_URL" -o "$installer" || die 'no se pudo descargar el instalador oficial'
  bash -n "$installer" || die 'el instalador descargado no supera la validación de sintaxis'

  RESTORE=true
  if [[ -n "$REQUESTED_VERSION" ]]; then
    env -u VERSION bash "$installer" --no-modify-path --version "$REQUESTED_VERSION"
  else
    env -u VERSION bash "$installer" --no-modify-path
  fi
  [[ -f "$ORIGINAL" && -x "$ORIGINAL" && -O "$ORIGINAL" ]] ||
    die "el instalador no creó $ORIGINAL"
  installed="$(binary_version "$ORIGINAL" || true)"
  [[ -n "$installed" ]] || die 'la versión instalada no es válida'
  [[ -z "$REQUESTED_VERSION" || "$installed" == "$REQUESTED_VERSION" ]] ||
    die "se solicitó $REQUESTED_VERSION pero se obtuvo $installed"

  STAGE="$(mktemp "${HOME}/.local/bin/.opencode-install.XXXXXX")"
  install -m 755 -- "$ORIGINAL" "$STAGE"
  [[ "$(binary_version "$STAGE")" == "$installed" ]] ||
    die 'la copia Rafex no supera la validación de versión'
  mv -f -- "$STAGE" "$ACTIVE"
  STAGE=''
  cmp -s -- "$ORIGINAL" "$ACTIVE" || die 'las instalaciones no coinciden'
  RESTORE=false
  printf 'OpenCode instalado: %s\n' "$installed"
  printf 'Respaldo: %s\n' "$BACKUP_DIR"
}

main() {
  parse_args "$@"
  require_linux_debian
  require_commands
  prepare_paths
  case "$ACTION" in
    check|status)
      show_status
      ;;
    plan)
      show_status
      show_plan
      ;;
    apply)
      apply_installation
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
