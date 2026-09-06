#!/usr/bin/env bash
# shellcheck shell=bash
# Hardening por fases para la ThinkPad Debian: SSH primero, servicios después.
set -Eeuo pipefail
umask 077

# Las sesiones SSH no siempre heredan /usr/sbin y /sbin. Los comandos de
# administración deben poder detectarse sin depender del shell del usuario.
SYSTEM_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH="$SYSTEM_PATH${PATH:+:$PATH}"

ACTION='check'
STAGE='all'
ALLOW_LOCAL_CONSOLE=0
LOG_FILE="${THINKPAD_HARDENING_LOG_FILE:-}"
LOG_DIR="${THINKPAD_HARDENING_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scripts-random-utils-whatever/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
else
  REPO_ROOT="$PWD"
fi
BACKUP_DIR='/var/backups/rafex-thinkpad-hardening'
SSH_DROPIN='/etc/ssh/sshd_config.d/90-thinkpad-hardening.conf'
SSHD_MAIN_CONFIG='/etc/ssh/sshd_config'
STOCK_ACCEPTENV_LINE='AcceptEnv LANG LC_* COLORTERM NO_COLOR'
FAIL2BAN_JAIL='/etc/fail2ban/jail.d/sshd-thinkpad.local'
AUDIT_RULES='/etc/audit/rules.d/99-thinkpad-hardening.rules'
SYSCTL_FILE='/etc/sysctl.d/99-thinkpad-hardening.conf'
APT_CONFIG='/etc/apt/apt.conf.d/52-thinkpad-security-upgrades'
USBGUARD_CONFIG='/etc/usbguard/usbguard-daemon.conf'
AUTHORIZED_KEYS="${HOME}/.ssh/authorized_keys"

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
  harden_thinkpad_linux.sh --check
  harden_thinkpad_linux.sh --plan --stage ssh|local|all
  harden_thinkpad_linux.sh --apply --stage ssh|local|all
  harden_thinkpad_linux.sh --status
  harden_thinkpad_linux.sh --audit

Opciones:
  --stage <etapa>        ssh, local o all (default: all)
  --local-console         Permitir ejecutar la etapa SSH sin SSH_CONNECTION
  --log-file <archivo>    Guardar la salida en el archivo indicado
  --check                 Diagnóstico sin cambios persistentes
  --plan                  Mostrar acciones sin aplicarlas
  --apply                 Aplicar la etapa seleccionada
  --status                Mostrar el estado de controles instalados
  --audit                 Ejecutar Lynis y debsums sin cambiar configuración
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION='check'; shift ;;
      --plan|--dry-run) ACTION='plan'; shift ;;
      --apply) ACTION='apply'; shift ;;
      --status) ACTION='status'; shift ;;
      --audit) ACTION='audit'; shift ;;
      --stage)
        [[ $# -ge 2 ]] || die '--stage requiere ssh, local o all'
        STAGE="$2"
        shift 2
        ;;
      --local-console) ALLOW_LOCAL_CONSOLE=1; shift ;;
      --log-file)
        [[ $# -ge 2 ]] || die '--log-file requiere un archivo'
        LOG_FILE="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  case "$STAGE" in
    ssh|local|all) ;;
    *) die "etapa desconocida: $STAGE" ;;
  esac
}

init_logging() {
  [[ "$ACTION" == apply || "$ACTION" == audit || -n "$LOG_FILE" ]] || return 0
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$LOG_DIR/harden_thinkpad_${STAMP}.log"
  fi
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "log: $LOG_FILE"
}

