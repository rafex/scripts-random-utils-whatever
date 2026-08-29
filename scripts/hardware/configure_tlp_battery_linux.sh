#!/usr/bin/env bash
# shellcheck shell=bash
# Configura umbrales de carga TLP para prolongar la vida de la batería.
set -Eeuo pipefail
umask 077

ACTION='check'
START_THRESHOLD=75
STOP_THRESHOLD=80
CONFIG_FILE='/etc/tlp.d/90-rafex-battery.conf'
BACKUP_ROOT='/var/backups/rafex-tlp-battery'
STAMP="$(date +%Y%m%d_%H%M%S)"
TEMPORARY_FILE=''

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

cleanup() {
  [[ -n "$TEMPORARY_FILE" ]] && rm -f -- "$TEMPORARY_FILE"
  return 0
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  configure_tlp_battery_linux.sh --check
  configure_tlp_battery_linux.sh --plan
  configure_tlp_battery_linux.sh --apply
  configure_tlp_battery_linux.sh --fullcharge

Opciones:
  --start <porcentaje>  Umbral de inicio de carga (default: 75)
  --stop <porcentaje>   Umbral de parada de carga (default: 80)
  --check               Mostrar estado sin modificar nada (default)
  --plan | --dry-run    Mostrar cambios sin modificar nada
  --apply               Configurar TLP y aplicar los umbrales mediante sudo
  --fullcharge          Cargar temporalmente hasta el 100%; requiere sudo
  --help | -h           Mostrar esta ayuda

Los umbrales se escriben en /etc/tlp.d/90-rafex-battery.conf y se aplican
inmediatamente con `tlp setcharge`. --fullcharge no cambia esa configuración.
EOF
}

parse_percentage() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name debe ser un entero entre 0 y 100"
  ((value >= 0 && value <= 100)) || die "$name debe estar entre 0 y 100"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --start)
        (($# >= 2)) || die '--start requiere un porcentaje'
        START_THRESHOLD="$2"
        shift
        ;;
      --stop)
        (($# >= 2)) || die '--stop requiere un porcentaje'
        STOP_THRESHOLD="$2"
        shift
        ;;
      --check) ACTION='check' ;;
      --plan|--dry-run) ACTION='plan' ;;
      --apply) ACTION='apply' ;;
      --fullcharge) ACTION='fullcharge' ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  parse_percentage '--start' "$START_THRESHOLD"
  parse_percentage '--stop' "$STOP_THRESHOLD"
  ((START_THRESHOLD < STOP_THRESHOLD)) || die '--start debe ser menor que --stop'
}

require_linux() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script requiere Linux'
  command -v systemctl >/dev/null 2>&1 || warn 'systemctl no está disponible'
  if [[ "$ACTION" == 'apply' || "$ACTION" == 'fullcharge' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
    sudo -v
  fi
}

batteries() {
  local path name found=0
  for path in /sys/class/power_supply/BAT*; do
    [[ -d "$path" ]] || continue
    name="${path##*/}"
    case "$name" in
      BAT0|BAT1)
        printf '%s\n' "$name"
        found=1
        ;;
      *)
        warn "batería no reconocida para TLP: $name"
        ;;
    esac
  done
  ((found == 1)) || return 1
}

render_config() {
  local battery
  cat <<'EOF'
# >>> rafex TLP battery managed >>>
# Umbrales conservadores para reducir ciclos y mantener la batería entre 75-80%.
EOF
  while IFS= read -r battery; do
    printf 'START_CHARGE_THRESH_%s=%s\n' "$battery" "$START_THRESHOLD"
    printf 'STOP_CHARGE_THRESH_%s=%s\n' "$battery" "$STOP_THRESHOLD"
  done < <(batteries)
  cat <<'EOF'
# <<< rafex TLP battery managed <<<
EOF
}

