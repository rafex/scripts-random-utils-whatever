#!/usr/bin/env bash
# shellcheck shell=bash
# Configura y valida la compresión del initramfs sin recompilar el kernel.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

ACTION='check'
COMPRESSION='zstd'
CONFIG_FILE='/etc/initramfs-tools/conf.d/99-rafex-compression'
BACKUP_ROOT='/var/backups/rafex-initramfs-compression'
STAMP="$(date +%Y%m%d_%H%M%S)"
SNAPSHOT=''
TEMPORARY_FILE=''

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "$CYAN$BOLD" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "$GREEN$BOLD" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW$BOLD" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$TEMPORARY_FILE" ]]; then
    rm -f -- "$TEMPORARY_FILE"
  fi
  return 0
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  configure_initramfs_compression_linux.sh --check
  configure_initramfs_compression_linux.sh --plan [--compression zstd|xz|lz4|gzip]
  configure_initramfs_compression_linux.sh --status
  configure_initramfs_compression_linux.sh --apply [--compression zstd|xz|lz4|gzip]
  configure_initramfs_compression_linux.sh --rollback --latest

Opciones:
  --compression <algoritmo>  Compresión del initramfs (default: zstd)
  --check                    Mostrar diagnóstico sin modificar nada (default)
  --plan | --dry-run         Mostrar acciones y validar prerrequisitos
  --status                   Mostrar configuración e imágenes instaladas
  --apply                    Instalar dependencias faltantes, configurar y regenerar
  --rollback --latest        Restaurar el respaldo administrado más reciente
  --help | -h                Mostrar esta ayuda

Algoritmos soportados: zstd, xz, lz4 y gzip.
El script modifica únicamente el initramfs. No recompila ni reemplaza vmlinuz,
no modifica GRUB y no reinicia el equipo automáticamente.
EOF
}

parse_args() {
  local saw_action=0
  while (($#)); do
    case "$1" in
      --compression)
        (($# >= 2)) || die '--compression requiere zstd, xz, lz4 o gzip'
        COMPRESSION="$2"
        shift
        ;;
      --check)
        ((saw_action == 0)) || die 'solo se puede indicar una acción'
        ACTION='check'; saw_action=1
        ;;
      --plan|--dry-run)
        ((saw_action == 0)) || die 'solo se puede indicar una acción'
        ACTION='plan'; saw_action=1
        ;;
      --status)
        ((saw_action == 0)) || die 'solo se puede indicar una acción'
        ACTION='status'; saw_action=1
        ;;
      --apply)
        ((saw_action == 0)) || die 'solo se puede indicar una acción'
        ACTION='apply'; saw_action=1
        ;;
      --rollback)
        ((saw_action == 0)) || die 'solo se puede indicar una acción'
        ACTION='rollback'; saw_action=1
        ;;
      --latest)
        SNAPSHOT='latest'
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done

  case "$COMPRESSION" in
    zstd|xz|lz4|gzip) ;;
    *) die "compresión no soportada: $COMPRESSION" ;;
  esac
  if [[ "$ACTION" == 'rollback' && "$SNAPSHOT" != 'latest' ]]; then
    die 'rollback requiere --latest'
  fi
}

require_debian() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "distribución no soportada: ${ID:-desconocida}"
}

installed_kernels() {
  find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V
}

compression_command() {
  case "$1" in
    zstd) printf '%s\n' zstd ;;
    xz) printf '%s\n' xz ;;
    lz4) printf '%s\n' lz4 ;;
    gzip) printf '%s\n' gzip ;;
    *) return 1 ;;
  esac
}

compression_package() {
  case "$1" in
    zstd) printf '%s\n' zstd ;;
    xz) printf '%s\n' xz-utils ;;
    lz4) printf '%s\n' lz4 ;;
    gzip) printf '%s\n' '' ;;
    *) return 1 ;;
  esac
}

rd_config_key() {
  case "$1" in
    zstd) printf '%s\n' CONFIG_RD_ZSTD ;;
    xz) printf '%s\n' CONFIG_RD_XZ ;;
    lz4) printf '%s\n' CONFIG_RD_LZ4 ;;
    gzip) printf '%s\n' CONFIG_RD_GZIP ;;
    *) return 1 ;;
  esac
}