report_failure() {
  local status="$?"
  if [[ "$status" -ne 0 && -n "$LOG_FILE" ]]; then
    echo "✗ ejecución fallida; log: $LOG_FILE" >&2
  fi
  exit "$status"
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "distribución no soportada: ${ID:-desconocida}"
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el script como usuario normal; se usará sudo'
  command -v apt-get >/dev/null 2>&1 || die 'apt-get no está disponible'
  command -v dpkg-query >/dev/null 2>&1 || die 'dpkg-query no está disponible'
  if [[ "$ACTION" == apply || "$ACTION" == audit ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
    sudo -v
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

file_exists_root() {
  [[ -e "$1" ]]
}

backup_file() {
  local source="$1"
  local relative destination
  BACKUP_DEST=''
  if ! sudo -n test -e "$source" 2>/dev/null; then
    return 0
  fi
  relative="${source#/}"
  destination="$BACKUP_DIR/${relative//\//_}.bak.${STAMP}"
  sudo install -d -m 0755 "$BACKUP_DIR"
  sudo cp -a -- "$source" "$destination"
  BACKUP_DEST="$destination"
  info "respaldo: $destination"
}

restore_backup() {
  local destination="$1" backup="$2"
  if [[ -n "$backup" ]]; then
    sudo cp -a -- "$backup" "$destination"
  else
    sudo rm -f -- "$destination"
  fi
}

install_root_content() {
  local destination="$1" mode="$2" content="$3"
  local temporary current_mode expected_mode
  expected_mode="$((10#$mode))"
  FILE_CHANGED=0
  BACKUP_DEST=''
  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  if sudo -n test -f "$destination" 2>/dev/null &&
    sudo -n cmp -s "$temporary" "$destination" 2>/dev/null; then
    current_mode="$(sudo -n stat -c '%a' "$destination" 2>/dev/null || true)"
    if [[ "$current_mode" == "$expected_mode" ]]; then
      rm -f -- "$temporary"
      ok "sin cambios: $destination"
      return 0
    fi
    info "corrigiendo permisos de $destination: actual=$current_mode esperado=$expected_mode"
  fi
  if [[ "$ACTION" == plan ]]; then
    rm -f -- "$temporary"
    info "[plan] escribir $destination"
    return 0
  fi
  backup_file "$destination"
  sudo install -D -m "$mode" "$temporary" "$destination"
  rm -f -- "$temporary"
  FILE_CHANGED=1
  ok "configurado: $destination"
}

ssh_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh. No editar manualmente.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 2
AcceptEnv COLORTERM NO_COLOR
EOF
}

fail2ban_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh. No editar manualmente.
[sshd]
enabled = true
backend = systemd
port = 22
banaction = ufw
maxretry = 5
findtime = 10m
bantime = 1h
EOF
}

audit_rules_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh. No usar -e 2 aquí.
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d -p wa -k sshd
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security -p wa -k security
EOF
}

sysctl_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh.
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
EOF
}

apt_config_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
EOF
}

usbguard_content() {
  cat <<'EOF'
# Gestionado por harden_thinkpad_linux.sh.
# Auditoría sin bloqueo: los dispositivos sin regla quedan autorizados.
ImplicitPolicyTarget=allow
PresentDevicePolicy=keep
InsertedDevicePolicy=apply-policy
IPCAllowedUsers=root
AuditBackend=FileAudit
AuditFilePath=/var/log/usbguard/usbguard-audit.log
EOF
}

check_ssh() {
  echo '--- SSH ---'
  if [[ -s "$AUTHORIZED_KEYS" ]] && grep -Eq '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$AUTHORIZED_KEYS"; then
    ok "clave autorizada encontrada: $AUTHORIZED_KEYS"
  else
    warn "no se encontró una clave SSH utilizable en $AUTHORIZED_KEYS"
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    ok "sesión SSH detectada: ${SSH_CONNECTION%% *}"
  else
    warn 'no se detectó SSH_CONNECTION'
  fi
  if file_exists_root "$SSH_DROPIN"; then
    ok "drop-in SSH presente: $SSH_DROPIN"
  else
    warn "drop-in SSH ausente: $SSH_DROPIN"
  fi
  if sudo -n /usr/sbin/sshd -t 2>/dev/null; then
    ok 'sshd -t correcto'
  else
    warn 'no se pudo validar sshd -t sin sudo o la configuración tiene errores'
  fi
  local effective_ssh
  if effective_ssh="$(sudo -n /usr/sbin/sshd -T 2>/dev/null)"; then
    printf '%s\n' "$effective_ssh" | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|maxauthtries|logingracetime|clientaliveinterval|clientalivecountmax) ' || true
    if printf '%s\n' "$effective_ssh" | grep -qE '^acceptenv (lang|lc_\*)$'; then
      warn 'sshd todavía acepta LANG/LC_* del cliente (AcceptEnv es acumulativo; revisa la línea de stock en sshd_config)'
    else
      ok 'sshd ya no acepta LANG/LC_* del cliente'
    fi
  else
    warn 'no se pudo consultar la configuración efectiva de sshd sin sudo'
  fi
}

