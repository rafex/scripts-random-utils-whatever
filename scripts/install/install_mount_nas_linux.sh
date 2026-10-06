#!/usr/bin/env bash
# install_mount_nas_linux.sh v1.0.0
# Instala un comando autónomo mountNas en ~/.local/bin.
set -Eeuo pipefail
umask 077

ACTION=check
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/scripts/network/connect_nas_linux.sh"
TARGET="${NAS_INSTALL_TARGET:-$HOME/.local/bin/mountNas}"
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_mount_nas_linux.sh --check|--plan|--apply|--status
  install_mount_nas_linux.sh --help

Instala mountNas en ~/.local/bin. Después de instalarlo, el comando no requiere
el repositorio: usa los valores y credenciales locales de ~/.config/samba.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

install_helper() {
  local target_dir temporary backup
  target_dir="$(dirname -- "$TARGET")"
  if [[ "$ACTION" == plan ]]; then
    printf '[plan] instalar %s desde %s\n' "$TARGET" "$SOURCE"
    return 0
  fi
  [[ "$ACTION" == apply ]] || return 0
  mkdir -p -- "$target_dir"
  if [[ -f "$TARGET" ]] && cmp -s -- "$SOURCE" "$TARGET"; then
    chmod 0755 -- "$TARGET"
    printf 'mountNas ya está actualizado: %s\n' "$TARGET"
    return 0
  fi
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    backup="$TARGET.bak.$STAMP"
    [[ ! -e "$backup" && ! -L "$backup" ]] || die "ya existe el respaldo $backup"
    cp -a -- "$TARGET" "$backup"
    printf 'Respaldo: %s\n' "$backup"
  fi
  temporary="$(mktemp "$target_dir/.mountNas.XXXXXX")"
  if ! install -m 0755 -- "$SOURCE" "$temporary"; then
    rm -f -- "$temporary"
    die 'no se pudo preparar mountNas'
  fi
  mv -f -- "$temporary" "$TARGET"
  printf 'Comando instalado: %s\n' "$TARGET"
  case ":${PATH}:" in
    *":$target_dir:"*) ;;
    *) printf 'Aviso: agrega %s a PATH para ejecutar mountNas directamente.\n' "$target_dir" >&2 ;;
  esac
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -f "$SOURCE" ]] || die "no se encuentra el script fuente: $SOURCE"
  case "$ACTION" in
    check|status)
      if [[ -x "$TARGET" ]] && cmp -s -- "$SOURCE" "$TARGET"; then
        printf 'mountNas instalado y actualizado: %s\n' "$TARGET"
      elif [[ -e "$TARGET" || -L "$TARGET" ]]; then
        printf 'mountNas existe pero necesita actualizarse: %s\n' "$TARGET"
        [[ "$ACTION" == status ]] || return 1
      else
        printf 'mountNas no está instalado. Ejecuta: just install-mount-nas --apply\n'
        [[ "$ACTION" == status ]] || return 1
      fi
      ;;
    plan|apply) install_helper ;;
  esac
}

main "$@"
