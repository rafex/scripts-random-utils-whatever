#!/usr/bin/env bash
# shellcheck shell=bash
# Configura QEMU/KVM para virtualización de escritorio en qemu:///session.
set -Eeuo pipefail

umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION='check'
TARGET_USER="$(id -un)"
TARGET_HOME="${HOME:?HOME no está definido}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$TARGET_HOME/.local/share}"
SESSION_URI='qemu:///session'
LIBVIRT_CONFIG="$XDG_CONFIG_HOME/libvirt/libvirt.conf"
IMAGE_DIR="$XDG_DATA_HOME/libvirt/images"
ISO_DIR="$TARGET_HOME/VMs/iso"
BEGIN_MARKER='# BEGIN rafex configure-kvm'
END_MARKER='# END rafex configure-kvm'

readonly -a PACKAGES=(
  qemu-system-x86
  qemu-utils
  libvirt-daemon-system
  libvirt-clients
  virt-manager
  virt-viewer
  ovmf
  swtpm
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_kvm_linux.sh --check
  configure_kvm_linux.sh --plan
  configure_kvm_linux.sh --apply
  configure_kvm_linux.sh --status

Opciones:
  --check       Auditar CPU, /dev/kvm, paquetes y qemu:///session.
  --plan        Mostrar acciones sin modificar el sistema.
  --dry-run     Alias de --plan.
  --apply       Instalar dependencias y preparar pools de usuario.
  --status      Mostrar el estado detallado de QEMU/KVM/libvirt.
  --help        Mostrar esta ayuda.

La configuración usa qemu:///session, almacenamiento dentro de HOME y
user-mode networking para las VMs. No crea bridges ni abre puertos.
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

require_platform() {
  [[ "$(uname -s)" == 'Linux' ]] || die 'este script solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || die "se requiere Debian; distribución detectada: ${ID:-desconocida}"
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  if [[ "$ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
    command -v apt-get >/dev/null 2>&1 || die 'falta apt-get para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'
}

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || printf 'no-instalado'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

has_cpu_virtualization() {
  grep -Eoq '(^|[[:space:]])(vmx|svm)([[:space:]]|$)' /proc/cpuinfo 2>/dev/null
}

current_groups() {
  id -nG "$TARGET_USER" 2>/dev/null || true
}

session_virsh() {
  command -v virsh >/dev/null 2>&1 || return 127
  LC_ALL=C virsh -c "$SESSION_URI" "$@"
}

pool_exists() {
  session_virsh pool-info "$1" >/dev/null 2>&1
}

pool_active() {
  session_virsh pool-info "$1" 2>/dev/null |
    awk -F': ' '
      /^(State|Active):/ {
        value=tolower($2)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value == "running" || value == "active" || value == "yes") {
          found=1
        }
      }
      END { exit(found ? 0 : 1) }
    '
}

pool_path() {
  session_virsh pool-dumpxml "$1" 2>/dev/null |
    sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -n 1
}

show_platform_status() {
  printf '═══ Plataforma QEMU/KVM ═══\n'
  printf 'usuario=%s\n' "$TARGET_USER"
  printf 'home=%s\n' "$TARGET_HOME"
  printf 'uri=%s\n' "$SESSION_URI"

  if has_cpu_virtualization; then
    ok 'CPU expone vmx/svm'
  else
    warn 'no se detectó vmx/svm en /proc/cpuinfo; revisa la virtualización en firmware'
  fi

  if [[ -e /dev/kvm ]]; then
    printf 'kvm_device='; stat -c '%A %U:%G' /dev/kvm 2>/dev/null || printf 'presente\n'
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
      ok '/dev/kvm es legible y escribible por la sesión actual'
    else
      warn '/dev/kvm existe pero la sesión actual no tiene lectura/escritura'
    fi
  else
    warn '/dev/kvm no existe; revisa el kernel y la virtualización del firmware'
  fi

  if getent group kvm >/dev/null 2>&1; then
    if printf '%s\n' "$(current_groups)" | tr ' ' '\n' | grep -qx kvm; then
      ok "$TARGET_USER pertenece al grupo kvm"
    else
      warn "$TARGET_USER no pertenece al grupo kvm en esta sesión"
    fi
  else
    warn 'el grupo kvm no existe'
  fi

  if printf '%s\n' "$(current_groups)" | tr ' ' '\n' | grep -qx libvirt; then
    warn "$TARGET_USER pertenece a libvirt; el perfil recomienda no usar ese grupo"
  else
    ok "$TARGET_USER no pertenece al grupo libvirt"
  fi
}

show_package_status() {
  local package
  printf '═══ Paquetes QEMU/KVM ═══\n'
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      printf '✓ %-24s %s\n' "$package" "$(package_version "$package")"
    else
      printf '✗ %-24s ausente\n' "$package"
    fi
  done
}

show_command_status() {
  local command_name
  printf '═══ Herramientas ═══\n'
  for command_name in qemu-system-x86_64 qemu-img virsh virt-manager virt-viewer; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '✓ %-24s %s\n' "$command_name" "$(command -v "$command_name")"
    else
      printf '✗ %-24s ausente\n' "$command_name"
    fi
  done
}

show_session_status() {
  local pool path
  printf '═══ Sesión libvirt ═══\n'
  printf 'config=%s\n' "$LIBVIRT_CONFIG"
  if [[ -f "$LIBVIRT_CONFIG" ]]; then
    if grep -Eq '^[[:space:]]*uri_default[[:space:]]*=[[:space:]]*"qemu:///session"' "$LIBVIRT_CONFIG"; then
      ok 'qemu:///session está configurado como URI predeterminada de usuario'
    elif grep -Eq '^[[:space:]]*uri_default[[:space:]]*=' "$LIBVIRT_CONFIG"; then
      warn 'libvirt.conf contiene otra uri_default; se conserva sin sobrescribir'
    else
      warn 'libvirt.conf existe, pero no define uri_default'
    fi
  else
    warn 'no existe configuración de usuario libvirt; se puede usar -c qemu:///session'
  fi

  if ! command -v virsh >/dev/null 2>&1; then
    warn 'virsh no está instalado; instala la etapa virtualization del laboratorio'
    return 0
  fi

  if session_virsh uri >/dev/null 2>&1; then
    printf 'virsh_uri='; session_virsh uri 2>/dev/null || true
    printf 'domains:\n'; session_virsh list --all 2>/dev/null || true
    printf 'networks:\n'; session_virsh net-list --all 2>/dev/null || true
  else
    warn 'no se pudo abrir qemu:///session desde esta sesión'
  fi

  printf 'storage=%s\n' "$IMAGE_DIR"
  printf 'isos=%s\n' "$ISO_DIR"
  for pool in rafex-images rafex-iso; do
    if pool_exists "$pool"; then
      path="$(pool_path "$pool")"
      if [[ "$pool" == rafex-images ]]; then
        printf 'pool=%s path=%s\n' "$pool" "${path:-desconocido}"
      else
        printf 'pool=%s path=%s\n' "$pool" "${path:-desconocido}"
      fi
      if pool_active "$pool"; then
        ok "pool $pool activa"
      else
        warn "pool $pool existe pero no está activa"
      fi
    else
      warn "pool $pool no existe"
    fi
  done

  if [[ -d "$IMAGE_DIR" && -d "$ISO_DIR" ]]; then
    ok 'directorios privados de imágenes e ISOs presentes'
  else
    warn 'faltan uno o más directorios privados de almacenamiento'
  fi
  info 'red de VMs: user-mode/NAT explícita; no se crea una red bridge'
}

show_status() {
  show_platform_status
  show_package_status
  show_command_status
  show_session_status
}

show_plan() {
  show_status
  printf '═══ Plan de aplicación ═══\n'
  info "[plan] comprobar candidatos APT para: ${PACKAGES[*]}"
  info '[plan] sudo apt-get update e instalar solo paquetes ausentes'
  info "[plan] añadir únicamente $TARGET_USER al grupo kvm si falta"
  info "[plan] crear $IMAGE_DIR y $ISO_DIR con permisos 700"
  info "[plan] configurar $LIBVIRT_CONFIG para qemu:///session si no hay conflicto"
  info '[plan] crear y activar pools rafex-images y rafex-iso solo si no existen'
  info '[plan] no crear bridges, no abrir puertos y no configurar qemu:///system'
}

validate_candidates() {
  local package candidate missing=0
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      continue
    fi
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done
  ((missing == 0)) || die 'uno o más paquetes QEMU/KVM no tienen candidato APT'
}

install_packages() {
  local -a missing=()
  local package
  for package in "${PACKAGES[@]}"; do
    package_installed "$package" || missing+=("$package")
  done
  if ((${#missing[@]} == 0)); then
    ok 'paquetes QEMU/KVM ya instalados'
    return 0
  fi
  sudo apt-get update
  validate_candidates
  info "instalando: ${missing[*]}"
  sudo apt-get install -y "${missing[@]}"
  ok 'paquetes QEMU/KVM instalados'
}

ensure_kvm_group() {
  if ! getent group kvm >/dev/null 2>&1; then
    warn 'el grupo kvm no existe después de instalar; no se modificaron grupos'
    return 0
  fi
  if printf '%s\n' "$(current_groups)" | tr ' ' '\n' | grep -qx kvm; then
    ok "$TARGET_USER ya pertenece al grupo kvm"
  else
    sudo usermod -aG kvm "$TARGET_USER"
    ok "$TARGET_USER añadido únicamente al grupo kvm"
    warn 'cierra y abre sesión, o ejecuta newgrp kvm, para activar el grupo'
  fi
}

backup_file() {
  local source="$1" backup
  [[ -f "$source" ]] || return 0
  backup="${source}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -a -- "$source" "$backup"
  info "respaldo creado: $backup"
}

configure_libvirt_default_uri() {
  local base temporary
  mkdir -p -- "$(dirname "$LIBVIRT_CONFIG")"

  if [[ -f "$LIBVIRT_CONFIG" ]] &&
    grep -Eq '^[[:space:]]*uri_default[[:space:]]*=' "$LIBVIRT_CONFIG"; then
    if grep -Eq '^[[:space:]]*uri_default[[:space:]]*=[[:space:]]*"qemu:///session"' "$LIBVIRT_CONFIG"; then
      ok 'qemu:///session ya es la URI predeterminada'
    else
      warn "se conserva uri_default existente en $LIBVIRT_CONFIG"
      warn 'usa virt-manager --connect qemu:///session para evitar el conflicto'
    fi
    return 0
  fi

  base="$(mktemp "${LIBVIRT_CONFIG}.base.XXXXXX")"
  temporary="$(mktemp "${LIBVIRT_CONFIG}.tmp.XXXXXX")"
  if [[ -f "$LIBVIRT_CONFIG" ]]; then
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin { inside=1; next }
      inside && $0 == end { inside=0; next }
      !inside { print }
    ' "$LIBVIRT_CONFIG" > "$base"
  fi
  {
    if [[ -s "$base" ]]; then
      cat "$base"
      printf '\n'
    fi
    printf '%s\n' "$BEGIN_MARKER"
    printf 'uri_default = "qemu:///session"\n'
    printf '%s\n' "$END_MARKER"
  } > "$temporary"
  rm -f -- "$base"

  if [[ -f "$LIBVIRT_CONFIG" ]] && cmp -s "$LIBVIRT_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
    ok 'configuración de URI sin cambios'
    return 0
  fi
  backup_file "$LIBVIRT_CONFIG"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$LIBVIRT_CONFIG"
  ok "URI predeterminada configurada en $LIBVIRT_CONFIG"
}

ensure_storage() {
  local pool target path
  mkdir -p -- "$IMAGE_DIR" "$ISO_DIR"
  chmod 700 "$IMAGE_DIR" "$ISO_DIR"
  ok "directorios privados preparados: $IMAGE_DIR y $ISO_DIR"

  for pool in rafex-images rafex-iso; do
    if [[ "$pool" == rafex-images ]]; then
      target="$IMAGE_DIR"
    else
      target="$ISO_DIR"
    fi
    if pool_exists "$pool"; then
      path="$(pool_path "$pool")"
      if [[ "$path" != "$target" ]]; then
        warn "pool $pool ya existe con otra ruta: ${path:-desconocida}; no se modifica"
        continue
      fi
      session_virsh pool-autostart "$pool" >/dev/null
      if pool_active "$pool"; then
        ok "pool $pool ya estaba activa"
      else
        session_virsh pool-start "$pool" >/dev/null
        ok "pool $pool activada"
      fi
      continue
    fi
    session_virsh pool-define-as "$pool" dir --target "$target" >/dev/null
    session_virsh pool-autostart "$pool" >/dev/null
    session_virsh pool-start "$pool" >/dev/null
    ok "pool $pool creada y activa: $target"
  done
}

apply_mode() {
  sudo -v
  install_packages
  ensure_kvm_group
  command -v virsh >/dev/null 2>&1 || die 'virsh no quedó instalado'
  configure_libvirt_default_uri
  ensure_storage
  show_session_status
  ok 'QEMU/KVM listo para usar con qemu:///session'
  info 'la red de cada VM debe seleccionarse como user-mode/NAT o none'
}

main() {
  parse_args "$@"
  require_platform
  case "$ACTION" in
    check|status)
      show_status
      ;;
    plan)
      show_plan
      ;;
    apply)
      apply_mode
      ;;
    *)
      die "acción inválida: $ACTION"
      ;;
  esac
}

main "$@"