check_packages() {
  local package missing=()
  for package in "$@"; do
    package_installed "$package" || missing+=("$package")
  done
  if ((${#missing[@]} > 0)); then
    warn "paquetes pendientes: ${missing[*]}"
  else
    ok 'paquetes de hardening instalados'
  fi
}

check_service() {
  local unit="$1"
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    ok "$unit activo"
  else
    warn "$unit inactivo o no disponible"
  fi
}

check_managed_file() {
  local path="$1" label="$2"
  if file_exists_root "$path"; then
    ok "$label presente: $path"
  else
    warn "$label ausente: $path"
  fi
}

check_local() {
  echo '--- hardening local ---'
  check_packages ufw fail2ban apparmor-utils apparmor-profiles apparmor-profiles-extra \
    auditd audispd-plugins unattended-upgrades debsums lynis usbguard needrestart
  check_service apparmor.service
  check_service fail2ban.service
  check_service auditd.service
  check_service usbguard.service
  check_service usbguard-dbus.service
  check_service fstrim.timer
  check_managed_file "$FAIL2BAN_JAIL" 'jail SSH de Fail2ban'
  check_managed_file "$AUDIT_RULES" 'reglas personalizadas de auditd'
  check_managed_file "$USBGUARD_CONFIG" 'configuración de USBGuard'
  if [[ -e "$USBGUARD_CONFIG" ]]; then
    if [[ "$(sudo -n stat -c '%a' "$USBGUARD_CONFIG" 2>/dev/null || true)" == 600 ]]; then
      ok 'configuración de USBGuard tiene permisos 0600'
    else
      warn 'la configuración de USBGuard debe tener permisos 0600'
    fi
  fi
  if command -v ufw >/dev/null 2>&1; then
    sudo -n ufw status verbose 2>/dev/null || warn 'UFW requiere sudo para consultar su estado'
  else
    echo 'ufw=missing'
  fi
  if command -v fail2ban-client >/dev/null 2>&1; then
    sudo -n fail2ban-client status sshd 2>/dev/null || warn 'jail sshd de fail2ban no está disponible'
  else
    echo 'fail2ban-client=missing'
  fi
  if command -v aa-status >/dev/null 2>&1; then
    sudo -n aa-status 2>/dev/null || warn 'no se pudo consultar AppArmor'
  else
    echo 'aa-status=missing'
  fi
  if command -v auditctl >/dev/null 2>&1; then
    sudo -n auditctl -s 2>/dev/null || warn 'no se pudo consultar auditd'
  else
    echo 'auditctl=missing'
  fi
  if command -v usbguard >/dev/null 2>&1; then
    sudo -n usbguard list-devices 2>/dev/null || warn 'no se pudo consultar USBGuard'
  else
    echo 'usbguard=missing'
  fi
  if file_exists_root "$SYSCTL_FILE"; then ok "sysctl presente: $SYSCTL_FILE"; else warn "sysctl ausente: $SYSCTL_FILE"; fi
  if file_exists_root "$APT_CONFIG"; then ok "actualizaciones configuradas: $APT_CONFIG"; else warn "actualizaciones no configuradas: $APT_CONFIG"; fi
}

preflight_ssh() {
  [[ "$ALLOW_LOCAL_CONSOLE" -eq 1 || -n "${SSH_CONNECTION:-}" ]] ||
    die 'la etapa SSH requiere SSH_CONNECTION; usa --local-console solo desde la consola local'
  [[ -s "$AUTHORIZED_KEYS" ]] || die "falta $AUTHORIZED_KEYS; no se desactivará la contraseña"
  grep -Eq '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$AUTHORIZED_KEYS" ||
    die "no hay una clave SSH reconocible en $AUTHORIZED_KEYS; no se desactivará la contraseña"
  [[ "$ACTION" == plan ]] && return 0
  sudo -n /usr/sbin/sshd -t 2>/dev/null ||
    die 'la configuración SSH actual no supera sshd -t'
}

neutralize_stock_acceptenv() {
  # AcceptEnv es una directiva acumulativa en sshd_config (igual que
  # SendEnv del lado cliente): un AcceptEnv en el drop-in no reemplaza el
  # de /etc/ssh/sshd_config, se le SUMA (confirmado con `sshd -T`). La
  # única forma real de dejar de aceptar LANG/LC_* del cliente es comentar
  # la línea de stock de Debian en el archivo principal.
  ACCEPTENV_CHANGED=0
  ACCEPTENV_BACKUP=''
  # sshd_config principal es de lectura pública (644): no hace falta sudo
  # para detectar la línea, solo para comentarla más abajo.
  [[ -f "$SSHD_MAIN_CONFIG" ]] || return 0
  local line_number
  line_number="$(grep -nxF "$STOCK_ACCEPTENV_LINE" "$SSHD_MAIN_CONFIG" 2>/dev/null |
    head -1 | cut -d: -f1)"
  if [[ -z "$line_number" ]]; then
    ok "AcceptEnv de stock ya no está presente en $SSHD_MAIN_CONFIG"
    return 0
  fi
  if [[ "$ACTION" == plan ]]; then
    info "[plan] comentar línea $line_number ('$STOCK_ACCEPTENV_LINE') en $SSHD_MAIN_CONFIG"
    return 0
  fi
  backup_file "$SSHD_MAIN_CONFIG"
  ACCEPTENV_BACKUP="$BACKUP_DEST"
  sudo sed -i "${line_number}s/^/# Neutralizado por harden_thinkpad_linux.sh -ver AcceptEnv en ${SSH_DROPIN}-: /" \
    "$SSHD_MAIN_CONFIG"
  ACCEPTENV_CHANGED=1
  ok "AcceptEnv de stock neutralizado en $SSHD_MAIN_CONFIG (línea $line_number)"
}

apply_ssh() {
  local dropin_backup dropin_changed acceptenv_backup acceptenv_changed
  preflight_ssh
  if [[ "$ACTION" == plan ]]; then
    info "[plan] respaldar y escribir $SSH_DROPIN"
    neutralize_stock_acceptenv
    info '[plan] sudo /usr/sbin/sshd -t'
    info '[plan] sudo systemctl reload ssh'
    return 0
  fi
  install_root_content "$SSH_DROPIN" 0644 "$(ssh_content)"
  dropin_changed="$FILE_CHANGED"
  dropin_backup="$BACKUP_DEST"
  neutralize_stock_acceptenv
  acceptenv_changed="$ACCEPTENV_CHANGED"
  acceptenv_backup="$ACCEPTENV_BACKUP"
  if [[ "$dropin_changed" -eq 0 && "$acceptenv_changed" -eq 0 ]]; then
    ok 'SSH ya estaba endurecido'
    return 0
  fi
  if ! sudo /usr/sbin/sshd -t; then
    warn 'sshd -t falló; restaurando configuración SSH anterior'
    [[ "$dropin_changed" -eq 1 ]] && restore_backup "$SSH_DROPIN" "$dropin_backup"
    [[ "$acceptenv_changed" -eq 1 ]] && restore_backup "$SSHD_MAIN_CONFIG" "$acceptenv_backup"
    sudo /usr/sbin/sshd -t || true
    die 'no se aplicó el hardening SSH'
  fi
  if ! sudo systemctl reload ssh; then
    warn 'systemctl reload ssh falló; restaurando configuración SSH anterior'
    [[ "$dropin_changed" -eq 1 ]] && restore_backup "$SSH_DROPIN" "$dropin_backup"
    [[ "$acceptenv_changed" -eq 1 ]] && restore_backup "$SSHD_MAIN_CONFIG" "$acceptenv_backup"
    sudo systemctl reload ssh || true
    die 'no se aplicó el hardening SSH'
  fi
  ok 'SSH endurecido y recargado sin reiniciar el servicio'
}

install_packages() {
  local packages=(ufw fail2ban apparmor-utils apparmor-profiles apparmor-profiles-extra
    auditd audispd-plugins unattended-upgrades debsums lynis usbguard needrestart)
  if [[ "$ACTION" == plan ]]; then
    info "[plan] sudo apt-get update"
    info "[plan] sudo apt-get install -y ${packages[*]}"
    return 0
  fi
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

apply_ufw() {
  if [[ "$ACTION" == plan ]]; then
    info '[plan] bash scripts/install/install_ufw_linux.sh --apply --profile all'
    return 0
  fi
  bash "$REPO_ROOT/scripts/install/install_ufw_linux.sh" --apply --profile all
}

apply_fail2ban() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] escribir $FAIL2BAN_JAIL"
    info '[plan] sudo fail2ban-client -t'
    info '[plan] sudo systemctl enable --now fail2ban'
    return 0
  fi
  install_root_content "$FAIL2BAN_JAIL" 0644 "$(fail2ban_content)"
  sudo fail2ban-client -t
  sudo systemctl enable --now fail2ban
  sudo fail2ban-client status sshd
}

apply_apparmor() {
  if [[ "$ACTION" == plan ]]; then
    info '[plan] instalar y activar AppArmor sin cambiar perfiles a enforce'
    return 0
  fi
  sudo systemctl enable --now apparmor
  sudo aa-status || true
  sudo aa-unconfined 2>/dev/null || true
  sudo journalctl -k --no-pager -n 80 -g 'apparmor' 2>/dev/null || true
}

apply_auditd() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] escribir $AUDIT_RULES"
    info '[plan] sudo augenrules --check && sudo augenrules --load'
    info '[plan] sudo systemctl enable --now auditd'
    return 0
  fi
  install_root_content "$AUDIT_RULES" 0640 "$(audit_rules_content)"
  sudo augenrules --check
  sudo augenrules --load
  sudo systemctl enable --now auditd
  sudo auditctl -s
}

