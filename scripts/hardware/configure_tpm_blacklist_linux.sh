#!/usr/bin/env bash
# configure_tpm_blacklist_linux.sh v1.0.0
# Configura de forma reversible el bloqueo de módulos TPM en Debian.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

readonly VERSION="v1.0.0"
readonly TARGET_DIR="/etc/modprobe.d"
readonly TARGET_CONFIG="${TARGET_DIR}/99-rafex-tpm-blacklist.conf"
readonly BACKUP_ROOT="/var/backups/rafex-tpm-blacklist"
readonly BEGIN_MARKER="# BEGIN rafex TPM blacklist"
readonly END_MARKER="# END rafex TPM blacklist"
readonly MODULES=(tpm tpm_crb tpm_tis tpm_tis_core)

ACTION="check"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_tpm_blacklist_linux.sh --check
  configure_tpm_blacklist_linux.sh --plan
  configure_tpm_blacklist_linux.sh --status
  configure_tpm_blacklist_linux.sh --apply
  configure_tpm_blacklist_linux.sh --rollback

Acciones:
  --check       valida Debian, modprobe e initramfs sin modificar nada.
  --plan        muestra el cambio previsto sin modificar nada.
  --status      muestra la regla, módulos cargados y respaldos administrados.
  --apply       instala la blacklist y regenera los initramfs; no reinicia.
  --rollback    restaura el respaldo administrado más reciente y regenera initramfs.
  --dry-run     alias de --plan.
  --help        muestra esta ayuda.

La regla afecta cargas futuras. Un módulo ya cargado solo dejará de usarse
después de reiniciar; este script no descarga módulos TPM en ejecución.
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

require_user_and_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal; sudo se solicita internamente'
}

require_commands() {
  local command_name
  for command_name in awk cmp cp date find grep install mktemp paste sort tail wc; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
  command -v modprobe >/dev/null 2>&1 || warn 'modprobe no está disponible; el diagnóstico será parcial'
}

require_initramfs_tools() {
  command -v update-initramfs >/dev/null 2>&1 || die 'falta la herramienta: update-initramfs'
}

target_is_managed() {
  [[ -f "$TARGET_CONFIG" ]] || return 1
  grep -Fqx "$BEGIN_MARKER" "$TARGET_CONFIG" && grep -Fqx "$END_MARKER" "$TARGET_CONFIG"
}

