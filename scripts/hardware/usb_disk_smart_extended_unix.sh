#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="${0##*/}"
OS_TYPE="$(uname -s)"
SELECT_ALL=0
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
  just disk-smart-extended [--all]
  bash scripts/hardware/$SCRIPT_NAME [--all]

Opciones:
  --all       Ejecutar la prueba SMART extendida en todos los discos USB externos
  -h, --help  Mostrar esta ayuda

La prueba es de solo lectura, puede tardar varias horas y el reporte se guarda
en /tmp (o en el directorio indicado por TMPDIR).
EOF
}

while (($#)); do
  case "$1" in
    --all) SELECT_ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "opción desconocida: $1"; usage; exit 2 ;;
  esac
done

case "$OS_TYPE" in
  Linux|Darwin) ;;
  *) error "sistema operativo no soportado: $OS_TYPE"; exit 1 ;;
esac

for command_name in smartctl date; do
  command -v "$command_name" >/dev/null 2>&1 || {
    error "falta la dependencia requerida: $command_name"
    exit 1
  }
done

if [[ "$OS_TYPE" == Linux ]]; then
  command -v lsblk >/dev/null 2>&1 || { error "falta la dependencia requerida: lsblk"; exit 1; }
else
  command -v diskutil >/dev/null 2>&1 || { error "falta la dependencia requerida: diskutil"; exit 1; }
fi

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  error "sudo es necesario para consultar y ejecutar SMART"
  exit 1
fi

smartctl_run() {
  if [[ $EUID -eq 0 ]]; then smartctl "$@"; else sudo smartctl "$@"; fi
}

declare -a DISKS=()
declare -a DISK_LABELS=()
if [[ "$OS_TYPE" == Linux ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r device transport type <<<"$line"
    [[ "$type" == disk && "$transport" == usb ]] || continue
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

declare -a SELECTED_DISKS=()
if ((SELECT_ALL)); then
  SELECTED_DISKS=("${DISKS[@]}")
else
  read -rp 'Selecciona el disco por número (o all para todos): ' selection
  if [[ "$selection" == all ]]; then
    SELECTED_DISKS=("${DISKS[@]}")
  elif [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#DISKS[@]})); then
    SELECTED_DISKS=("${DISKS[$((selection - 1))]}")
  else
    error "selección inválida"
    exit 2
  fi
fi

echo
printf 'Prueba SMART extendida de solo lectura en:\n'
for disk in "${SELECTED_DISKS[@]}"; do
  for i in "${!DISKS[@]}"; do
    if [[ "${DISKS[$i]}" == "$disk" ]]; then printf '  - %s\n' "${DISK_LABELS[$i]}"; fi
  done
done
printf '\nEl proceso puede tardar varias horas; el equipo debe permanecer encendido.\n'
read -rp 'Para continuar escribe YES: ' confirmation
[[ "$confirmation" == YES ]] || { info 'Operación cancelada.'; exit 0; }

REPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/usb-smart-extended.XXXXXX")"
REPORT="$REPORT_DIR/REPORTE.md"
printf '# Reporte SMART extendido USB\n\n- Fecha: %s\n- Sistema: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$OS_TYPE" >"$REPORT"
declare -a ACTIVE_DISKS=()

for disk in "${SELECTED_DISKS[@]}"; do
  info "Iniciando autotest SMART extendido en $disk. Si se solicita, introduce tu contraseña de sudo."
  START_OUTPUT=""
  if START_OUTPUT="$(smartctl_run -t long "$disk" 2>&1)"; then
    ACTIVE_DISKS+=("$disk")
    success "Prueba iniciada en $disk"
  else
    warn "smartctl no pudo iniciar la prueba extendida en $disk"
  fi
  printf "## %s — inicio\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$START_OUTPUT" >>"$REPORT"
done

if ((${#ACTIVE_DISKS[@]} == 0)); then
  error "no se pudo iniciar ninguna prueba; revisa el reporte $REPORT"
  exit 1
fi

declare -A COMPLETED=()
for disk in "${ACTIVE_DISKS[@]}"; do COMPLETED["$disk"]=0; done

while :; do
  pending=0
  for disk in "${ACTIVE_DISKS[@]}"; do
    [[ "${COMPLETED[$disk]}" == 1 ]] && continue
    pending=$((pending + 1))
    STATUS_OUTPUT="$(smartctl_run -a "$disk" 2>&1 || true)"
    progress="$(awk '/Self-test routine in progress/ {if (match($0, /[0-9]+%/)) {print substr($0, RSTART, RLENGTH); exit}}' <<<"$STATUS_OUTPUT")"
    if [[ -n "$progress" ]]; then
      info "$disk: prueba en curso, queda aproximadamente $progress"
    elif grep -Eiq 'Extended offline[[:space:]].*Completed without error' <<<"$STATUS_OUTPUT"; then
      COMPLETED["$disk"]=1
      printf "## %s — resultado\n\nEstado: **Completada sin errores**.\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$STATUS_OUTPUT" >>"$REPORT"
      success "$disk: prueba extendida completada sin errores"
    elif grep -Eiq 'Extended offline[[:space:]].*(Completed: read failure|Completed: unknown failure|Aborted|Interrupted)' <<<"$STATUS_OUTPUT"; then
      COMPLETED["$disk"]=1
      printf "## %s — resultado\n\nEstado: **falló o fue interrumpida**.\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$STATUS_OUTPUT" >>"$REPORT"
      warn "$disk: el resultado indica error o interrupción; revisa el reporte"
    elif grep -q 'No self-tests have been logged' <<<"$STATUS_OUTPUT"; then
      warn "$disk: aún no aparece el resultado del autotest; se volverá a consultar"
    else
      warn "$disk: no se pudo determinar el estado; se volverá a consultar"
    fi
  done
  ((pending == 0)) && break
  sleep 60
done

printf '\nReporte guardado en: %s\n' "$REPORT"
