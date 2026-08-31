#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015
# Auditoría de preparación: solo lectura, sin solicitar sudo ni cambiar el sistema.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

TARGET_USER="$(id -un)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLOCKERS=0
PENDING=0

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
blocker() { BLOCKERS=$((BLOCKERS + 1)); printf '✗ BLOQUEO: %s\n' "$*" >&2; }
pending() { PENDING=$((PENDING + 1)); warn "pendiente: $*"; }

usage() {
  cat <<'EOF'
Uso:
  audit_thinkpad_readiness_linux.sh --check
  audit_thinkpad_readiness_linux.sh --status

La auditoría es de solo lectura. No solicita sudo, no instala paquetes,
no cambia servicios y no muestra PIN, contraseñas, IMEI, IMSI ni secretos Wi-Fi.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --check|--status) shift ;;
      --help|-h) usage; exit 0 ;;
      *) printf '✗ ERROR: argumento desconocido: %s\n' "$1" >&2; exit 2 ;;
    esac
  done
}

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || { printf '✗ ERROR: se requiere Linux\n' >&2; exit 1; }
  [[ -r /etc/os-release ]] || { printf '✗ ERROR: falta /etc/os-release\n' >&2; exit 1; }
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "$ID" == debian ]] || {
    printf '✗ ERROR: se requiere Debian; se detectó %s\n' "$ID" >&2
    exit 1
  }
}

command_path() { command -v "$1" 2>/dev/null || true; }

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'
}

check_services() {
  local unit
  printf '═══ Servicios y controles ═══\n'
  for unit in NetworkManager.service ModemManager.service fail2ban.service apparmor.service auditd.service fstrim.timer tlp.service; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      ok "$unit activo"
    else
      warn "$unit inactivo, ausente o no verificable"
    fi
  done
  for unit in usbguard.service usbguard-dbus.service; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      ok "$unit activo"
    else
      blocker "$unit no está activo"
    fi
  done
}

check_privileged_controls() {
  local effective_ssh expected_line key
  printf '═══ Controles privilegiados ═══\n'
  if ! sudo -n true 2>/dev/null; then
    pending 'ejecutar la verificación desde la consola local después de sudo -v'
    return 0
  fi
  if sudo -n ufw status 2>/dev/null | grep -q '^Status: active'; then
    ok 'UFW activo'
  else
    blocker 'UFW no aparece activo'
  fi
  if sudo -n fail2ban-client status sshd 2>/dev/null | grep -q 'Status for the jail: sshd'; then
    ok 'Fail2ban tiene activo el jail sshd'
  else
    blocker 'Fail2ban no muestra activo el jail sshd'
  fi
  sudo -n aa-status >/dev/null 2>&1 && ok 'AppArmor responde correctamente' || blocker 'AppArmor no pudo verificarse'
  if sudo -n auditctl -s 2>/dev/null | grep -Eq '^enabled[[:space:]]+[12]'; then
    ok 'auditd está habilitado en el kernel'
  else
    blocker 'auditd no aparece habilitado'
  fi
  sudo -n test -f /etc/audit/rules.d/99-thinkpad-hardening.rules &&
    ok 'reglas personalizadas de auditd presentes' ||
    blocker 'faltan las reglas personalizadas de auditd'
  sudo -n test -f /etc/polkit-1/rules.d/10-udisks2-mount.rules &&
    ok 'regla Polkit de montaje USB presente' ||
    blocker 'falta la regla Polkit de montaje USB'
  effective_ssh="$(sudo -n /usr/sbin/sshd -T 2>/dev/null || true)"
  if [[ -z "$effective_ssh" ]]; then
    blocker 'no se pudo consultar sshd -T'
  else
    for key in permitrootlogin passwordauthentication kbdinteractiveauthentication pubkeyauthentication maxauthtries; do
      case "$key" in
        permitrootlogin) expected_line='permitrootlogin no' ;;
        passwordauthentication) expected_line='passwordauthentication no' ;;
        kbdinteractiveauthentication) expected_line='kbdinteractiveauthentication no' ;;
        pubkeyauthentication) expected_line='pubkeyauthentication yes' ;;
        maxauthtries) expected_line='maxauthtries 3' ;;
      esac
      if grep -Fqx "$expected_line" <<< "$effective_ssh"; then
        ok "sshd: $expected_line"
      else
        blocker "sshd no aplica la directiva $expected_line"
      fi
    done
  fi
  sudo -n usbguard list-devices >/dev/null 2>&1 &&
    ok 'USBGuard permite consultar dispositivos' ||
    blocker 'USBGuard no permite consultar dispositivos'
}

