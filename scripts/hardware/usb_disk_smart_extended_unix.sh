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
  command -v readlink >/dev/null 2>&1 || { error "falta la dependencia requerida: readlink"; exit 1; }
  command -v systemd-inhibit >/dev/null 2>&1 || { error "falta la dependencia requerida: systemd-inhibit"; exit 1; }
else
  command -v diskutil >/dev/null 2>&1 || { error "falta la dependencia requerida: diskutil"; exit 1; }
  command -v caffeinate >/dev/null 2>&1 || { error "falta la dependencia requerida: caffeinate"; exit 1; }
fi

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  error "sudo es necesario para consultar y ejecutar SMART"
  exit 1
fi

privileged_run() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

smartctl_run() {
  privileged_run smartctl "$@"
}

declare -a DISKS=()
declare -a DISK_LABELS=()
if [[ "$OS_TYPE" == Linux ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r device transport type <<<"$line"
    [[ "$type" == disk && "$transport" == usb ]] || continue
    read -r size_bytes _ <<<"$(lsblk -bdnro SIZE,MODEL "$device" 2>/dev/null || true)"
    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]] || ((size_bytes == 0)); then continue; fi
    size="$(lsblk -dnro SIZE "$device" 2>/dev/null || true)"
    model="$(lsblk -dnro MODEL "$device" 2>/dev/null || true)"
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
USB_PM_FILE=""
USB_PM_ORIGINAL=""
INHIBITOR_PID=""
FINAL_RC=0

restore_usb_power() {
  if [[ -n "$USB_PM_FILE" && -n "$USB_PM_ORIGINAL" && -e "$USB_PM_FILE" ]]; then
    if ! printf '%s\n' "$USB_PM_ORIGINAL" | privileged_run tee "$USB_PM_FILE" >/dev/null; then
      warn "no se pudo restaurar $USB_PM_FILE; restaura manualmente su valor original: $USB_PM_ORIGINAL"
      printf -- "- ⚠ No se restauró \`%s\`; valor original: \`%s\`\n" "$USB_PM_FILE" "$USB_PM_ORIGINAL" >>"$REPORT"
    else
      printf -- "- Restaurado \`%s\` al valor original \`%s\`.\n" "$USB_PM_FILE" "$USB_PM_ORIGINAL" >>"$REPORT"
    fi
  fi
  USB_PM_FILE=""
  USB_PM_ORIGINAL=""
}

# shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap.
cleanup() {
  local exit_status=$?
  restore_usb_power
  if [[ -n "$INHIBITOR_PID" ]]; then
    kill "$INHIBITOR_PID" >/dev/null 2>&1 || true
    wait "$INHIBITOR_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$exit_status" == 130 || "$exit_status" == 143 ]]; then
    printf '\nPrueba interrumpida por una señal; consulta el último estado SMART antes de reintentar.\n' >>"$REPORT"
  fi
  return "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_sleep_inhibitor() {
  if [[ "$OS_TYPE" == Linux ]]; then
    systemd-inhibit --what=sleep:handle-lid-switch --mode=block --why='SMART extended disk self-test' sleep 86400 >/dev/null 2>&1 &
  else
    caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
  fi
  INHIBITOR_PID=$!
  sleep 1
  if ! kill -0 "$INHIBITOR_PID" >/dev/null 2>&1; then
    error 'no se pudo bloquear la suspensión del equipo'
    return 1
  fi
}

