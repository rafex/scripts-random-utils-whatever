#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# format_usb_unix.sh
# Formatea un disco USB en macOS y Linux.
# ─────────────────────────────────────────────────────────────────────────────

USB_DISK="${USB_DISK:-}"
USB_FORMAT="${USB_FORMAT:-FAT32}"
USB_NAME="${USB_NAME:-USB}"
ARG_DISK=""
ARG_FORMAT=""
ARG_NAME=""
ENV_FILE=".env"
OS_TYPE="$(uname -s)"

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}Uso:${RESET}"
  echo "  $0 [opciones]"
  echo
  echo -e "${BOLD}Opciones:${RESET}"
  echo -e "  ${CYAN}-d, --disk${RESET}    <diskN|sdX>   Disco destino (ej. disk5, sdb)"
  echo -e "  ${CYAN}-f, --format${RESET}  <formato>     Sistema de archivos (defecto: FAT32)"
  echo -e "  ${CYAN}-n, --name${RESET}    <etiqueta>    Nombre del volumen (defecto: USB)"
  echo -e "  ${CYAN}    --env${RESET}     <archivo.env> Archivo .env con USB_DISK, USB_FORMAT, USB_NAME"
  echo -e "  ${CYAN}-h, --help${RESET}                  Mostrar esta ayuda"
  echo
  echo -e "${BOLD}Formatos disponibles:${RESET}"
  echo -e "  ${CYAN}FAT32${RESET}   Compatible con macOS, Linux y Windows (recomendado para USBs)"
  echo -e "  ${CYAN}exFAT${RESET}   Sin límite de 4 GB por archivo, compatible con macOS y Linux"
  echo -e "  ${CYAN}ext4${RESET}    Solo Linux"
  echo -e "  ${CYAN}APFS${RESET}    Solo macOS (macOS 10.13+)"
  echo -e "  ${CYAN}HFS+${RESET}    Solo macOS"
  echo
  echo -e "${BOLD}Variables de entorno:${RESET}"
  echo -e "  ${CYAN}USB_DISK${RESET}    Disco destino"
  echo -e "  ${CYAN}USB_FORMAT${RESET}  Sistema de archivos"
  echo -e "  ${CYAN}USB_NAME${RESET}    Nombre del volumen"
  echo
  echo -e "${BOLD}Formato del .env:${RESET}"
  echo "  USB_DISK=disk5"
  echo "  USB_FORMAT=FAT32"
  echo "  USB_NAME=MI_USB"
  echo
  echo -e "${BOLD}Ejemplo:${RESET}"
  echo "  $0 --disk disk5 --format FAT32 --name MI_USB"
  echo "  $0 --disk sdb --format exFAT --name DATOS"
  echo "  $0 --env usb.env"
  echo "  USB_DISK=disk5 USB_FORMAT=FAT32 $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar .env (solo USB_DISK, USB_FORMAT, USB_NAME)
# ─────────────────────────────────────────────────────────────────────────────
load_env_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    info "No se encontró archivo .env: ${BOLD}$file${RESET} (se omite)"
    return
  fi

  info "Cargando configuración desde: ${BOLD}$file${RESET}"
  local val
  val="$(grep -E '^USB_DISK=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  if [[ -n "$val" ]]; then USB_DISK="$val"; info "  USB_DISK=${BOLD}$val${RESET}"; fi
  val="$(grep -E '^USB_FORMAT=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  if [[ -n "$val" ]]; then USB_FORMAT="$val"; info "  USB_FORMAT=${BOLD}$val${RESET}"; fi
  val="$(grep -E '^USB_NAME=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  if [[ -n "$val" ]]; then USB_NAME="$val"; info "  USB_NAME=${BOLD}$val${RESET}"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--disk)
      ARG_DISK="$2"
      shift 2
      ;;
    -f|--format)
      ARG_FORMAT="$2"
      shift 2
      ;;
    -n|--name)
      ARG_NAME="$2"
      shift 2
      ;;
    --env)
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "argumento desconocido: $1"
      echo
      usage
      exit 1
      ;;
  esac
done

# Cargar .env; args explícitos tienen prioridad
load_env_file "$ENV_FILE"
[[ -n "$ARG_DISK" ]]   && USB_DISK="$ARG_DISK"
[[ -n "$ARG_FORMAT" ]] && USB_FORMAT="$ARG_FORMAT"
[[ -n "$ARG_NAME" ]]   && USB_NAME="$ARG_NAME"

# Normalizar formato a mayúsculas
USB_FORMAT="${USB_FORMAT^^}"

