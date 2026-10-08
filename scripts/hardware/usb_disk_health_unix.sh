#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="${0##*/}"
OS_TYPE="$(uname -s)"
WRITE_SIZE="1G"
TEST_FILE=""
REPORT_DIR=""

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf "${CYAN}${BOLD}  →${RESET} %s\n" "$*"; }
success() { printf "${GREEN}${BOLD}  ✓${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}${BOLD}  ⚠${RESET} %s\n" "$*" >&2; }
error() { printf "${RED}${BOLD}  ✗ ERROR:${RESET} %s\n" "$*" >&2; }

usage() {
  cat <<EOF
Uso:
  just disk-health [--size <tamano>]
  bash scripts/hardware/$SCRIPT_NAME [--size <tamano>]

Opciones:
  --size <tamano>   Cantidad de datos de escritura (K, M o G); defecto: 1G
  -h, --help        Mostrar esta ayuda

El script lista discos externos y puntos de montaje, consulta SMART y escribe
un archivo temporal secuencial que elimina al finalizar. El reporte se guarda
en /tmp (o en el directorio indicado por TMPDIR).
EOF
}

cleanup() {
  if [[ -n "$TEST_FILE" && -e "$TEST_FILE" ]]; then
    rm -f -- "$TEST_FILE" || warn "No se pudo borrar el archivo temporal: $TEST_FILE"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while (($#)); do
  case "$1" in
    --size)
      (($# >= 2)) || { error "falta el valor de --size"; usage; exit 2; }
      WRITE_SIZE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "opción desconocida: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ ! "$WRITE_SIZE" =~ ^[1-9][0-9]*[KMG]$ ]]; then
  error "tamaño inválido: usa un entero seguido de K, M o G (por ejemplo 1G)"
  exit 2
fi

case "$OS_TYPE" in
  Linux|Darwin) ;;
  *) error "sistema operativo no soportado: $OS_TYPE"; exit 1 ;;
esac

for command_name in fio smartctl python3 df; do
  command -v "$command_name" >/dev/null 2>&1 || {
    error "falta la dependencia requerida: $command_name"
    exit 1
  }
done

if [[ "$OS_TYPE" == Linux ]]; then
  command -v lsblk >/dev/null 2>&1 || { error "falta la dependencia requerida: lsblk"; exit 1; }
  command -v findmnt >/dev/null 2>&1 || { error "falta la dependencia requerida: findmnt"; exit 1; }
else
  command -v diskutil >/dev/null 2>&1 || { error "falta la dependencia requerida: diskutil"; exit 1; }
fi

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  error "sudo es necesario para consultar SMART"
  exit 1
fi

smartctl_run() {
  if [[ $EUID -eq 0 ]]; then
    smartctl "$@"
  else
    sudo smartctl "$@"
  fi
}

declare -a DISKS=()
declare -a DISK_LABELS=()
if [[ "$OS_TYPE" == Linux ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r device transport type <<<"$line"
    [[ "$type" == disk ]] || continue
    [[ "$transport" == usb ]] || continue
    read -r size model <<<"$(lsblk -dnro SIZE,MODEL "$device" 2>/dev/null || true)"
    DISKS+=("$device")
    DISK_LABELS+=("$device  $size  ${model:-modelo desconocido}")
  done < <(lsblk -dpno NAME,TRAN,TYPE 2>/dev/null)
else
  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    detail="$(diskutil info "$device" 2>/dev/null || true)"
    model="$(awk -F: '/Media Name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<<"$detail")"
    size="$(awk -F: '/Disk Size/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<<"$detail")"
    DISKS+=("$device")
    DISK_LABELS+=("$device  ${size:-tamaño desconocido}  ${model:-modelo desconocido}")
  done < <(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk[0-9]+[[:space:]]/ {print $1}')
fi

if ((${#DISKS[@]} == 0)); then
  error "no se encontraron discos externos USB"
  exit 1
fi

printf '\n%s\n' 'Discos externos detectados:'
for i in "${!DISKS[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${DISK_LABELS[$i]}"; done
read -rp 'Selecciona el disco por número: ' selection
[[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#DISKS[@]})) || {
  error "selección de disco inválida"
  exit 2
}
DISK="${DISKS[$((selection - 1))]}"

printf '\nPuntos de montaje disponibles:\n'
if [[ "$OS_TYPE" == Linux ]]; then
  findmnt -rn -o TARGET,SOURCE,FSTYPE | awk '$1 ~ /^\// {print}'
else
  df -P
fi
read -r -p 'Escribe el punto de montaje del disco seleccionado: ' MOUNTPOINT
[[ -n "$MOUNTPOINT" ]] || { error "no se indicó un punto de montaje"; exit 2; }

if [[ ! -d "$MOUNTPOINT" || ! -w "$MOUNTPOINT" ]]; then
  error "el punto de montaje no existe o no permite escritura: $MOUNTPOINT"
  exit 1
fi

if [[ "$OS_TYPE" == Linux ]]; then
  SOURCE_DEVICE="$(findmnt -nro SOURCE --target "$MOUNTPOINT" | head -1)"
  SOURCE_DEVICE="${SOURCE_DEVICE%%\[*}"
  SOURCE_NAME="${SOURCE_DEVICE##*/}"
  PARENT_NAME="$(lsblk -nro PKNAME "$SOURCE_DEVICE" 2>/dev/null | head -1 || true)"
  MOUNT_DISK="${PARENT_NAME:-$SOURCE_NAME}"
  SELECTED_NAME="${DISK##*/}"
  BOOT_SOURCE="$(findmnt -nro SOURCE --target / 2>/dev/null | head -1 || true)"
  BOOT_NAME="${BOOT_SOURCE##*/}"
  BOOT_PARENT="$(lsblk -nro PKNAME "$BOOT_SOURCE" 2>/dev/null | head -1 || true)"
  BOOT_DISK="${BOOT_PARENT:-$BOOT_NAME}"
  if [[ "$SELECTED_NAME" == "$BOOT_DISK" ]]; then
    error "el disco seleccionado contiene el filesystem raíz del sistema; operación bloqueada"
    exit 1
  fi
else
  SOURCE_DEVICE="$(df -P "$MOUNTPOINT" | awk 'NR == 2 {print $1}')"
  MOUNT_DISK="$(sed -E 's#^/dev/(r)?(disk[0-9]+).*#\2#' <<<"$SOURCE_DEVICE")"
  SELECTED_NAME="${DISK##*/}"
  BOOT_SOURCE="$(df -P / | awk 'NR == 2 {print $1}')"
  BOOT_DISK="$(sed -E 's#^/dev/(r)?(disk[0-9]+).*#\2#' <<<"$BOOT_SOURCE")"
  if [[ "$SELECTED_NAME" == "$BOOT_DISK" ]]; then
    error "el disco seleccionado contiene el filesystem raíz del sistema; operación bloqueada"
    exit 1
  fi
fi

if [[ "$MOUNT_DISK" != "$SELECTED_NAME" ]]; then
  error "el punto de montaje $MOUNTPOINT pertenece a ${SOURCE_DEVICE:-otro disco}, no a $DISK"
  exit 1
fi

SIZE_BYTES="$(python3 -c 'import sys; n=int(sys.argv[1][:-1]); u=sys.argv[1][-1]; print(n * {"K":1024,"M":1024**2,"G":1024**3}[u])' "$WRITE_SIZE")"
AVAILABLE_KIB="$(df -Pk "$MOUNTPOINT" | awk 'NR == 2 {print $4}')"
AVAILABLE_BYTES=$((AVAILABLE_KIB * 1024))
if ((AVAILABLE_BYTES < SIZE_BYTES + 134217728)); then
  error "espacio libre insuficiente; se necesitan $WRITE_SIZE más 128 MiB de margen"
  exit 1
fi

echo
printf '%s\n' "Destino: $DISK" "Montaje: $MOUNTPOINT" "Escritura secuencial: $WRITE_SIZE (un archivo temporal)"
read -rp 'Para continuar escribe YES: ' confirmation
if [[ "$confirmation" != YES ]]; then
  info 'Operación cancelada.'
  exit 0
fi

REPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/usb-disk-health.XXXXXX")"
REPORT="$REPORT_DIR/REPORTE.md"
{
  printf '# Reporte de salud y escritura USB\n\n'
  printf -- '- Fecha: %s\n- Sistema: %s\n- Disco: `%s`\n- Montaje: `%s`\n- Escritura solicitada: `%s`\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$OS_TYPE" "$DISK" "$MOUNTPOINT" "$WRITE_SIZE"
  printf '## SMART antes de la prueba\n\n'
} >"$REPORT"

info 'Consultando SMART. Si se solicita, introduce tu contraseña de sudo.'
SMART_BEFORE="$(smartctl_run -a "$DISK" 2>&1)" || SMART_BEFORE_RC=$?
SMART_BEFORE_RC="${SMART_BEFORE_RC:-0}"
printf '%s\n' '```text' "$SMART_BEFORE" '```' >>"$REPORT"
if ((SMART_BEFORE_RC != 0)); then
  warn "smartctl devolvió estado $SMART_BEFORE_RC; revisa si el puente USB permite el acceso SMART"
fi

info 'Solicitando la prueba corta SMART (si el dispositivo la soporta).'
SMART_TEST="$(smartctl_run -t short "$DISK" 2>&1)" || SMART_TEST_RC=$?
SMART_TEST_RC="${SMART_TEST_RC:-0}"
{
  printf '\n## Inicio de autotest SMART corto\n\n```text\n%s\n```\n' "$SMART_TEST"
} >>"$REPORT"
if ((SMART_TEST_RC != 0)); then
  warn 'no se pudo iniciar el autotest SMART corto; se continuará con la prueba de escritura'
fi

TEST_FILE="$(mktemp "$MOUNTPOINT/.usb-disk-health.XXXXXX")"
info "Escribiendo $WRITE_SIZE con fio; el archivo temporal se eliminará al finalizar."
FIO_OUTPUT="$REPORT_DIR/fio.json"
if ! fio --name=usb-disk-health --filename="$TEST_FILE" --size="$WRITE_SIZE" --rw=write --bs=1M --ioengine=sync --end_fsync=1 --group_reporting --eta=never --output-format=json --output="$FIO_OUTPUT"; then
  error 'fio falló durante la prueba de escritura'
  exit 1
fi

WRITE_SUMMARY="$(python3 - "$FIO_OUTPUT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
job = data["jobs"][0]["write"]
written = job.get("io_bytes", 0)
bw = job.get("bw_bytes", 0)
lat = job.get("clat_ns", {}).get("mean", 0)
print(f"{written}\t{bw / (1024 * 1024):.2f}\t{lat / 1_000_000:.2f}")
PY
)"
IFS=$'\t' read -r WRITTEN_BYTES WRITE_MBPS LATENCY_MS <<<"$WRITE_SUMMARY"
{
  printf '\n## Resultado de escritura\n\n'
  printf -- '- Bytes escritos: %s\n- Rendimiento medio: %s MiB/s\n- Latencia media: %s ms\n' "$WRITTEN_BYTES" "$WRITE_MBPS" "$LATENCY_MS"
  printf -- '- Archivo de prueba: `%s` (se elimina al salir)\n' "$TEST_FILE"
  printf '\n## SMART después de la prueba\n\n```text\n'
} >>"$REPORT"

SMART_AFTER="$(smartctl_run -a "$DISK" 2>&1)" || SMART_AFTER_RC=$?
SMART_AFTER_RC="${SMART_AFTER_RC:-0}"
printf '%s\n' "$SMART_AFTER" '```' >>"$REPORT"
if ((SMART_AFTER_RC != 0)); then
  warn "smartctl devolvió estado $SMART_AFTER_RC al consultar el estado final"
fi

rm -f -- "$TEST_FILE"
TEST_FILE=""
success "Prueba terminada. Reporte: $REPORT"
if ((SMART_TEST_RC == 0)); then
  info 'El autotest SMART puede seguir en curso; el reporte conserva la salida de smartctl para consultar su estado.'
fi
