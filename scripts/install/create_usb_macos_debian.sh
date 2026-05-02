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
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Uso:
  $0 [opciones]

Opciones:
  -f, --from <archivo.iso>    Ruta al archivo ISO fuente
  -t, --to   <diskN>          Disco destino, ejemplo: disk4
      --env  <archivo.env>    Archivo .env con USB_ISO y USB_DISK
  -h, --help                  Mostrar esta ayuda

Variables de entorno:
  USB_ISO    Ruta al archivo ISO
  USB_DISK   Disco destino (ej. disk4)

Formato del .env:
  USB_ISO=/ruta/debian.iso
  USB_DISK=disk4

Ejemplo:
  $0 --from debian.iso --to disk4
  $0 --env config.env
  USB_ISO=debian.iso USB_DISK=disk4 $0
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar .env (solo USB_ISO y USB_DISK para evitar ejecución arbitraria)
# ─────────────────────────────────────────────────────────────────────────────
load_env_file() {
  local file="$1"
  [[ ! -f "$file" ]] && return

  echo "Cargando configuración desde: $file"
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
        echo "Error: argumento desconocido: $1"
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
  echo "Error: no se especificó la ISO (usa --from, USB_ISO o .env)"
  echo
  usage
  exit 1
fi

if [[ ! -f "$USB_ISO" ]]; then
  echo "Error: no existe la ISO: $USB_ISO"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar discos disponibles y solicitar destino si no fue especificado
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════"
echo "  Discos disponibles:"
echo "═══════════════════════════════════════════════════"
diskutil list
echo

if [[ -z "$USB_DISK" ]]; then
  read -rp "Indica el disco USB destino (ejemplo: disk4): " USB_DISK
fi

if [[ ! "$USB_DISK" =~ ^disk[0-9]+$ ]]; then
  echo "Error: formato de disco inválido. Usa algo como: disk4"
  exit 1
fi

DEVICE="/dev/$USB_DISK"
RAW_DEVICE="/dev/r$USB_DISK"

# ─────────────────────────────────────────────────────────────────────────────
# Protección: bloquear discos de sistema
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "Verificando que el disco no sea parte del sistema..."

# Bloquear disk0: casi siempre es el disco de arranque en macOS
if [[ "$USB_DISK" == "disk0" ]]; then
  echo "ERROR: disk0 es el disco principal del sistema. Operación bloqueada."
  exit 1
fi

# Verificar que el disco existe
if ! diskutil info "$DEVICE" &>/dev/null; then
  echo "Error: el disco $DEVICE no existe o no está disponible."
  exit 1
fi

DISK_INFO="$(diskutil info "$DEVICE")"

# Bloquear si es disco interno
if echo "$DISK_INFO" | grep -qi "Device Location.*Internal"; then
  echo "ERROR: $DEVICE es un disco interno del sistema. Operación bloqueada."
  exit 1
fi

# Bloquear si coincide con el disco raíz del sistema
BOOT_DISK="$(diskutil info / 2>/dev/null | grep 'Part of Whole' | awk '{print $NF}')" || true
if [[ -n "$BOOT_DISK" && "$USB_DISK" == "$BOOT_DISK" ]]; then
  echo "ERROR: $DEVICE contiene el volumen de arranque del sistema. Operación bloqueada."
  exit 1
fi

# Advertir si no parece ser extraíble o externo
if ! echo "$DISK_INFO" | grep -qiE "Removable Media.*Yes|Device Location.*External"; then
  echo
  echo "┌─────────────────────────────────────────────────────┐"
  echo "│  ⚠️  ADVERTENCIA: $DEVICE no parece ser externo/extraíble"
  echo "├─────────────────────────────────────────────────────┤"
  echo "$DISK_INFO" | grep -E "Device Location|Removable|Protocol" | sed 's/^/│  /'
  echo "└─────────────────────────────────────────────────────┘"
  echo
  read -rp "¿Continuar de todas formas? Escribe YES para aceptar el riesgo: " FORCE_CONFIRM
  if [[ "$FORCE_CONFIRM" != "YES" ]]; then
    echo "Cancelado."
    exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mostrar información del disco y confirmación final
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════"
echo "  Información del disco seleccionado:"
echo "═══════════════════════════════════════════════════"
diskutil info "$DEVICE"

echo
echo "╔═══════════════════════════════════════════════════╗"
echo "║               ¡¡ A T E N C I Ó N !!               ║"
echo "╠═══════════════════════════════════════════════════╣"
echo "║                                                   ║"
printf "║  ISO origen  : %-34s ║\n" "$USB_ISO"
printf "║  Disco destino: %-33s ║\n" "$DEVICE"
echo "║                                                   ║"
echo "║  TODO el contenido del disco será ELIMINADO       ║"
echo "║  de forma IRREVERSIBLE. Respalda tus datos.       ║"
echo "║                                                   ║"
echo "╚═══════════════════════════════════════════════════╝"
echo

read -rp "Escribe YES (en mayúsculas) para continuar: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelado."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Grabar ISO
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "Desmontando $DEVICE..."
diskutil unmountDisk "$DEVICE"

echo
echo "Copiando ISO al USB..."
echo "Puedes ver el progreso desde otra terminal con:"
echo "  sudo pkill -INFO dd"
echo

sudo dd if="$USB_ISO" of="$RAW_DEVICE" bs=4m conv=sync

echo
echo "Sincronizando datos..."
sync

echo "Expulsando $DEVICE..."
diskutil eject "$DEVICE"

echo
echo "Listo. La USB booteable fue creada correctamente."