apply_updates() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] escribir $APT_CONFIG"
    info '[plan] configurar seguridad diaria sin reinicio automático'
    return 0
  fi
  install_root_content "$APT_CONFIG" 0644 "$(apt_config_content)"
  sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  sudo unattended-upgrade --dry-run --debug
}

apply_sysctl() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] escribir $SYSCTL_FILE"
    info "[plan] sudo sysctl -p $SYSCTL_FILE"
    return 0
  fi
  install_root_content "$SYSCTL_FILE" 0644 "$(sysctl_content)"
  sudo sysctl -p "$SYSCTL_FILE"
}

apply_usbguard() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] escribir $USBGUARD_CONFIG con política de auditoría sin bloqueo"
    info '[plan] sudo systemctl enable usbguard usbguard-dbus'
    info '[plan] reiniciar usbguard y usbguard-dbus en ese orden'
    return 0
  fi
  sudo install -d -m 0755 /var/log/usbguard
  install_root_content "$USBGUARD_CONFIG" 0600 "$(usbguard_content)"
  sudo systemctl enable usbguard.service usbguard-dbus.service
  sudo systemctl reset-failed usbguard.service usbguard-dbus.service 2>/dev/null || true
  if ! sudo systemctl restart usbguard.service; then
    warn 'USBGuard no pudo iniciar; se conserva la configuración para diagnóstico'
    sudo journalctl -u usbguard.service -u usbguard-dbus.service -b --no-pager -n 60 || true
    die 'usbguard.service no está operativo'
  fi
  if ! sudo systemctl restart usbguard-dbus.service; then
    warn 'el servicio D-Bus de USBGuard no pudo iniciar'
    sudo journalctl -u usbguard.service -u usbguard-dbus.service -b --no-pager -n 60 || true
    die 'usbguard-dbus.service no está operativo'
  fi
  sudo systemctl is-active --quiet usbguard.service || die 'usbguard.service quedó inactivo'
  sudo systemctl is-active --quiet usbguard-dbus.service || die 'usbguard-dbus.service quedó inactivo'
  sudo usbguard list-devices
  ok 'USBGuard activo en modo de auditoría sin bloqueo'
}

