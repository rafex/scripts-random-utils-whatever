#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# create_usb_macos_debian.sh
# Crea un USB booteable desde una ISO en macOS.
# ─────────────────────────────────────────────────────────────────────────────

USB_ISO="${USB_ISO:-}"
USB_DISK="${USB_DISK:-}"
ARG_ISO=""
ARG_DISK=""
ENV_FILE=".env"

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
  [[ ! -f "$file" ]] && return

  info "Cargando configuración desde: ${BOLD}$file${RESET}"
  local val
  val="$(grep -E '^USB_ISO=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  [[ -n "$val" ]] && USB_ISO="$val"
  val="$(grep -E '^USB_DISK=' "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'")" || true
  [[ -n "$val" ]] && USB_DISK="$val"
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
diskutil list
echo

if [[ -z "$USB_DISK" ]]; then
  read -rp "$(echo -e "${BOLD}Indica el disco USB destino (ejemplo: disk4):${RESET} ")" USB_DISK
fi

if [[ ! "$USB_DISK" =~ ^disk[0-9]+$ ]]; then
  error "formato de disco inválido. Usa algo como: ${BOLD}disk4${RESET}"
  exit 1
fi

DEVICE="/dev/$USB_DISK"
RAW_DEVICE="/dev/r$USB_DISK"

# ─────────────────────────────────────────────────────────────────────────────
# Protección: bloquear discos de sistema
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Verificando que el disco no sea parte del sistema..."

# Bloquear disk0: casi siempre es el disco de arranque en macOS
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

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar información del disco y confirmación final
# ─────────────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Información del disco seleccionado:${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
diskutil info "$DEVICE"

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
# Grabar ISO
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Desmontando ${BOLD}$DEVICE${RESET}..."
diskutil unmountDisk "$DEVICE"

echo
info "Copiando ISO al USB..."
echo -e "  ${YELLOW}Puedes ver el progreso desde otra terminal con:${RESET}"
echo -e "  ${BOLD}  sudo pkill -INFO dd${RESET}"
echo

sudo dd if="$USB_ISO" of="$RAW_DEVICE" bs=4m conv=sync

echo
info "Sincronizando datos..."
sync

info "Expulsando ${BOLD}$DEVICE${RESET}..."
diskutil eject "$DEVICE"

echo
success "${BOLD}Listo. La USB booteable fue creada correctamente.${RESET}"