show_tlp_status() {
  local detected_batteries=()
  echo '═══ Batería ThinkPad gestionada por TLP ═══'
  printf 'start_threshold=%s%%\n' "$START_THRESHOLD"
  printf 'stop_threshold=%s%%\n' "$STOP_THRESHOLD"
  printf 'config=%s\n' "$CONFIG_FILE"
  mapfile -t detected_batteries < <(batteries || true)
  if ((${#detected_batteries[@]} > 0)); then
    printf 'batteries=%s\n' "${detected_batteries[*]}"
  else
    warn 'no se detectó una batería BAT0/BAT1'
  fi
  if command -v tlp >/dev/null 2>&1; then
    ok 'tlp=available'
    tlp-stat -s 2>/dev/null || warn 'no se pudo consultar tlp-stat -s'
    tlp-stat -b 2>/dev/null || warn 'no se pudo consultar tlp-stat -b'
  else
    warn 'tlp=missing'
  fi
  if [[ -r "$CONFIG_FILE" ]]; then
    ok "configuración presente: $CONFIG_FILE"
    sed -n '/^START_CHARGE_THRESH_BAT[01]=/p;/^STOP_CHARGE_THRESH_BAT[01]=/p' "$CONFIG_FILE"
  else
    warn "configuración ausente: $CONFIG_FILE"
  fi
  return 0
}

backup_config() {
  local backup="$BACKUP_ROOT/tlp-battery.conf.bak.$STAMP" suffix=1
  sudo install -d -m 0700 "$BACKUP_ROOT"
  while sudo test -e "$backup"; do
    backup="$BACKUP_ROOT/tlp-battery.conf.bak.$STAMP.$suffix"
    suffix=$((suffix + 1))
  done
  sudo cp -a -- "$CONFIG_FILE" "$backup"
  printf '%s\n' "$backup"
}

install_config() {
  local backup='' changed=0
  TEMPORARY_FILE="$(mktemp)"
  render_config > "$TEMPORARY_FILE"
  if sudo test -r "$CONFIG_FILE" && sudo cmp -s "$TEMPORARY_FILE" "$CONFIG_FILE"; then
    ok 'configuración 75/80 ya estaba instalada'
  else
    changed=1
    if sudo test -e "$CONFIG_FILE"; then
      backup="$(backup_config)"
    fi
    sudo install -d -m 0755 "$(dirname "$CONFIG_FILE")"
    sudo install -o root -g root -m 0644 "$TEMPORARY_FILE" "$CONFIG_FILE"
    if [[ -n "$backup" ]]; then
      info "respaldo creado: $backup"
    fi
    ok "configuración instalada: $CONFIG_FILE"
  fi

  if ! sudo tlp setcharge "$START_THRESHOLD" "$STOP_THRESHOLD"; then
    if ((changed == 1)); then
      if [[ -n "$backup" ]]; then
        sudo cp -a -- "$backup" "$CONFIG_FILE"
      else
        sudo rm -f -- "$CONFIG_FILE"
      fi
    fi
    die 'TLP no pudo aplicar los umbrales; se restauró la configuración anterior'
  fi
  if systemctl list-unit-files tlp.service >/dev/null 2>&1; then
    sudo systemctl enable --now tlp.service
  fi
  ok "TLP aplica inicio ${START_THRESHOLD}% y parada ${STOP_THRESHOLD}%"
}

fullcharge() {
  command -v tlp >/dev/null 2>&1 || die 'tlp no está instalado; ejecuta --apply primero'
  warn 'fullcharge desactiva temporalmente el límite y permite cargar al 100%'
  sudo tlp fullcharge
  ok 'carga completa solicitada; los umbrales configurados se restaurarán al reiniciar TLP o el equipo'
}

main() {
  parse_args "$@"
  require_linux
  case "$ACTION" in
    check)
      show_tlp_status
      ;;
    plan)
      show_tlp_status
      info '[plan] instalar tlp si falta'
      info "[plan] respaldar $CONFIG_FILE si existe"
      info "[plan] escribir umbrales ${START_THRESHOLD}/${STOP_THRESHOLD}% en $CONFIG_FILE"
      info "[plan] ejecutar sudo tlp setcharge $START_THRESHOLD $STOP_THRESHOLD"
      info '[plan] habilitar tlp.service si existe'
      ;;
    apply)
      command -v tlp >/dev/null 2>&1 || {
        info 'tlp no está instalado; se instalará desde Debian'
        sudo apt-get update
        sudo apt-get install -y tlp
      }
      batteries >/dev/null || die 'no se detectó una batería ThinkPad compatible'
      install_config
      ;;
    fullcharge)
      fullcharge
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