check_network() {
  local rows wifi wwan duplicate_count active_count
  printf '═══ Red y WWAN ═══\n'
  if ! command -v nmcli >/dev/null 2>&1; then
    blocker 'nmcli no está disponible'
    return 0
  fi
  rows="$(nmcli -t -g DEVICE,TYPE,STATE device status 2>/dev/null || true)"
  wifi="$(awk -F: '$2 == "wifi" && $3 == "connected" { count++ } END { print count + 0 }' <<< "$rows")"
  wwan="$(awk -F: '$2 == "gsm" && $3 == "connected" { count++ } END { print count + 0 }' <<< "$rows")"
  printf 'wifi_conectado=%s wwan_conectado=%s\n' "$wifi" "$wwan"
  ((wifi > 0)) && ok 'Wi-Fi conectado' || warn 'Wi-Fi no está conectado actualmente'
  ((wwan > 0)) && ok 'WWAN conectada como respaldo' || info 'WWAN no conectada actualmente'
  duplicate_count="$(nmcli -t -g NAME,UUID,TYPE connection show 2>/dev/null |
    awk -F: -v wanted='OXXO Cel' '$1 == wanted && $3 == "gsm" { count++ } END { print count + 0 }')"
  active_count="$(nmcli -t -g NAME,UUID,TYPE connection show --active 2>/dev/null |
    awk -F: -v wanted='OXXO Cel' '$1 == wanted && $3 == "gsm" { count++ } END { print count + 0 }')"
  if ((duplicate_count == 1)); then
    ok 'existe un único perfil GSM OXXO Cel'
  elif ((duplicate_count > 1)); then
    blocker "existen $duplicate_count perfiles GSM OXXO Cel"
  else
    pending 'no existe el perfil GSM OXXO Cel'
  fi
  printf 'oxxo_cel_activos=%s\n' "$active_count"
}

check_dumpcap() {
  local dumpcap getcap mode caps
  printf '═══ Captura de tráfico ═══\n'
  dumpcap="$(command_path dumpcap)"
  if [[ -z "$dumpcap" ]]; then
    pending 'dumpcap no está instalado'
    return 0
  fi
  mode="$(stat -c '%A' "$dumpcap" 2>/dev/null || true)"
  getcap="$(command_path getcap)"
  if [[ -z "$getcap" ]]; then
    pending 'no se puede verificar dumpcap porque falta getcap'
    return 0
  fi
  caps="$("$getcap" "$dumpcap" 2>/dev/null || true)"
  if [[ "$mode" == *s* || "$caps" == *cap_net_* ]]; then
    blocker 'dumpcap conserva SUID o capacidades persistentes'
  else
    ok 'dumpcap no tiene privilegios persistentes; la captura requiere sudo'
  fi
}