config_for_kernel() {
  local kernel="$1"
  if [[ -r "/boot/config-$kernel" ]]; then
    printf '%s\n' "/boot/config-$kernel"
  elif [[ "$kernel" == "$(uname -r)" && -r /proc/config.gz ]] && command -v zgrep >/dev/null 2>&1; then
    printf '%s\n' /proc/config.gz
  else
    return 1
  fi
}

config_supports_compression() {
  local config="$1" key="$2"
  if [[ "$config" == /proc/config.gz ]]; then
    zgrep -Eq "^$key=y$" "$config"
  else
    grep -Eq "^$key=y$" "$config"
  fi
}

config_sources() {
  printf '%s\n' /etc/initramfs-tools/initramfs.conf
  if [[ -d /etc/initramfs-tools/conf.d ]]; then
    find /etc/initramfs-tools/conf.d -maxdepth 1 -type f -print 2>/dev/null | sort
  fi
}

active_compression_settings() {
  local file
  while IFS= read -r file; do
    [[ -r "$file" ]] || continue
    grep -HnE '^[[:space:]]*COMPRESS[[:space:]]*=' "$file" || true
  done < <(config_sources)
}

effective_compression() {
  local setting
  setting="$(active_compression_settings | tail -n 1 || true)"
  if [[ -z "$setting" ]]; then
    printf '%s\n' 'default-initramfs-tools'
  else
    printf '%s\n' "$setting" | sed -E 's/.*COMPRESS[[:space:]]*=[[:space:]]*//'
  fi
}

check_conflicts() {
  local file raw value conflict=0
  while IFS= read -r file; do
    [[ -r "$file" ]] || continue
    [[ "$file" == "$CONFIG_FILE" ]] && continue
    while IFS= read -r raw; do
      value="$(printf '%s\n' "$raw" | sed -E 's/^[[:space:]]*COMPRESS[[:space:]]*=[[:space:]]*//')"
      value="$(printf '%s\n' "$value" | awk '{print $1}')"
      if [[ "$value" != "$COMPRESSION" ]]; then
        warn "configuración manual conflictiva: $file establece COMPRESS=$value"
        conflict=1
      fi
    done < <(grep -E '^[[:space:]]*COMPRESS[[:space:]]*=' "$file" || true)
  done < <(config_sources)
  ((conflict == 0))
}

required_commands_missing() {
  local command missing=0
  for command in update-initramfs mkinitramfs lsinitramfs file find sort stat df sha256sum paste; do
    if ! command -v "$command" >/dev/null 2>&1; then
      printf '%s\n' "$command"
      missing=1
    fi
  done
  command -v "$(compression_command "$COMPRESSION")" >/dev/null 2>&1 || {
    printf '%s\n' "$(compression_command "$COMPRESSION")"
    missing=1
  }
  return "$missing"
}

kernel_support_report() {
  local kernel config key
  key="$(rd_config_key "$COMPRESSION")"
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    if ! config="$(config_for_kernel "$kernel")"; then
      printf 'kernel=%s soporte=%s\n' "$kernel" 'config-ausente'
    elif config_supports_compression "$config" "$key"; then
      printf 'kernel=%s soporte=%s\n' "$kernel" 'si'
    else
      printf 'kernel=%s soporte=%s\n' "$kernel" 'no'
    fi
  done < <(installed_kernels)
}

validate_kernel_support() {
  local kernel config key
  key="$(rd_config_key "$COMPRESSION")"
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    config="$(config_for_kernel "$kernel")" || die "falta /boot/config-$kernel para validar CONFIG_RD"
    config_supports_compression "$config" "$key" || \
      die "$kernel no tiene $key=y; no se puede aplicar $COMPRESSION con seguridad"
  done < <(installed_kernels)
}

image_compression() {
  local image="$1" description
  description="$(file -b -- "$image" 2>/dev/null || true)"
  case "$description" in
    *Zstandard*) printf '%s\n' zstd ;;
    *XZ*|*LZMA*) printf '%s\n' xz ;;
    *LZ4*) printf '%s\n' lz4 ;;
    *gzip*|*GZip*) printf '%s\n' gzip ;;
    *) printf '%s\n' desconocida ;;
  esac
}