manual_conflicts() {
  local config_file pattern
  for config_file in "$TARGET_DIR"/*.conf; do
    [[ -f "$config_file" ]] || continue
    [[ "$config_file" == "$TARGET_CONFIG" ]] && continue
    for pattern in "${MODULES[@]}"; do
      if grep -Eqi "^[[:space:]]*(blacklist|install)[[:space:]]+${pattern}([[:space:]]|$)" "$config_file"; then
        printf '%s\n' "$config_file"
        break
      fi
    done
  done
}

loaded_modules() {
  local module
  for module in "${MODULES[@]}"; do
    if grep -q "^${module}[[:space:]]" /proc/modules 2>/dev/null; then
      printf '%s\n' "$module"
    fi
  done
}

show_status() {
  local conflicts backup_count module
  echo "═══ Blacklist TPM Rafex ${VERSION} ═══"
  printf 'destino=%s\n' "$TARGET_CONFIG"
  printf 'módulos_objetivo=%s\n' "${MODULES[*]}"
  if [[ -f "$TARGET_CONFIG" ]]; then
    if target_is_managed; then
      ok 'archivo administrado presente'
    else
      warn 'existe el destino, pero no está administrado por Rafex'
    fi
  else
    info 'blacklist administrada no instalada'
  fi
  printf 'módulos_cargados='
  loaded_modules | paste -sd, - || true
  printf '\n'
  if command -v update-initramfs >/dev/null 2>&1; then
    ok 'update-initramfs disponible'
  else
    warn 'update-initramfs no está disponible'
  fi
  conflicts="$(manual_conflicts)"
  if [[ -n "$conflicts" ]]; then
    warn 'hay reglas no administradas que afectan módulos TPM:'
    printf '  %s\n' "$conflicts" >&2
  else
    ok 'no se detectan reglas TPM externas'
  fi
  backup_count=0
  if [[ -d "$BACKUP_ROOT" ]]; then
    backup_count="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | wc -l)"
  fi
  printf 'respaldos_administrados=%s\n' "$backup_count"
  for module in "${MODULES[@]}"; do
    [[ -r "/sys/module/${module}" ]] && info "${module}: cargado" || true
  done
}

validate_context() {
  local conflicts
  require_initramfs_tools
  if [[ -e "$TARGET_CONFIG" || -L "$TARGET_CONFIG" ]] && ! target_is_managed; then
    die "${TARGET_CONFIG} existe y no está administrado; no se sobrescribirá"
  fi
  [[ ! -L "$TARGET_CONFIG" ]] || die "${TARGET_CONFIG} es un enlace simbólico; revísalo manualmente"
  conflicts="$(manual_conflicts)"
  [[ -z "$conflicts" ]] || die "hay reglas TPM no administradas: ${conflicts//$'\n'/, }"
}

check_environment() {
  validate_context
  [[ -d /etc/modprobe.d ]] || warn '/etc/modprobe.d no existe; se creará durante --apply'
  [[ -d /boot ]] || die '/boot no está disponible'
  [[ -n "$(find /boot -maxdepth 1 -name 'initrd.img-*' -print -quit 2>/dev/null)" ]] || warn 'no se encontraron initramfs en /boot'
}

require_sudo() {
  command -v sudo >/dev/null 2>&1 || die 'falta sudo'
  sudo -v
}

write_managed_config() {
  local temporary
  temporary="$(mktemp)"
  trap 'rm -f -- "$temporary"' RETURN
  cat > "$temporary" <<EOF
$BEGIN_MARKER
# Bloquea la carga automática de TPM para el perfil Rafex.
# No descarga módulos ya cargados ni desactiva el TPM en el firmware.
blacklist tpm
blacklist tpm_crb
blacklist tpm_tis
blacklist tpm_tis_core
$END_MARKER
EOF
  sudo install -d -m 0755 -- "$TARGET_DIR"
  sudo install -o root -g root -m 0644 -- "$temporary" "$TARGET_CONFIG"
  trap - RETURN
  rm -f -- "$temporary"
}

backup_target() {
  local backup_dir="$BACKUP_ROOT/$TIMESTAMP"
  sudo install -d -o root -g root -m 0700 -- "$backup_dir"
  if sudo test -e "$TARGET_CONFIG"; then
    sudo cp -p -- "$TARGET_CONFIG" "$backup_dir/99-rafex-tpm-blacklist.conf"
  else
    sudo touch "$backup_dir/99-rafex-tpm-blacklist.conf.absent"
    sudo chmod 0600 "$backup_dir/99-rafex-tpm-blacklist.conf.absent"
  fi
  info "respaldo creado bajo $backup_dir"
  printf '%s\n' "$backup_dir"
}

restore_backup_dir() {
  local backup_dir="$1"
  if sudo test -e "$backup_dir/99-rafex-tpm-blacklist.conf.absent"; then
    sudo rm -f -- "$TARGET_CONFIG"
  elif sudo test -f "$backup_dir/99-rafex-tpm-blacklist.conf"; then
    sudo install -o root -g root -m 0644 -- "$backup_dir/99-rafex-tpm-blacklist.conf" "$TARGET_CONFIG"
  else
    die "respaldo incompleto: $backup_dir"
  fi
}

latest_backup() {
  [[ -d "$BACKUP_ROOT" ]] || return 1
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -n 1
}

regenerate_initramfs() {
  sudo update-initramfs -u -k all
}

apply_config() {
  local backup_dir
  check_environment
  require_sudo
  backup_dir="$(backup_target | tail -n 1)"
  if ! write_managed_config || ! regenerate_initramfs; then
    warn 'falló la instalación o regeneración; se restaura el archivo anterior'
    restore_backup_dir "$backup_dir"
    regenerate_initramfs || warn 'la regeneración posterior al rollback también falló'
    die 'no se aplicó el cambio de forma completa'
  fi
  ok "blacklist TPM instalada: $TARGET_CONFIG"
  warn 'reinicia manualmente para que el kernel deje de cargar módulos TPM; no se reinició el equipo'
  warn 'esto puede afectar TPM/PTT, cifrado, atestación y herramientas que dependan de /dev/tpm*'
}

rollback_config() {
  local backup_dir
  backup_dir="$(latest_backup)" || die "no hay respaldos en $BACKUP_ROOT"
  [[ -n "$backup_dir" ]] || die "no hay respaldos en $BACKUP_ROOT"
  if [[ -e "$TARGET_CONFIG" || -L "$TARGET_CONFIG" ]] && ! target_is_managed; then
    die 'el destino actual no está administrado; no se sobrescribirá'
  fi
  require_sudo
  restore_backup_dir "$backup_dir"
  regenerate_initramfs
  ok "respaldo restaurado: $backup_dir"
  warn 'reinicia manualmente para aplicar el rollback al cargador de módulos'
}

main() {
  parse_args "$@"
  require_user_and_linux
  require_commands
  case "$ACTION" in
    check)
      check_environment
      ok 'entorno Debian/modprobe/initramfs validado; no se modificó el sistema'
      ;;
    plan)
      check_environment
      echo "═══ Plan blacklist TPM Rafex ═══"
      info "instalar $TARGET_CONFIG con: ${MODULES[*]}"
      info 'regenerar todos los initramfs mediante update-initramfs -u -k all'
      info 'no descargar módulos, no cambiar BIOS/UEFI y no reiniciar automáticamente'
      ;;
    status) show_status ;;
    apply) apply_config ;;
    rollback) rollback_config ;;
  esac
}

main "$@"
