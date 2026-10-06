#!/usr/bin/env bash
# install_nas_client_linux.sh v1.0.0
# Instala el cliente CIFS requerido para montar recursos SMB/NAS en Linux.
set -Eeuo pipefail

ACTION=check
PACKAGE=cifs-utils

usage() {
  cat <<'EOF'
Uso:
  install_nas_client_linux.sh --check|--plan|--apply
  install_nas_client_linux.sh --help

Instala solo el cliente CIFS (cifs-utils), que proporciona mount.cifs.
No instala ni configura un servidor Samba.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check; shift ;;
      --plan|--dry-run) ACTION=plan; shift ;;
      --apply) ACTION=apply; shift ;;
      --help|-h) usage; exit 0 ;;
      *) printf 'Error: argumento desconocido: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

installed() {
  local status
  status="$(dpkg-query -W -f='Status' "$PACKAGE" 2>/dev/null || true)"
  [[ "$status" == 'install ok installed' ]]
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || {
    printf 'Error: este instalador requiere Linux.\n' >&2
    exit 1
  }
  command -v dpkg-query >/dev/null 2>&1 || {
    printf 'Error: dpkg-query no está disponible; este instalador requiere Debian/Ubuntu.\n' >&2
    exit 1
  }

  if installed; then
    printf 'cifs-utils ya está instalado.\n'
    if command -v mount.cifs >/dev/null 2>&1; then
      printf 'mount.cifs: %s\n' "$(command -v mount.cifs)"
    else
      printf 'Aviso: el paquete está instalado pero mount.cifs no aparece en PATH.\n' >&2
      exit 1
    fi
    return 0
  fi

  case "$ACTION" in
    check)
      printf 'Falta %s. Ejecuta: just install-nas-client --apply\n' "$PACKAGE"
      return 1
      ;;
    plan)
      printf '[plan] sudo apt-get update\n'
      printf '[plan] sudo apt-get install -y --no-install-recommends %s\n' "$PACKAGE"
      ;;
    apply)
      command -v apt-get >/dev/null 2>&1 || {
        printf 'Error: apt-get no está disponible.\n' >&2
        exit 1
      }
      command -v sudo >/dev/null 2>&1 || {
        printf 'Error: sudo no está disponible.\n' >&2
        exit 1
      }
      sudo -v
      sudo apt-get update
      sudo apt-get install -y --no-install-recommends "$PACKAGE"
      command -v mount.cifs >/dev/null 2>&1 || {
        printf 'Error: la instalación terminó, pero mount.cifs no está en PATH.\n' >&2
        exit 1
      }
      printf 'Cliente CIFS instalado: %s\n' "$(command -v mount.cifs)"
      ;;
  esac
}

main "$@"