# ─────────────────────────────────────────────────────────────────────────────
# Validar disco
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$USB_DISK" ]]; then
  error "no se especificó el disco (usa --disk, USB_DISK o .env)"
  echo
  usage
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar discos disponibles
# ─────────────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Discos disponibles:${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
if [[ "$OS_TYPE" == "Darwin" ]]; then
  diskutil list
else
  lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null || ls /dev/sd* /dev/nvme* /dev/mmcblk* 2>/dev/null || true
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Validar formato del disco según OS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "Darwin" ]]; then
  if [[ ! "$USB_DISK" =~ ^disk[0-9]+$ ]]; then
    error "formato de disco inválido en macOS. Usa algo como: ${BOLD}disk5${RESET}"
    exit 1
  fi
  DEVICE="/dev/$USB_DISK"
else
  if [[ ! "$USB_DISK" =~ ^(sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+|vd[a-z]+)$ ]]; then
    error "formato de disco inválido en Linux. Usa algo como: ${BOLD}sdb${RESET}, ${BOLD}nvme0n1${RESET}"
    exit 1
  fi
  DEVICE="/dev/$USB_DISK"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Protección: bloquear discos de sistema
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Verificando que el disco no sea parte del sistema..."

if [[ "$OS_TYPE" == "Darwin" ]]; then
  if [[ "$USB_DISK" == "disk0" ]]; then
    error "disk0 es el disco principal del sistema. Operación bloqueada."
    exit 1
  fi

  if ! diskutil info "$DEVICE" &>/dev/null; then
    error "el disco ${BOLD}$DEVICE${RESET} no existe o no está disponible."
    exit 1
  fi

  DISK_INFO="$(diskutil info "$DEVICE")"

  if echo "$DISK_INFO" | grep -qi "Device Location.*Internal"; then
    error "${BOLD}$DEVICE${RESET} es un disco interno del sistema. Operación bloqueada."
    exit 1
  fi

  BOOT_DISK="$(diskutil info / 2>/dev/null | grep 'Part of Whole' | awk '{print $NF}')" || true
  if [[ -n "$BOOT_DISK" && "$USB_DISK" == "$BOOT_DISK" ]]; then
    error "${BOLD}$DEVICE${RESET} contiene el volumen de arranque del sistema. Operación bloqueada."
    exit 1
  fi

  if ! echo "$DISK_INFO" | grep -qiE "Removable Media.*Yes|Device Location.*External"; then
    echo
    echo -e "${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
    echo -e "${YELLOW}${BOLD}│  ⚠  ADVERTENCIA: $DEVICE no parece ser externo/extraíble${RESET}"
    echo -e "${YELLOW}${BOLD}├─────────────────────────────────────────────────────┤${RESET}"
    echo "$DISK_INFO" | grep -E "Device Location|Removable|Protocol" | sed "s/^/$(echo -e "${YELLOW}│${RESET}")  /"
    echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
    echo
    read -rp "$(echo -e "${YELLOW}${BOLD}¿Continuar de todas formas? Escribe YES para aceptar el riesgo:${RESET} ")" FORCE_CONFIRM
    if [[ "$FORCE_CONFIRM" != "YES" ]]; then
      warn "Cancelado."
      exit 0
    fi
  fi
else
  BOOT_DISK="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)" || true
  if [[ -n "$BOOT_DISK" && "$USB_DISK" == "$BOOT_DISK" ]]; then
    error "${BOLD}$DEVICE${RESET} contiene el volumen de arranque del sistema. Operación bloqueada."
    exit 1
  fi

  if [[ ! -b "$DEVICE" ]]; then
    error "el dispositivo ${BOLD}$DEVICE${RESET} no existe o no es un dispositivo de bloque."
    exit 1
  fi

  REMOVABLE="$(cat "/sys/block/$USB_DISK/removable" 2>/dev/null || echo '0')"
  if [[ "$REMOVABLE" != "1" ]]; then
    echo
    echo -e "${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
    echo -e "${YELLOW}${BOLD}│  ⚠  ADVERTENCIA: $DEVICE no parece ser extraíble${RESET}"
    echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
    echo
    read -rp "$(echo -e "${YELLOW}${BOLD}¿Continuar de todas formas? Escribe YES para aceptar el riesgo:${RESET} ")" FORCE_CONFIRM
    if [[ "$FORCE_CONFIRM" != "YES" ]]; then
      warn "Cancelado."
      exit 0
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Validar formato según OS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "Darwin" ]]; then
  case "$USB_FORMAT" in
    FAT32|EXFAT|APFS|HFS+) ;;
    *)
      error "formato no soportado en macOS: ${BOLD}$USB_FORMAT${RESET}. Usa: FAT32, exFAT, APFS, HFS+"
      exit 1
      ;;
  esac