apply_local() {
  install_packages
  apply_ufw
  apply_fail2ban
  apply_apparmor
  apply_auditd
  apply_updates
  apply_sysctl
  apply_usbguard
  if [[ "$ACTION" == apply ]]; then
    ok 'hardening local aplicado'
  else
    ok 'plan de hardening local preparado'
  fi
}

run_audit() {
  echo '═══ Auditoría de hardening ═══'
  if command -v lynis >/dev/null 2>&1; then
    sudo lynis audit system --quick --no-colors || true
  else
    warn 'lynis no está instalado'
  fi
  if command -v debsums >/dev/null 2>&1; then
    sudo debsums -s || true
  else
    warn 'debsums no está instalado'
  fi
}

main() {
  parse_args "$@"
  init_logging
  require_debian
  case "$ACTION" in
    check)
      echo '═══ Check hardening ThinkPad ═══'
      check_ssh
      check_local
      ;;
    plan)
      echo "═══ Plan hardening ThinkPad ($STAGE) ═══"
      if [[ "$STAGE" == ssh || "$STAGE" == all ]]; then apply_ssh; fi
      if [[ "$STAGE" == local || "$STAGE" == all ]]; then apply_local; fi
      ok 'plan terminado; no se modificó el sistema'
      ;;
    apply)
      echo "═══ Aplicando hardening ThinkPad ($STAGE) ═══"
      if [[ "$STAGE" == ssh || "$STAGE" == all ]]; then apply_ssh; fi
      if [[ "$STAGE" == local || "$STAGE" == all ]]; then apply_local; fi
      ok 'hardening terminado'
      ;;
    status)
      check_ssh
      check_local
      ;;
    audit) run_audit ;;
  esac
}

trap report_failure EXIT
main "$@"
