#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# create_usb_unix.sh
# Crea un USB booteable desde una ISO en macOS y Linux.
# ─────────────────────────────────────────────────────────────────────────────

USB_ISO="${USB_ISO:-}"
USB_DISK="${USB_DISK:-}"
ARG_ISO=""
ARG_DISK=""
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
  echo -e "  ${CYAN}-f, --from${RESET} <archivo.iso>    Ruta al archivo ISO fuente"
  echo -e "  ${CYAN}-t, --to${RESET}   <diskN>          Disco destino, ejemplo: disk4"
  echo -e "  ${CYAN}    --env${RESET}  <archivo.env>    Archivo .env con USB_ISO y USB_DISK"
  echo -e "  ${CYAN}-h, --help${RESET}                  Mostrar esta ayuda"
  echo
  echo -e "${BOLD}Variables de entorno:${RESET}"
  echo -e "  ${CYAN}USB_ISO${RESET}    Ruta al archivo ISO"
  echo -e "  ${CYAN}USB_DISK${RESET}   Disco destino (ej. disk4)"
  echo
  echo -e "${BOLD}Formato del .env:${RESET}"
  echo "  USB_ISO=/ruta/debian.iso"
  echo "  USB_DISK=disk4"
  echo
  echo -e "${BOLD}Ejemplo:${RESET}"
  echo "  $0 --from debian.iso --to disk4"
  echo "  $0 --env config.env"
  echo "  USB_ISO=debian.iso USB_DISK=disk4 $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar .env (solo USB_ISO y USB_DISK para evitar ejecución arbitraria)
# ─────────────────────────────────────────────────────────────────────────────
load_env_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    info "No se encontró archivo .env: ${BOLD}$file${RESET} (se omite)"
    return
  fi

  info "Cargando configuración desde: ${BOLD}$file${RESET}"
  local val
  val="$(grep -E '^USB_ISO=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  if [[ -n "$val" ]]; then USB_ISO="$val"; info "  USB_ISO=${BOLD}$val${RESET}"; fi
  val="$(grep -E '^USB_DISK=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  if [[ -n "$val" ]]; then USB_DISK="$val"; info "  USB_DISK=${BOLD}$val${RESET}"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--from)
      ARG_ISO="$2"
      shift 2
      ;;
    -t|--to)
      ARG_DISK="$2"
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
      # Compatibilidad con uso posicional legacy: primer arg = ISO
      if [[ -z "$ARG_ISO" ]]; then
        ARG_ISO="$1"
      else
        error "argumento desconocido: $1"
        echo
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Cargar .env y luego los args explícitos tienen prioridad
load_env_file "$ENV_FILE"
[[ -n "$ARG_ISO" ]]  && USB_ISO="$ARG_ISO"
[[ -n "$ARG_DISK" ]] && USB_DISK="$ARG_DISK"

# ─────────────────────────────────────────────────────────────────────────────
# Validar ISO
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$USB_ISO" ]]; then
  error "no se especificó la ISO (usa --from, USB_ISO o .env)"
  echo
  usage
  exit 1
fi

if [[ ! -f "$USB_ISO" ]]; then
  error "no existe la ISO: ${BOLD}$USB_ISO${RESET}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar discos disponibles y solicitar destino si no fue especificado
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

if [[ -z "$USB_DISK" ]]; then
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    read -rp "$(echo -e "${BOLD}Indica el disco USB destino (ejemplo: disk4):${RESET} ")" USB_DISK
  else
    read -rp "$(echo -e "${BOLD}Indica el disco USB destino (ejemplo: sdb):${RESET} ")" USB_DISK
  fi
fi

# Validar formato según OS
if [[ "$OS_TYPE" == "Darwin" ]]; then
  if [[ ! "$USB_DISK" =~ ^disk[0-9]+$ ]]; then
    error "formato de disco inválido en macOS. Usa algo como: ${BOLD}disk4${RESET}"
    exit 1
  fi
  DEVICE="/dev/$USB_DISK"
  RAW_DEVICE="/dev/r$USB_DISK"
else
  if [[ ! "$USB_DISK" =~ ^(sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+|vd[a-z]+)$ ]]; then
    error "formato de disco inválido en Linux. Usa algo como: ${BOLD}sdb${RESET}, ${BOLD}nvme0n1${RESET}"
    exit 1
  fi
  DEVICE="/dev/$USB_DISK"
  RAW_DEVICE="/dev/$USB_DISK"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Protección: bloquear discos de sistema
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Verificando que el disco no sea parte del sistema..."