show_status() {
  local kernel image size compression
  echo '═══ Compresión del initramfs ThinkPad ═══'
  printf 'compresion_gestionada=%s\n' "$COMPRESSION"
  printf 'configuracion_efectiva=%s\n' "$(effective_compression)"
  printf 'configuracion_gestionada=%s\n' "$CONFIG_FILE"
  printf 'kernel_actual=%s\n' "$(uname -r)"
  printf '%s\n' 'vmlinuz=sin cambios (la compresión del kernel requiere recompilación)'
  echo '--- soporte del kernel ---'
  kernel_support_report
  echo '--- imágenes instaladas ---'
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    image="/boot/initrd.img-$kernel"
    if [[ -r "$image" ]]; then
      size="$(stat -c '%s' -- "$image" 2>/dev/null || printf '0')"
      size=$((size / 1024))
      compression="$(image_compression "$image")"
      printf 'kernel=%s initramfs=%s KiB compresion=%s\n' "$kernel" "$size" "$compression"
    else
      warn "no existe /boot/initrd.img-$kernel"
    fi
  done < <(installed_kernels)
  if active_compression_settings | grep -q .; then
    echo '--- directivas COMPRESS activas ---'
    active_compression_settings
  fi
  return 0
}

check_space() {
  local image required available size
  required=65536
  while IFS= read -r image; do
    [[ -f "$image" ]] || continue
    size="$(stat -c '%s' -- "$image" 2>/dev/null || printf '0')"
    required=$((required + (size / 1024) * 2))
  done < <(find /boot -maxdepth 1 -type f -name 'initrd.img-*' -print 2>/dev/null)
  available="$(df -Pk /boot | awk 'NR==2 {print $4}')"
  [[ "$available" =~ ^[0-9]+$ ]] || die 'no se pudo calcular el espacio libre de /boot'
  ((available >= required)) || die "espacio insuficiente en /boot: se requieren aproximadamente $required KiB y hay $available KiB"
}

create_snapshot() {
  local snapshot="$BACKUP_ROOT/$STAMP" kernel image suffix=1
  while sudo test -e "$snapshot"; do
    snapshot="$BACKUP_ROOT/$STAMP.$suffix"
    suffix=$((suffix + 1))
  done
  sudo install -d -o root -g root -m 0700 "$snapshot/images"
  if sudo test -e "$CONFIG_FILE"; then
    sudo cp -a -- "$CONFIG_FILE" "$snapshot/managed.conf"
    sudo touch "$snapshot/managed.conf.present"
  else
    sudo touch "$snapshot/managed.conf.absent"
  fi
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    image="/boot/initrd.img-$kernel"
    if sudo test -e "$image"; then
      sudo cp -a -- "$image" "$snapshot/images/"
    else
      sudo touch "$snapshot/images/$kernel.absent"
    fi
  done < <(installed_kernels)
  {
    printf 'created=%s\n' "$STAMP"
    printf 'compression=%s\n' "$COMPRESSION"
    printf 'config=%s\n' "$CONFIG_FILE"
    sudo find "$snapshot/images" -maxdepth 1 -type f -name 'initrd.img-*' -exec sha256sum {} +
  } | sudo tee "$snapshot/manifest.txt" >/dev/null
  printf '%s\n' "$snapshot"
}

restore_snapshot() {
  local snapshot="$1" kernel image backup
  [[ -d "$snapshot" ]] || die "respaldo no encontrado: $snapshot"
  if sudo test -f "$snapshot/managed.conf.present"; then
    sudo install -o root -g root -m 0644 "$snapshot/managed.conf" "$CONFIG_FILE"
  else
    sudo rm -f -- "$CONFIG_FILE"
  fi
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    image="/boot/initrd.img-$kernel"
    backup="$snapshot/images/initrd.img-$kernel"
    if sudo test -f "$backup" || sudo test -L "$backup"; then
      sudo cp -a -- "$backup" "$image"
    else
      sudo rm -f -- "$image"
    fi
  done < <(installed_kernels)
  ok "respaldo restaurado: $snapshot"
}

latest_snapshot() {
  [[ -d "$BACKUP_ROOT" ]] || return 1
  sudo find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print}'
}

install_missing_dependencies() {
  local package
  if ! command -v update-initramfs >/dev/null 2>&1 || \
     ! command -v mkinitramfs >/dev/null 2>&1 || \
     ! command -v lsinitramfs >/dev/null 2>&1; then
    die 'initramfs-tools no está instalado; instálalo antes de aplicar'
  fi
  if ! command -v "$(compression_command "$COMPRESSION")" >/dev/null 2>&1; then
    package="$(compression_package "$COMPRESSION")"
    [[ -n "$package" ]] || die "falta $(compression_command "$COMPRESSION") y no tiene paquete automático"
    info "instalando dependencia requerida: $package"
    sudo apt-get install -y --no-install-recommends "$package"
  fi
}

