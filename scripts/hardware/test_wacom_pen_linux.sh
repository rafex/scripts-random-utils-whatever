#!/usr/bin/env bash
# shellcheck shell=bash
#
# Diagnóstico e instalación de herramientas para probar pluma Wacom en Xorg.
set -Eeuo pipefail

ACTION="check"
APT_UPDATED=0

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
  test_wacom_pen_linux.sh --check
  test_wacom_pen_linux.sh --plan
  test_wacom_pen_linux.sh --apply

Opciones:
  --check       Diagnóstico sin modificar el sistema (default)
  --plan        Mostrar paquetes que se instalarían
  --apply       Instalar herramientas mediante APT y diagnosticar
  -h, --help    Mostrar esta ayuda

La prueba de eventos permanece manual:
  libinput debug-events
  evtest
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
}

apt_install() {
  local packages=("$@")
  info "Paquetes: ${packages[*]}"
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] sudo apt-get install -y ${packages[*]}"
    return 0
  fi
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    sudo apt-get update
    APT_UPDATED=1
  fi
  sudo apt-get install -y "${packages[@]}"
}

check_command() {
  local label="$1"
  local command_name="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$label: $command_name"
  else
    warn "$label: falta $command_name"
  fi
}

list_x_devices() {
  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY no está definido; ejecuta esta parte desde Alacritty/i3"
    return 0
  fi
  if command -v xinput >/dev/null 2>&1; then
    echo "xinput list:"
    xinput list || true
  fi
  if command -v xsetwacom >/dev/null 2>&1; then
    echo "xsetwacom --list devices:"
    xsetwacom --list devices || true
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local device
      device="$(printf '%s\n' "$line" | sed -E 's/[[:space:]]+id:.*$//' | sed -E 's/[[:space:]]+$//')"
      [[ -n "$device" ]] || continue
      echo "xsetwacom get $device all:"
      xsetwacom get "$device" all || warn "no se pudieron leer propiedades de $device"
    done < <(xsetwacom --list devices 2>/dev/null || true)
  fi
}

check_input_stack() {
  echo -e "${BOLD}${CYAN}═══ Dispositivos de entrada ═══${RESET}"
  list_x_devices
  if command -v libinput >/dev/null 2>&1; then
    echo "libinput list-devices:"
    libinput list-devices || warn "libinput no pudo enumerar dispositivos"
  else
    warn "libinput no está instalado"
  fi
  if command -v evtest >/dev/null 2>&1; then
    echo "evtest: disponible (la enumeración se hace manualmente)"
    info "Para probar eventos ejecuta: evtest /dev/input/eventX"
    info "Si aparece 'Permission denied', repite evtest con sudo desde la consola local"
  else
    warn "evtest no está instalado"
  fi
  echo "kernel-wacom:"
  if lsmod 2>/dev/null | grep -q '^wacom '; then
    ok "módulo wacom cargado"
  else
    warn "módulo wacom no aparece cargado"
  fi
  grep -E 'Wacom Pen|Wacom.*Finger|Wacom.*Pen' /proc/bus/input/devices 2>/dev/null ||
    warn "no se encontraron dispositivos Wacom en /proc/bus/input/devices"
}

main() {
  parse_args "$@"
  require_linux
  local packages=(
    evtest libinput-tools xinput xserver-xorg-input-wacom
    libwacom-common libwacom-bin xournalpp krita
  )

  echo -e "${BOLD}${CYAN}═══ Prueba de pluma Wacom ═══${RESET}"
  if [[ "$ACTION" == "apply" ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
    info "Se solicitará sudo para instalar las herramientas"
    sudo -v
    apt_install "${packages[@]}"
  elif [[ "$ACTION" == "plan" ]]; then
    apt_install "${packages[@]}"
  fi

  check_command "Eventos crudos" evtest
  check_command "Eventos libinput" libinput
  check_command "Herramienta X11 Wacom" xsetwacom
  check_command "Prueba de notas" xournalpp
  check_command "Prueba de presión" krita
  check_input_stack
  echo
  info "Abre Xournal++ para escritura y Krita para presión/inclinación"
  info "Para eventos: libinput debug-events o evtest (selecciona el dispositivo Wacom)"
}

main "$@"
