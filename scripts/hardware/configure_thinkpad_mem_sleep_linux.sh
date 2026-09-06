#!/usr/bin/env bash
# shellcheck shell=bash
# Hace permanente un modo de suspensión (mem_sleep_default) en GRUB para la
# ThinkPad X1 Yoga: s2idle (default) o deep. Un solo script administra el
# parámetro para que dos configuraciones no compitan por la misma línea de
# GRUB_CMDLINE_LINUX_DEFAULT.
set -Eeuo pipefail
umask 077

ACTION="check"
MODE="s2idle"
GRUB_FILE="/etc/default/grub"
BACKUP_ROOT="/var/backups/rafex-thinkpad-mem-sleep"
STAMP="$(date +%Y%m%d_%H%M%S)"
TEMPORARY_FILE=""

cleanup() {
  if [[ -n "$TEMPORARY_FILE" ]]; then
    rm -f -- "$TEMPORARY_FILE"
  fi
  # El trap EXIT nunca debe convertir una ejecución exitosa en código 1.
  return 0
}
trap cleanup EXIT

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
  configure_thinkpad_mem_sleep_linux.sh --check
  configure_thinkpad_mem_sleep_linux.sh --plan [--mode s2idle|deep]
  configure_thinkpad_mem_sleep_linux.sh --apply [--mode s2idle|deep]

Opciones:
  --check                Mostrar el estado sin modificar nada (default)
  --plan | --dry-run     Mostrar cambios previstos sin modificar
  --apply                Respaldar GRUB, añadir mem_sleep_default=<modo> y ejecutar update-grub
  --mode s2idle|deep      Modo a persistir; por defecto s2idle
  --help                  Mostrar esta ayuda

No reinicia el equipo automáticamente. El nuevo modo se activa después de
reiniciar y se verifica con /sys/power/mem_sleep. Antes de --apply, prueba
el modo en runtime (no persiste, no toca GRUB):

  echo <modo> | sudo tee /sys/power/mem_sleep
  systemctl suspend
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --mode)
        [[ $# -ge 2 ]] || die '--mode requiere un valor'
        MODE="$2"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  case "$MODE" in
    s2idle|deep) ;;
    *) die "modo no soportado: $MODE (usa s2idle o deep)" ;;
  esac
}

available_modes() {
  cat /sys/power/mem_sleep 2>/dev/null | tr -d '[]' || true
}

warn_if_mode_unavailable() {
  local available
  available="$(available_modes)"
  [[ -n "$available" ]] || return 0
  if ! grep -qw "$MODE" <<<"$available"; then
    warn "el kernel no ofrece '$MODE' en /sys/power/mem_sleep (disponibles: $available)"
  fi
}

show_status() {
  local cmdline=""
  if [[ -r /proc/cmdline ]]; then
    cmdline="$(grep -oE '(^| )mem_sleep_default=[^ ]+' /proc/cmdline | sed 's/^ //' || true)"
  fi
  echo "═══ Suspensión ThinkPad: mem_sleep_default (objetivo: $MODE) ═══"
  printf 'mem_sleep_actual='
  cat /sys/power/mem_sleep 2>/dev/null || echo desconocido
  printf 'kernel_parameter=%s\n' "${cmdline:-ausente}"
  if [[ -r "$GRUB_FILE" ]]; then
    grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" || \
      printf 'GRUB_CMDLINE_LINUX_DEFAULT=%s\n' ausente
    if grep -Eq "(^|[[:space:]])mem_sleep_default=${MODE}([[:space:]]|\"|\$)" "$GRUB_FILE"; then
      ok "GRUB ya contiene mem_sleep_default=$MODE"
    else
      warn "GRUB todavía no contiene mem_sleep_default=$MODE"
    fi
  else
    warn "no se puede leer $GRUB_FILE"
  fi
  warn_if_mode_unavailable
  # Un estado pendiente es un diagnóstico, no un error de ejecución.
  return 0
}

render_grub() {
  local destination="$1" count
  count="$(grep -Ec '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" || true)"
  case "$count" in
    0)
      cp -a -- "$GRUB_FILE" "$destination"
      printf '\nGRUB_CMDLINE_LINUX_DEFAULT="mem_sleep_default=%s"\n' "$MODE" >> "$destination"
      ;;
    1)
      grep -Eq '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"[[:space:]]*$' "$GRUB_FILE" || \
        die "$GRUB_FILE usa un formato no compatible; revisa GRUB_CMDLINE_LINUX_DEFAULT manualmente"
      sed -E \
        -e '/^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ s/(^|[[:space:]])mem_sleep_default=[^[:space:]\"]+/\1/g' \
        -e "/^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ s/^([[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"[[:space:]]*\$/\1 mem_sleep_default=${MODE}\"/" \
        "$GRUB_FILE" > "$destination"
      ;;
    *)
      die "$GRUB_FILE contiene múltiples líneas GRUB_CMDLINE_LINUX_DEFAULT"
      ;;
  esac
}

backup_grub() {
  local backup="${BACKUP_ROOT}/grub.bak.${STAMP}" suffix=1
  sudo install -d -m 700 "$BACKUP_ROOT"
  while sudo test -e "$backup"; do
    backup="${BACKUP_ROOT}/grub.bak.${STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  sudo cp -a -- "$GRUB_FILE" "$backup"
  printf '%s\n' "$backup"
}

apply_mode() {
  local temporary backup
  command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
  sudo -v
  [[ -f "$GRUB_FILE" ]] || die "no existe $GRUB_FILE"
  warn_if_mode_unavailable
  temporary="$(mktemp)"
  TEMPORARY_FILE="$temporary"
  render_grub "$temporary"
  if sudo cmp -s "$temporary" "$GRUB_FILE"; then
    ok "GRUB ya está configurado con $MODE; no se modificó"
    rm -f -- "$temporary"
    TEMPORARY_FILE=""
    return 0
  fi

  backup="$(backup_grub)"
  sudo install -o root -g root -m 644 "$temporary" "$GRUB_FILE"
  info "GRUB actualizado; respaldo: $backup"
  if ! sudo update-grub; then
    warn "update-grub falló; restaurando el respaldo"
    sudo cp -a -- "$backup" "$GRUB_FILE"
    die "no se aplicó la configuración de $MODE"
  fi
  if sudo grep -Eq "(^|[[:space:]])mem_sleep_default=${MODE}([[:space:]]|\"|\$)" "$GRUB_FILE"; then
    ok "mem_sleep_default=$MODE quedó configurado; reinicia para activarlo"
  else
    die "no se pudo verificar el parámetro en $GRUB_FILE"
  fi
  rm -f -- "$temporary"
  TEMPORARY_FILE=""
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die "este script requiere Linux"
  case "$ACTION" in
    check)
      show_status
      ;;
    plan)
      show_status
      info "[plan] respaldar $GRUB_FILE en $BACKUP_ROOT"
      info "[plan] añadir o reemplazar mem_sleep_default=$MODE en GRUB_CMDLINE_LINUX_DEFAULT"
      info "[plan] ejecutar sudo update-grub"
      warn "no se reiniciará automáticamente"
      return 0
      ;;
    apply)
      apply_mode
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