require_tools() {
  local missing
  if ! missing="$(required_commands_missing)"; then
    [[ -n "$missing" ]] || missing='herramientas desconocidas'
    die "faltan herramientas: $(printf '%s' "$missing" | paste -sd ', ' -); revisa initramfs-tools y la compresión seleccionada"
  fi
}

validate_images() {
  local kernel image actual
  while IFS= read -r kernel; do
    [[ -n "$kernel" ]] || continue
    image="/boot/initrd.img-$kernel"
    if [[ ! -r "$image" ]]; then
      warn "no existe la imagen regenerada: $image"
      return 1
    fi
    if ! sudo lsinitramfs "$image" >/dev/null; then
      warn "lsinitramfs no pudo leer $image"
      return 1
    fi
    actual="$(image_compression "$image")"
    if [[ "$actual" != "$COMPRESSION" ]]; then
      warn "$image quedó con compresión $actual; se esperaba $COMPRESSION"
      return 1
    fi
  done < <(installed_kernels)
}

write_managed_config() {
  TEMPORARY_FILE="$(mktemp)"
  cat > "$TEMPORARY_FILE" <<EOF
# >>> rafex initramfs compression managed >>>
# Gestionado por configure_initramfs_compression_linux.sh.
COMPRESS=$COMPRESSION
# <<< rafex initramfs compression managed <<<
EOF
  sudo install -d -o root -g root -m 0755 "$(dirname "$CONFIG_FILE")"
  sudo install -o root -g root -m 0644 "$TEMPORARY_FILE" "$CONFIG_FILE"
  rm -f -- "$TEMPORARY_FILE"
  TEMPORARY_FILE=''
}

apply_mode() {
  local snapshot
  command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  sudo -v
  install_missing_dependencies
  require_tools
  check_conflicts || die 'resuelve las directivas COMPRESS manuales antes de aplicar'
  [[ -n "$(installed_kernels)" ]] || die 'no se encontraron kernels instalados'
  validate_kernel_support
  check_space
  snapshot="$(create_snapshot)"
  info "respaldo creado: $snapshot"
  if ! write_managed_config; then
    restore_snapshot "$snapshot"
    die 'no se pudo instalar la configuración administrada'
  fi
  if ! sudo update-initramfs -u -k all; then
    warn 'update-initramfs falló; restaurando el estado anterior'
    restore_snapshot "$snapshot"
    die 'no se aplicó la compresión del initramfs'
  fi
  if ! validate_images; then
    warn 'la validación de las imágenes falló; restaurando el estado anterior'
    restore_snapshot "$snapshot"
    die 'las imágenes restauradas requieren una nueva comprobación antes de reiniciar'
  fi
  ok "initramfs regenerados con compresión $COMPRESSION para todos los kernels instalados"
  warn 'reinicia manualmente y comprueba el arranque; este script no reinicia el equipo'
}

rollback_mode() {
  local snapshot
  command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  sudo -v
  snapshot="$(latest_snapshot)" || die "no hay respaldos en $BACKUP_ROOT"
  [[ -n "$snapshot" ]] || die "no hay respaldos en $BACKUP_ROOT"
  info "restaurando el respaldo más reciente: $snapshot"
  restore_snapshot "$snapshot"
  ok 'rollback completado; no se reinició el equipo'
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check|status)
      show_status
      ;;
    plan)
      show_status
      check_conflicts || die 'el plan no puede continuar por una directiva COMPRESS manual conflictiva'
      if ! required_commands_missing >/dev/null 2>&1; then
        warn "--apply instalaría la dependencia faltante para $COMPRESSION mediante sudo apt-get"
      fi
      validate_kernel_support
      check_space
      info "[plan] respaldar configuración e imágenes en $BACKUP_ROOT"
      info "[plan] escribir COMPRESS=$COMPRESSION en $CONFIG_FILE"
      info '[plan] ejecutar sudo update-initramfs -u -k all'
      warn 'no se modificará vmlinuz, GRUB ni se reiniciará el equipo'
      ;;
    apply)
      apply_mode
      ;;
    rollback)
      rollback_mode
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
