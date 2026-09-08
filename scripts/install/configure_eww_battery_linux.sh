#!/usr/bin/env bash
# configure_eww_battery_linux.sh v1.1.0
# Compatibilidad histórica: la telemetría ya pertenece al dashboard EWW.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

readonly VERSION="v1.1.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly SOURCE_HELPER="${REPO_ROOT}/scripts/system/eww_battery_status_linux.sh"
readonly TARGET_HELPER="$HOME/.local/bin/eww-battery-status.sh"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"
readonly TARGET_YUCK="${CONFIG_ROOT}/eww.yuck"
readonly BEGIN_POLL=";; BEGIN rafex EWW battery telemetry"
readonly BEGIN_CARD=";; BEGIN rafex EWW battery telemetry card"

ACTION=check

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_eww_battery_linux.sh --check
  configure_eww_battery_linux.sh --plan
  configure_eww_battery_linux.sh --status
  configure_eww_battery_linux.sh --apply
  configure_eww_battery_linux.sh --rollback

Valida la telemetría EWW integrada por install_eww_linux.sh: AC, carga,
estado y salud estimada. No edita eww.yuck para evitar dos propietarios.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --status) ACTION=status ;;
      --apply) ACTION=apply ;;
      --rollback) ACTION=rollback ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal'
}

require_commands() {
  local command_name
  for command_name in awk cmp cp date grep install mktemp mv rm; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
}

validate_source() {
  [[ -s "$SOURCE_HELPER" ]] || die "falta el helper: $SOURCE_HELPER"
  [[ -s "$TARGET_YUCK" ]] || die "falta $TARGET_YUCK; ejecuta primero just install-eww --apply"
  grep -Fq 'BEGIN rafex EWW dashboard' "$TARGET_YUCK" || die 'el Yuck no parece una configuración EWW administrada'
}

show_status() {
  echo "═══ Telemetría de batería EWW ${VERSION} ═══"
  printf 'configuración=%s\n' "$TARGET_YUCK"
  printf 'helper=%s\n' "$TARGET_HELPER"
  if [[ -x "$TARGET_HELPER" ]]; then
    ok 'helper instalado'
  else
    warn 'helper no instalado'
  fi
  if [[ -f "$TARGET_YUCK" ]] && grep -Fqx "$BEGIN_POLL" "$TARGET_YUCK" && grep -Fqx "$BEGIN_CARD" "$TARGET_YUCK"; then
    ok 'bloques EWW administrados presentes'
  else
    warn 'bloques EWW administrados ausentes'
  fi
  if [[ -n "${DISPLAY:-}" && -x "$HOME/.local/bin/eww-widgets.sh" ]]; then
    info 'puedes recargar con: just eww-widgets --reload'
  else
    info 'sin DISPLAY o helper EWW; no se recarga automáticamente'
  fi
}

apply_config() {
  validate_source
  ok 'telemetría EWW ya está integrada; install-eww es su único instalador'
  info 'no se modifica eww.yuck para evitar que dos instaladores compongan el mismo archivo'
}

rollback_config() {
  die 'rollback bloqueado: la telemetría forma parte del dashboard administrado; usa install-eww o el rollback central'
}

main() {
  parse_args "$@"
  require_linux_user
  require_commands
  case "$ACTION" in
    check)
      validate_source
      ok 'configuración EWW y helper fuente válidos; no se modificó nada'
      ;;
    plan)
      validate_source
      echo "═══ Plan telemetría batería EWW ═══"
      info "instalar $TARGET_HELPER"
      info "verificar que install-eww ya integró el defpoll de 10s y la tarjeta en $TARGET_YUCK"
      info 'recargar únicamente la instancia EWW administrada si DISPLAY está disponible'
      info 'no ejecutar watch, sudo ni comandos de energía'
      ;;
    status) show_status ;;
    apply) apply_config ;;
    rollback) rollback_config ;;
  esac
}

main "$@"
