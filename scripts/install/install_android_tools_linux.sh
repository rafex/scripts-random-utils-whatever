#!/usr/bin/env bash
# v1.0.0 - Instala herramientas Android de Debian para la ThinkPad.
set -Eeuo pipefail

umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly -a ANDROID_PACKAGES=(adb fastboot android-udev-rules scrcpy)
readonly -a CONFLICT_PACKAGES=(android-sdk-platform-tools-common google-android-platform-tools-installer)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_android_tools_linux.sh --check
  install_android_tools_linux.sh --plan
  install_android_tools_linux.sh --apply
  install_android_tools_linux.sh --status

Instala adb, fastboot, scrcpy y las reglas udev Android de Debian. No añade
grupos, no inicia el servidor ADB y no activa ADB por red.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}"
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
    command -v udevadm >/dev/null 2>&1 || die 'falta udevadm para recargar las reglas Android'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

show_packages() {
  local package version candidate
  printf '═══ Herramientas Android ═══\n'
  for package in "${ANDROID_PACKAGES[@]}"; do
    if package_installed "$package"; then
      version="$(package_version "$package")"
      printf '✓ %-22s instalado (%s)\n' "$package" "${version:-versión desconocida}"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-22s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
}

check_candidates() {
  local package candidate missing=0
  for package in "${ANDROID_PACKAGES[@]}"; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=$((missing + 1))
    fi
  done
  ((missing == 0)) || die 'uno o más paquetes Android no tienen candidato APT; revisa las fuentes Debian'
}

show_conflicts() {
  local package
  for package in "${CONFLICT_PACKAGES[@]}"; do
    if package_installed "$package"; then
      warn "paquete potencialmente conflictivo instalado: $package; no se sobrescribirá ni desinstalará automáticamente"
    fi
  done
}

check_conflicts() {
  local package
  for package in "${CONFLICT_PACKAGES[@]}"; do
    if package_installed "$package"; then
      die "se detectó $package; retíralo o actualízalo manualmente antes de instalar las reglas Android de Debian"
    fi
  done
}

show_udev_rule() {
  local rule
  for rule in /usr/lib/udev/rules.d/51-android.rules /lib/udev/rules.d/51-android.rules; do
    if [[ -r "$rule" ]]; then
      ok "regla udev presente: $rule"
      return 0
    fi
  done
  warn 'regla udev Android ausente'
}

show_status() {
  local service_state groups
  printf '═══ Estado de herramientas Android ═══\n'
  show_packages
  show_udev_rule
  if command -v systemctl >/dev/null 2>&1; then
    service_state="$(systemctl is-active usbguard.service 2>/dev/null || true)"
    if [[ "$service_state" == active ]]; then
      ok 'USBGuard activo; el instalador no autoriza dispositivos automáticamente'
    else
      info "USBGuard: ${service_state:-no disponible}"
    fi
  fi
  groups="$(id -nG 2>/dev/null || true)"
  if [[ "$groups" == *plugdev* ]]; then
    info 'plugdev ya pertenece a la sesión; no fue modificado por este instalador'
  else
    info 'no se modifican grupos del usuario; el acceso depende de las reglas udev de Debian'
  fi
  info 'ADB no se inicia automáticamente y ADB por red permanece desactivado'
}

show_plan() {
  printf '═══ Plan herramientas Android ═══\n'
  show_packages
  check_candidates
  show_conflicts
  info 'instalar con APT: adb fastboot android-udev-rules scrcpy'
  info 'recargar reglas udev; será necesario desconectar y reconectar el teléfono'
  info 'no añadir grupos, no iniciar ADB y no habilitar ADB por Wi-Fi'
  info 'no se modificará el perfil base ni se instalará Android Studio'
}

apply_install() {
  sudo -v
  check_candidates
  check_conflicts
  info 'actualizando índices APT'
  sudo apt-get update
  info 'instalando herramientas Android desde Debian'
  sudo apt-get --no-remove install --no-install-recommends -y "${ANDROID_PACKAGES[@]}"
  sudo udevadm control --reload-rules
  ok 'herramientas Android y reglas udev instaladas'
  info 'desconecta y vuelve a conectar el teléfono antes de ejecutar adb devices'
  info 'activa Depuración USB en el teléfono y acepta su huella RSA cuando la solicite'
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      show_packages
      check_candidates
      show_conflicts
      ;;
    plan) show_plan ;;
    apply) apply_install ;;
    status) show_status ;;
  esac
}

main "$@"