set_usb_power_on() {
  local disk="$1" sys_path parent
  [[ "$OS_TYPE" == Linux ]] || return 0
  sys_path="$(readlink -f "/sys/class/block/${disk##*/}/device" 2>/dev/null || true)"
  while [[ -n "$sys_path" && "$sys_path" != / ]]; do
    if [[ -f "$sys_path/idVendor" && -f "$sys_path/idProduct" && -f "$sys_path/power/control" ]]; then
      USB_PM_FILE="$sys_path/power/control"
      USB_PM_ORIGINAL="$(<"$USB_PM_FILE")"
      printf "## Energía USB para %s\n\n- Ruta: \`%s\`\n- Valor original: \`%s\`\n" "$disk" "$USB_PM_FILE" "$USB_PM_ORIGINAL" >>"$REPORT"
      if [[ "$USB_PM_ORIGINAL" != on ]]; then
        info "Desactivando temporalmente autosuspend USB para ${sys_path##*/}."
        if ! printf 'on\n' | privileged_run tee "$USB_PM_FILE" >/dev/null; then
          return 1
        fi
      fi
      return 0
    fi
    parent="${sys_path%/*}"
    [[ "$parent" != "$sys_path" ]] || break
    sys_path="$parent"
  done
  printf '\n' >>"$REPORT"
  warn "no se encontró el control de energía USB del puente de $disk; se mantendrá el disco activo con lecturas periódicas"
  printf "## Energía USB para %s\n\nNo se encontró \`power/control\`; se usará keepalive de lectura.\n\n" "$disk" >>"$REPORT"
  return 0
}

keepalive_read() {
  local disk="$1"
  if [[ "$OS_TYPE" == Linux ]]; then
    privileged_run dd "if=$disk" of=/dev/null bs=4096 count=1 iflag=direct status=none
  else
    privileged_run dd "if=$disk" of=/dev/null bs=4096 count=1 >/dev/null 2>&1
  fi
}

start_sleep_inhibitor || exit 1
printf '## Protección contra suspensión\n\nSuspensión del equipo bloqueada durante las pruebas.\n\n' >>"$REPORT"

for disk in "${SELECTED_DISKS[@]}"; do
  restore_usb_power
  if ! set_usb_power_on "$disk"; then
    error "no se pudo desactivar el autosuspend USB para $disk; no se iniciará el autotest"
    FINAL_RC=1
    continue
  fi

  info "Iniciando autotest SMART extendido en $disk. Si se solicita, introduce tu contraseña de sudo."
  START_OUTPUT=""
  if ! START_OUTPUT="$(smartctl_run -t long "$disk" 2>&1)"; then
    warn "smartctl no pudo iniciar la prueba extendida en $disk"
    FINAL_RC=1
    printf "## %s — no iniciada\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$START_OUTPUT" >>"$REPORT"
    continue
  fi

  printf "## %s — inicio\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$START_OUTPUT" >>"$REPORT"
  success "Prueba iniciada en $disk; se esperará a que termine antes de iniciar el siguiente disco"
  estimated_minutes="$(sed -n 's/.*Please wait \([0-9][0-9]*\) minutes.*/\1/p' <<<"$START_OUTPUT" | head -1)"
  [[ "$estimated_minutes" =~ ^[0-9]+$ ]] || estimated_minutes=300
  deadline=$((SECONDS + estimated_minutes * 60 + 1800))
  disk_done=0

  while ((SECONDS < deadline)); do
    STATUS_OUTPUT="$(smartctl_run -a "$disk" 2>&1 || true)"
    progress="$(awk '/Self-test routine in progress/ {if (match($0, /[0-9]+%/)) {print substr($0, RSTART, RLENGTH); exit}}' <<<"$STATUS_OUTPUT")"
    latest_selftest="$(awk '/SMART Self-test log structure revision number/ {in_log=1; next} in_log && /^[[:space:]]*#[[:space:]]*1[[:space:]]/ {print; exit}' <<<"$STATUS_OUTPUT")"
    if [[ -n "$progress" ]]; then
      info "$disk: prueba en curso, queda aproximadamente $progress; keepalive activo"
      printf -- '- %s — %s restante\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$progress" >>"$REPORT"
    elif grep -Eiq 'Extended offline[[:space:]].*Completed without error' <<<"$latest_selftest"; then
      disk_done=1
      printf "\n## %s — resultado\n\nEstado: **Completada sin errores**.\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$STATUS_OUTPUT" >>"$REPORT"
      success "$disk: prueba extendida completada sin errores"
      break
    elif grep -Eiq 'Extended offline[[:space:]].*(Completed: read failure|Completed: unknown failure|Aborted|Interrupted)' <<<"$latest_selftest"; then
      disk_done=1
      FINAL_RC=1
      printf "\n## %s — resultado\n\nEstado: **falló o fue interrumpida**.\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$STATUS_OUTPUT" >>"$REPORT"
      warn "$disk: el resultado indica error o interrupción; revisa el reporte"
      break
    else
      warn "$disk: no se pudo determinar el estado todavía; se seguirá vigilando"
    fi

    if ! keepalive_read "$disk"; then
      warn "falló la lectura keepalive de $disk; se volverá a intentar en el siguiente ciclo"
    fi
    sleep 60
  done

  if ((disk_done == 0)); then
    FINAL_RC=1
    STATUS_OUTPUT="$(smartctl_run -a "$disk" 2>&1 || true)"
    printf "\n## %s — resultado\n\nEstado: **inconcluso; superó el tiempo esperado más 30 minutos**.\n\n\`\`\`text\n%s\n\`\`\`\n\n" "$disk" "$STATUS_OUTPUT" >>"$REPORT"
    warn "$disk: tiempo máximo superado sin resultado concluyente"
  fi
done

restore_usb_power
if ((FINAL_RC == 0)); then success 'Todas las pruebas finalizaron sin errores'; else warn 'Una o más pruebas fallaron o quedaron inconclusas'; fi
printf '\nReporte guardado en: %s\n' "$REPORT"
exit "$FINAL_RC"
