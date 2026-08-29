#!/usr/bin/env bash
# shellcheck shell=bash
# Activa el temporizador periódico de mantenimiento TRIM para SSD/NVMe.
set -Eeuo pipefail
umask 077

ACTION='check'
UNIT='fstrim.timer'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_fstrim_linux.sh --check
  configure_fstrim_linux.sh --plan
  configure_fstrim_linux.sh --apply
  configure_fstrim_linux.sh --status

Opciones:
  --check       Mostrar el estado sin modificar nada (default)
  --plan        Mostrar las acciones previstas sin modificar nada
  --dry-run     Alias de --plan
  --apply       Habilitar e iniciar fstrim.timer mediante sudo
  --status      Mostrar el estado y la próxima ejecución del temporizador
  --help        Mostrar esta ayuda

El script no ejecuta fstrim inmediatamente y no modifica fstab, GRUB ni las
opciones de montaje del NVMe.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION='check' ;;
      --plan|--dry-run) ACTION='plan' ;;
      --apply) ACTION='apply' ;;
      --status) ACTION='status' ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

show_status() {
  echo '═══ TRIM periódico para SSD/NVMe ═══'
  if ! command -v systemctl >/dev/null 2>&1; then
    warn 'systemctl no está disponible; se requiere Debian con systemd'
    return 0
  fi

  printf 'unidad=%s\n' "$UNIT"
  printf 'instalada='; systemctl cat "$UNIT" >/dev/null 2>&1 && echo sí || echo no
  printf 'habilitada='; systemctl is-enabled "$UNIT" 2>/dev/null || echo no
  printf 'activa='; systemctl is-active "$UNIT" 2>/dev/null || echo no
  printf 'próxima_ejecución='; systemctl list-timers "$UNIT" --no-legend 2>/dev/null || echo no-disponible
  return 0
}

apply_mode() {
  command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  command -v systemctl >/dev/null 2>&1 || die 'systemctl no está disponible'
  sudo -v
  sudo systemctl enable --now "$UNIT"
  systemctl is-enabled "$UNIT" >/dev/null || die "$UNIT no quedó habilitado"
  systemctl is-active "$UNIT" >/dev/null || die "$UNIT no quedó activo"
  ok "$UNIT habilitado y activo"
  info 'TRIM se ejecutará según el calendario de systemd; no se ejecutó fstrim manualmente'
  show_status
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script requiere Linux'

  case "$ACTION" in
    check|status)
      show_status
      ;;
    plan)
      show_status
      info '[plan] sudo -v'
      info "[plan] sudo systemctl enable --now $UNIT"
      info '[plan] verificar estado y próxima ejecución'
      ;;
    apply)
      apply_mode
      ;;
    *) die 'acción inválida' ;;
  esac
}

main "$@"
