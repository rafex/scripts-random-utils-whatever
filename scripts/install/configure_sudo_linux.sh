#!/usr/bin/env bash
# shellcheck shell=bash
#
# Bootstrap seguro de sudo en una instalación Debian recién instalada.
# Debe ejecutarse como root mediante su; nunca solicita ni recibe contraseñas.
set -Eeuo pipefail
umask 077

ACTION="check"
TARGET_USER="${SUDO_TARGET_USER:-${SUDO_USER:-${USER:-}}}"

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
  configure_sudo_linux.sh --check --user usuario
  configure_sudo_linux.sh --plan --user usuario
  configure_sudo_linux.sh --apply --user usuario

Opciones:
  --user usuario         Usuario normal que recibirá sudo
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Instalar y configurar sudo; requiere root
  -h, --help             Mostrar esta ayuda

Este bootstrap se ejecuta como root mediante `su -`. La contraseña de root
la gestiona `su`; este script nunca la lee, almacena ni transmite.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        [[ $# -ge 2 ]] || die "--user requiere un nombre de usuario"
        TARGET_USER="$2"
        shift 2
        ;;
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script solo funciona en Linux"
  command -v getent >/dev/null 2>&1 || die "getent no está disponible"
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
  [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || \
    die "indica un usuario normal con --user, por ejemplo: --user rafex"
  getent passwd "$TARGET_USER" >/dev/null 2>&1 || \
    die "el usuario no existe: $TARGET_USER"
  [[ "$(id -u "$TARGET_USER")" -gt 0 ]] || \
    die "el usuario objetivo no puede ser root: $TARGET_USER"
  if [[ "$ACTION" == "apply" && "$EUID" -ne 0 ]]; then
    die "--apply debe ejecutarse como root; usa: su -"
  fi
}

has_sudo_group() {
  getent group sudo >/dev/null 2>&1 || return 1
  id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sudo
}

sudoers_group_rule_present() {
  local file
  for file in /etc/sudoers /etc/sudoers.d/*; do
    [[ -f "$file" ]] || continue
    if grep -Eq '^[[:space:]]*%sudo[[:space:]]+ALL[[:space:]]*=' "$file" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

print_status() {
  echo
  echo -e "${BOLD}${CYAN}═══ Estado de sudo ═══${RESET}"
  printf 'target-user=%s\n' "$TARGET_USER"
  if command -v sudo >/dev/null 2>&1; then
    ok "comando sudo instalado"
  else
    warn "comando sudo no instalado"
  fi
  if getent group sudo >/dev/null 2>&1; then
    ok "grupo sudo existe"
  else
    warn "grupo sudo no existe"
  fi
  if has_sudo_group; then
    ok "$TARGET_USER pertenece al grupo sudo"
  else
    warn "$TARGET_USER no pertenece al grupo sudo"
  fi
  if [[ "$EUID" -eq 0 ]]; then
    if sudoers_group_rule_present; then
      ok "sudoers autoriza al grupo sudo"
    else
      warn "no se encontró una regla %sudo estándar en /etc/sudoers o /etc/sudoers.d"
    fi
  else
    info "regla sudoers: no inspeccionada (requiere root)"
  fi
  if command -v visudo >/dev/null 2>&1 && [[ "$EUID" -eq 0 ]]; then
    visudo -c >/dev/null && ok "sintaxis de sudoers válida" || warn "sintaxis de sudoers inválida"
  fi
}

backup_file() {
  local source="$1"
  local stamp
  [[ -e "$source" ]] || return 0
  stamp="$(date +%Y%m%d_%H%M%S)"
  cp -a "$source" "${source}.bak.${stamp}"
  info "respaldo creado: ${source}.bak.${stamp}"
}

install_group_rule() {
  local destination='/etc/sudoers.d/90-sudo-group'
  local temporary
  local content='%sudo ALL=(ALL:ALL) ALL'

  if sudoers_group_rule_present; then
    return 0
  fi
  if [[ -e "$destination" ]]; then
    backup_file "$destination"
  fi
  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  install -D -m 0440 "$temporary" "$destination"
  rm -f "$temporary"
  info "regla sudoers instalada: $destination"
}

apply_configuration() {
  local sudo_installed=0

  if dpkg-query -W -f='${Status}' sudo 2>/dev/null | grep -q 'install ok installed'; then
    sudo_installed=1
  fi
  if [[ "$sudo_installed" -eq 0 ]]; then
    info "instalando sudo mediante apt-get"
    apt-get update
    apt-get install -y sudo
  fi
  getent group sudo >/dev/null 2>&1 || groupadd sudo
  usermod -aG sudo "$TARGET_USER"
  install_group_rule
  visudo -c >/dev/null || die "la configuración de sudoers no es válida"
  ok "sudo configurado para $TARGET_USER"
  info "cierra la sesión de $TARGET_USER y vuelve a entrar para actualizar sus grupos"
}

main() {
  parse_args "$@"
  require_linux

  if [[ "$ACTION" == "plan" ]]; then
    print_status
    echo
    info "[plan] apt-get update"
    info "[plan] apt-get install -y sudo (si falta)"
    info "[plan] crear grupo sudo (si falta)"
    info "[plan] usermod -aG sudo $TARGET_USER"
    info "[plan] validar /etc/sudoers con visudo"
    exit 0
  fi

  if [[ "$ACTION" == "check" ]]; then
    print_status
    exit 0
  fi

  print_status
  apply_configuration
}

main "$@"