else
  case "$USB_FORMAT" in
    FAT32|EXFAT|EXT4|EXT3|EXT2|NTFS) ;;
    *)
      error "formato no soportado en Linux: ${BOLD}$USB_FORMAT${RESET}. Usa: FAT32, exFAT, ext4, ext3, ext2, NTFS"
      exit 1
      ;;
  esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar información del disco y confirmación final
# ─────────────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Información del disco seleccionado:${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
if [[ "$OS_TYPE" == "Darwin" ]]; then
  diskutil info "$DEVICE"
else
  lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,VENDOR "$DEVICE" 2>/dev/null || true
fi

echo
echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${RED}${BOLD}║               ¡¡ A T E N C I Ó N !!               ║${RESET}"
echo -e "${RED}${BOLD}╠═══════════════════════════════════════════════════╣${RESET}"
echo -e "${RED}${BOLD}║                                                   ║${RESET}"
echo -e "${RED}${BOLD}║${RESET}  Disco destino : ${CYAN}${BOLD}$(printf '%-34s' "$DEVICE")${RESET}${RED}${BOLD} ║${RESET}"
echo -e "${RED}${BOLD}║${RESET}  Formato       : ${CYAN}${BOLD}$(printf '%-34s' "$USB_FORMAT")${RESET}${RED}${BOLD} ║${RESET}"
echo -e "${RED}${BOLD}║${RESET}  Nombre volumen: ${CYAN}${BOLD}$(printf '%-34s' "$USB_NAME")${RESET}${RED}${BOLD} ║${RESET}"
echo -e "${RED}${BOLD}║                                                   ║${RESET}"
echo -e "${RED}${BOLD}║  TODO el contenido del disco será ELIMINADO       ║${RESET}"
echo -e "${RED}${BOLD}║  de forma IRREVERSIBLE. Respalda tus datos.       ║${RESET}"
echo -e "${RED}${BOLD}║                                                   ║${RESET}"
echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo

read -rp "$(echo -e "${RED}${BOLD}Escribe YES (en mayúsculas) para continuar:${RESET} ")" CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  warn "Cancelado."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Formatear disco
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Desmontando ${BOLD}$DEVICE${RESET}..."
if [[ "$OS_TYPE" == "Darwin" ]]; then
  diskutil unmountDisk "$DEVICE"
else
  if command -v udisksctl &>/dev/null; then
    udisksctl unmount -b "$DEVICE" 2>/dev/null || true
  else
    sudo umount "$DEVICE"* 2>/dev/null || true
  fi
fi

echo
info "Formateando ${BOLD}$DEVICE${RESET} como ${BOLD}$USB_FORMAT${RESET} con nombre ${BOLD}$USB_NAME${RESET}..."
echo

if [[ "$OS_TYPE" == "Darwin" ]]; then
  case "$USB_FORMAT" in
    FAT32)
      diskutil eraseDisk FAT32 "$USB_NAME" MBRFormat "$DEVICE"
      ;;
    EXFAT)
      diskutil eraseDisk ExFAT "$USB_NAME" "$DEVICE"
      ;;
    APFS)
      diskutil eraseDisk APFS "$USB_NAME" "$DEVICE"
      ;;
    HFS+)
      diskutil eraseDisk JHFS+ "$USB_NAME" "$DEVICE"
      ;;
  esac
else
  case "$USB_FORMAT" in
    FAT32)
      sudo mkfs.fat -F32 -n "$USB_NAME" "$DEVICE"
      ;;
    EXFAT)
      if ! command -v mkfs.exfat &>/dev/null; then
        error "mkfs.exfat no está instalado. Instala: exfatprogs o exfat-utils"
        exit 1
      fi
      sudo mkfs.exfat -n "$USB_NAME" "$DEVICE"
      ;;
    EXT4)
      sudo mkfs.ext4 -L "$USB_NAME" "$DEVICE"
      ;;
    EXT3)
      sudo mkfs.ext3 -L "$USB_NAME" "$DEVICE"
      ;;
    EXT2)
      sudo mkfs.ext2 -L "$USB_NAME" "$DEVICE"
      ;;
    NTFS)
      if ! command -v mkfs.ntfs &>/dev/null; then
        error "mkfs.ntfs no está instalado. Instala: ntfs-3g"
        exit 1
      fi
      sudo mkfs.ntfs -f -L "$USB_NAME" "$DEVICE"
      ;;
  esac
fi

echo
info "Sincronizando datos..."
sync

echo
success "${BOLD}Listo. $DEVICE formateado como $USB_FORMAT con nombre '$USB_NAME'.${RESET}"