if [[ "$OS_TYPE" == "Darwin" ]]; then
  # macOS: bloquear disk0
  if [[ "$USB_DISK" == "disk0" ]]; then
    error "disk0 es el disco principal del sistema. Operación bloqueada."
    exit 1
  fi

  # Verificar que el disco existe
  if ! diskutil info "$DEVICE" &>/dev/null; then
    error "el disco ${BOLD}$DEVICE${RESET} no existe o no está disponible."
    exit 1
  fi

  DISK_INFO="$(diskutil info "$DEVICE")"

  # Bloquear si es disco interno
  if echo "$DISK_INFO" | grep -qi "Device Location.*Internal"; then
    error "${BOLD}$DEVICE${RESET} es un disco interno del sistema. Operación bloqueada."
    exit 1
  fi

  # Bloquear si coincide con el disco raíz del sistema
  BOOT_DISK="$(diskutil info / 2>/dev/null | grep 'Part of Whole' | awk '{print $NF}')" || true
  if [[ -n "$BOOT_DISK" && "$USB_DISK" == "$BOOT_DISK" ]]; then
    error "${BOLD}$DEVICE${RESET} contiene el volumen de arranque del sistema. Operación bloqueada."
    exit 1
  fi

  # Advertir si no parece ser extraíble o externo
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
  # Linux: bloquear sda/nvme0n1 si es el disco de boot
  BOOT_DISK="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)" || true
  if [[ -n "$BOOT_DISK" && "$USB_DISK" == "$BOOT_DISK" ]]; then
    error "${BOLD}$DEVICE${RESET} contiene el volumen de arranque del sistema. Operación bloqueada."
    exit 1
  fi

  # Verificar que el disco existe
  if [[ ! -b "$DEVICE" ]]; then
    error "el dispositivo ${BOLD}$DEVICE${RESET} no existe o no es un dispositivo de bloque."
    exit 1
  fi

  # Advertir si no parece ser extraíble
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
echo -e "${RED}${BOLD}║${RESET}  ISO origen  : ${CYAN}${BOLD}$(printf '%-34s' "$USB_ISO")${RESET}${RED}${BOLD} ║${RESET}"
echo -e "${RED}${BOLD}║${RESET}  Disco destino: ${CYAN}${BOLD}$(printf '%-33s' "$DEVICE")${RESET}${RED}${BOLD} ║${RESET}"
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
# Detectar método de progreso disponible
# ─────────────────────────────────────────────────────────────────────────────
dd_with_progress() {
  local iso="$1" dest="$2"

  if command -v pv &>/dev/null; then
    info "Usando ${BOLD}pv${RESET} para mostrar progreso..."
    pv "$iso" | sudo dd of="$dest" bs=4m conv=sync
  elif [[ "$OS_TYPE" == "Linux" ]]; then
    info "Usando ${BOLD}dd status=progress${RESET}..."
    sudo dd if="$iso" of="$dest" bs=4M conv=sync status=progress
  else
    # macOS: dd en background + bucle de SIGINFO cada 5 segundos
    info "Usando ${BOLD}dd${RESET} con SIGINFO periódico (macOS)..."
    sudo dd if="$iso" of="$dest" bs=4m conv=sync &
    local dd_pid=$!
    while kill -0 "$dd_pid" 2>/dev/null; do
      sleep 5
      kill -INFO "$dd_pid" 2>/dev/null || true
    done
    wait "$dd_pid"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Grabar ISO
# ─────────────────────────────────────────────────────────────────────────────
echo
if [[ "$OS_TYPE" == "Darwin" ]]; then
  info "Desmontando ${BOLD}$DEVICE${RESET}..."
  diskutil unmountDisk "$DEVICE"
else
  info "Desmontando ${BOLD}$DEVICE${RESET}..."
  if command -v udisksctl &>/dev/null; then
    udisksctl unmount -b "$DEVICE" 2>/dev/null || true
  else
    sudo umount "$DEVICE"* 2>/dev/null || true
  fi
fi

echo
info "Copiando ISO al USB..."
echo

dd_with_progress "$USB_ISO" "$RAW_DEVICE"

echo
info "Sincronizando datos..."
sync

if [[ "$OS_TYPE" == "Darwin" ]]; then
  info "Expulsando ${BOLD}$DEVICE${RESET}..."
  diskutil eject "$DEVICE"
else
  info "Expulsando ${BOLD}$DEVICE${RESET}..."
  if command -v udisksctl &>/dev/null; then
    udisksctl power-off -b "$DEVICE" 2>/dev/null || true
  else
    sudo eject "$DEVICE" 2>/dev/null || true
  fi
fi

echo
success "${BOLD}Listo. La USB booteable fue creada correctamente.${RESET}"