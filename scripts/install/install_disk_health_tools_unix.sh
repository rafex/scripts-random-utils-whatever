#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="${0##*/}"
OS_TYPE="$(uname -s)"

info() { printf '→ %s\n' "$*"; }
success() { printf '✓ %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Uso:
  just install-disk-health-tools
  bash scripts/install/$SCRIPT_NAME

Instala smartmontools (smartctl) y fio, dependencias de
scripts/hardware/usb_disk_health_unix.sh. No modifica los discos.
EOF
}

if (($#)); then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) error "opción desconocida: $1"; usage; exit 2 ;;
  esac
fi

missing=()
command -v smartctl >/dev/null 2>&1 || missing+=(smartmontools)
command -v fio >/dev/null 2>&1 || missing+=(fio)

if ((${#missing[@]} == 0)); then
  success 'smartctl y fio ya están instalados; no hay cambios.'
  exit 0
fi

run_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || { error 'sudo es necesario para instalar paquetes'; exit 1; }
    sudo "$@"
  fi
}

case "$OS_TYPE" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      error 'Homebrew no está instalado; instala Homebrew y vuelve a ejecutar este script.'
      exit 1
    }
    info "Instalando con Homebrew: ${missing[*]}"
    brew install "${missing[@]}"
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      info "Instalando con APT: ${missing[*]}"
      run_root apt-get update
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      info "Instalando con DNF: ${missing[*]}"
      run_root dnf install -y "${missing[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      info "Instalando con pacman: ${missing[*]}"
      run_root pacman -S --needed --noconfirm "${missing[@]}"
    elif command -v zypper >/dev/null 2>&1; then
      info "Instalando con zypper: ${missing[*]}"
      run_root zypper --non-interactive install "${missing[@]}"
    elif command -v apk >/dev/null 2>&1; then
      info "Instalando con apk: ${missing[*]}"
      run_root apk add "${missing[@]}"
    else
      error 'no se encontró un gestor compatible (apt-get, dnf, pacman, zypper o apk).'
      exit 1
    fi
    ;;
  *)
    error "sistema operativo no soportado: $OS_TYPE"
    exit 1
    ;;
esac

missing_commands=()
command -v smartctl >/dev/null 2>&1 || missing_commands+=(smartctl)
command -v fio >/dev/null 2>&1 || missing_commands+=(fio)
if ((${#missing_commands[@]} > 0)); then
  error "la instalación terminó, pero aún faltan comandos: ${missing_commands[*]}"
  exit 1
fi

success 'smartctl y fio están listos para el diagnóstico de discos USB.'