check_storage_energy() {
  local root_source root_fs
  printf '═══ Almacenamiento y energía ═══\n'
  read -r root_source root_fs < <(findmnt -n -o SOURCE,FSTYPE / 2>/dev/null || printf 'desconocido desconocido\n')
  printf 'root=%s fs=%s\n' "$root_source" "$root_fs"
  if lsblk -rno TYPE 2>/dev/null | grep -qx crypt; then
    ok 'se detecta una capa cifrada LUKS/device-mapper'
  else
    warn 'no se pudo confirmar la capa cifrada automáticamente'
  fi
  systemctl is-enabled --quiet fstrim.timer 2>/dev/null && ok 'fstrim.timer habilitado' || warn 'fstrim.timer no está habilitado'
  [[ -r /sys/power/mem_sleep ]] && grep -q '\[s2idle\]' /sys/power/mem_sleep &&
    ok 's2idle está seleccionado' || warn 's2idle no está seleccionado o no se pudo leer'
  [[ -r /etc/tlp.d/90-rafex-battery.conf ]] &&
    ok 'límites de batería TLP presentes' || pending 'no se puede leer la configuración protegida de TLP'
}

check_virtualization() {
  printf '═══ Virtualización ═══\n'
  grep -Eq '(^|[[:space:]])vmx([[:space:]]|$)' /proc/cpuinfo 2>/dev/null &&
    ok 'VT-x (vmx) anunciado por la CPU' || warn 'no se detectó vmx/svm'
  [[ -r /dev/kvm && -w /dev/kvm ]] && ok '/dev/kvm accesible' || warn '/dev/kvm no es accesible en esta sesión'
  if command -v virsh >/dev/null 2>&1; then
    virsh -c qemu:///session list --all >/dev/null 2>&1 && ok 'qemu:///session responde' || warn 'qemu:///session no responde'
  else
    pending 'virsh no está instalado'
  fi
}

check_desktop_and_backup() {
  local connected backup_target
  printf '═══ Sesión gráfica y respaldo ═══\n'
  if [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1; then
    connected="$(xrandr --query 2>/dev/null | awk '$2 == "connected" { print $1 }' | paste -sd, -)"
    ok "salidas X11 conectadas: ${connected:-ninguna}"
  else
    pending 'probar físicamente el proyector desde la sesión gráfica; esta auditoría no tiene DISPLAY'
  fi
  backup_target="/run/media/$TARGET_USER/ssd_rafex_1"
  findmnt -rn -o TARGET 2>/dev/null | grep -Fxq "$backup_target" &&
    ok "SSD de respaldo montado: $backup_target" ||
    pending "montar manualmente el SSD de respaldo en $backup_target antes del respaldo final"
}

check_runtimes_and_lab() {
  local package command_name missing_count=0 missing_names=''
  printf '═══ Runtimes y laboratorio ═══\n'
  for command_name in java node mvn gradle podman; do
    command -v "$command_name" >/dev/null 2>&1 && ok "$command_name disponible" || warn "$command_name ausente en esta sesión"
  done
  for package in sleuthkit testdisk yara hashdeep ssdeep rkhunter john hydra hashcat; do
    if ! package_installed "$package"; then
      missing_count=$((missing_count + 1))
      missing_names="$missing_names $package"
    fi
  done
  if ((missing_count == 0)); then
    ok 'etapas forense y credenciales completas'
  else
    info "paquetes opcionales pendientes:$missing_names"
  fi
  package_installed kismet || info 'kismet no está instalado; no tiene candidato en los repositorios activos'
}

check_repo() {
  local state
  if command -v git >/dev/null 2>&1 && [[ -d "$REPO_ROOT/.git" ]]; then
    state="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)"
    [[ -z "$state" ]] && ok 'repositorio local limpio' || warn 'repositorio local tiene cambios no comprometidos'
  fi
}

main() {
  parse_args "$@"
  require_linux_debian
  printf '═══ Auditoría de preparación ThinkPad ═══\nusuario=%s\n' "$TARGET_USER"
  check_repo
  check_services
  check_privileged_controls
  check_network
  check_dumpcap
  check_storage_energy
  check_virtualization
  check_desktop_and_backup
  check_runtimes_and_lab
  printf '═══ Resultado ═══\n'
  if ((BLOCKERS == 0)); then
    ok "sin bloqueos confirmados; pendientes=$PENDING"
    return 0
  fi
  blocker "$BLOCKERS bloqueo(s) requieren corrección antes de certificar el equipo"
  return 1
}

main "$@"
