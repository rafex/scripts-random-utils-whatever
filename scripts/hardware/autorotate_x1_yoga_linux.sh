#!/usr/bin/env bash
# shellcheck shell=bash
#
# Rotación automática para ThinkPad X1 Yoga de primera generación en Xorg.
# La rotación se ejecuta como usuario dentro de la sesión gráfica.
set -Eeuo pipefail

SCRIPT_NAME="autorotate-x1-yoga.sh"
MODE="check"
ORIENTATION="normal"
SENSOR_ONLY=0
DISABLE_INPUTS="${AUTOROTATE_DISABLE_INPUTS:-0}"
SCREEN_INTERNAL="${SCREEN_INTERNAL:-}"
TABLET_MODE_FILE="/sys/devices/platform/thinkpad_acpi/hotkey_tablet_mode"
LAST_ORIENTATION=""
LAST_TABLET_MODE=""
SENSOR_DIR=""
SENSOR_PID=""

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
  autorotate_x1_yoga.sh --check
  autorotate_x1_yoga.sh --once --orientation normal|right|inverted|left
  autorotate_x1_yoga.sh --daemon
  autorotate_x1_yoga.sh --daemon --sensor-only

Opciones:
  --check                 Diagnóstico sin modificar la sesión gráfica
  --once                  Aplicar una orientación y terminar
  --daemon                Escuchar sensor y modo tablet continuamente
  --orientation VALOR     normal, right, inverted o left
  --sensor-only           Ignorar hotkey_tablet_mode y usar solo el sensor
  --disable-inputs        Desactivar teclado/touchpad/TrackPoint en modo tablet
  --enable-inputs         No desactivar dispositivos de entrada (default)
  -h, --help              Mostrar esta ayuda

Variables de entorno:
  SCREEN_INTERNAL                 Salida interna de xrandr, si se desea fijar
  AUTOROTATE_DISABLE_INPUTS=1    Equivalente a --disable-inputs
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) MODE="check"; shift ;;
      --once) MODE="once"; shift ;;
      --daemon) MODE="daemon"; shift ;;
      --orientation)
        [[ $# -ge 2 ]] || die "--orientation requiere un valor"
        ORIENTATION="$2"
        shift 2
        ;;
      --sensor-only) SENSOR_ONLY=1; shift ;;
      --disable-inputs) DISABLE_INPUTS=1; shift ;;
      --enable-inputs) DISABLE_INPUTS=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  case "$ORIENTATION" in
    normal|right|right-up|inverted|bottom-up|left|left-up) ;;
    *) die "orientación inválida: $ORIENTATION" ;;
  esac

  if [[ "$SENSOR_ONLY" -eq 1 && "$MODE" == "once" ]]; then
    warn "--sensor-only no tiene efecto con --once"
  fi
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script solo funciona en Linux"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"
}

normalize_orientation() {
  case "$1" in
    normal) echo normal ;;
    right|right-up) echo right ;;
    inverted|bottom-up) echo inverted ;;
    left|left-up) echo left ;;
  esac
}

xrandr_rotation() {
  case "$(normalize_orientation "$1")" in
    normal) echo normal ;;
    right) echo right ;;
    inverted) echo inverted ;;
    left) echo left ;;
  esac
}

wacom_rotation() {
  case "$(normalize_orientation "$1")" in
    normal) echo none ;;
    right) echo cw ;;
    inverted) echo half ;;
    left) echo ccw ;;
  esac
}

xinput_matrix() {
  case "$(normalize_orientation "$1")" in
    normal) echo "1 0 0 0 1 0 0 0 1" ;;
    right) echo "0 -1 1 1 0 0 0 0 1" ;;
    inverted) echo "-1 0 1 0 -1 1 0 0 1" ;;
    left) echo "0 1 0 -1 0 1 0 0 1" ;;
  esac
}

internal_output() {
  local output
  require_command xrandr
  if [[ -n "$SCREEN_INTERNAL" ]]; then
    xrandr --query | awk -v output="$SCREEN_INTERNAL" '$1 == output && $2 == "connected" { found=1 } END { exit(found ? 0 : 1) }' ||
      die "SCREEN_INTERNAL no está conectado: $SCREEN_INTERNAL"
    echo "$SCREEN_INTERNAL"
    return 0
  fi
  output="$(xrandr --query | awk '$1 ~ /^(eDP|LVDS|DSI)-/ && $2 == "connected" { print $1; exit }')"
  [[ -n "$output" ]] || die "no se detectó una salida interna eDP/LVDS/DSI"
  echo "$output"
}

tablet_mode() {
  if [[ "$SENSOR_ONLY" -eq 1 ]]; then
    echo 1
  elif [[ -r "$TABLET_MODE_FILE" ]]; then
    tr -d '[:space:]' < "$TABLET_MODE_FILE"
  else
    echo unknown
  fi
}

log_event() {
  if command -v logger >/dev/null 2>&1; then
    logger -t "$SCRIPT_NAME" -- "$*"
  fi
}

notify_failure() {
  log_event "ERROR: $*"
  if [[ -n "${DISPLAY:-}" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Rotación automática" "$*" >/dev/null 2>&1 || true
  fi
}

cleanup_sensor() {
  if [[ -n "${SENSOR_PID:-}" ]]; then
    kill "$SENSOR_PID" 2>/dev/null || true
  fi
  if [[ -n "${SENSOR_DIR:-}" ]]; then
    rm -rf "$SENSOR_DIR"
  fi
}

trim_device_name() {
  sed -E 's/[[:space:]]+id:.*$//' | sed -E 's/[[:space:]]+$//'
}

wacom_devices() {
  command -v xsetwacom >/dev/null 2>&1 || return 0
  xsetwacom --list devices 2>/dev/null | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line" | trim_device_name
  done
}

xinput_tablet_devices() {
  command -v xinput >/dev/null 2>&1 || return 0
  xinput --list --name-only 2>/dev/null | grep -iE 'wacom|pen|touch|finger' || true
}

rotate_wacom_devices() {
  local orientation="$1"
  local rotation
  local device
  local found=0
  local applied=0
  rotation="$(wacom_rotation "$orientation")"

  if ! command -v xsetwacom >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    found=1
    if xsetwacom set "$device" Rotate "$rotation" >/dev/null 2>&1; then
      applied=1
    else
      warn "no se pudo orientar dispositivo Wacom: $device"
    fi
  done < <(wacom_devices)

  [[ "$found" -eq 1 && "$applied" -eq 1 ]]
}

rotate_xinput_devices() {
  local orientation="$1"
  local matrix
  local -a matrix_values
  local device
  local found=0
  matrix="$(xinput_matrix "$orientation")"
  read -r -a matrix_values <<< "$matrix"

  command -v xinput >/dev/null 2>&1 || return 1
  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    if xinput list-props "$device" 2>/dev/null | grep -Fq 'Coordinate Transformation Matrix'; then
      found=1
      xinput set-prop "$device" 'Coordinate Transformation Matrix' "${matrix_values[@]}" >/dev/null 2>&1 ||
        warn "no se pudo orientar dispositivo libinput: $device"
    fi
  done < <(xinput_tablet_devices)
  [[ "$found" -eq 1 ]]
}

rotate_input_devices() {
  local orientation="$1"
  if ! rotate_wacom_devices "$orientation"; then
    rotate_xinput_devices "$orientation" || warn "no se detectó un dispositivo táctil/lápiz reorientable"
  fi
}

set_tablet_input_state() {
  local mode="$1"
  local device
  local action="enable"

  [[ "$DISABLE_INPUTS" == "1" ]] || return 0
  command -v xinput >/dev/null 2>&1 || return 0
  [[ "$mode" == "1" ]] && action="disable"

  while IFS= read -r device; do
    case "$device" in
      "AT Translated Set 2 keyboard"|"TPPS/2 IBM TrackPoint"|"SynPS/2 Synaptics TouchPad")
        xinput "$action" "$device" >/dev/null 2>&1 || warn "no se pudo $action: $device"
        ;;
    esac
  done < <(xinput --list --name-only 2>/dev/null || true)
}

apply_orientation() {
  local orientation="$1"
  local normalized
  local output
  normalized="$(normalize_orientation "$orientation")"
  output="$(internal_output)"

  if ! xrandr --output "$output" --rotate "$(xrandr_rotation "$normalized")" >/dev/null 2>&1; then
    notify_failure "xrandr no pudo rotar $output a $normalized"
    return 1
  fi
  rotate_input_devices "$normalized"
  LAST_ORIENTATION="$normalized"
  log_event "orientación aplicada: $normalized en $output"
  ok "orientación aplicada: $normalized ($output)"
}

check_sensor() {
  if ! command -v monitor-sensor >/dev/null 2>&1; then
    warn "monitor-sensor no está instalado"
    return 0
  fi
  local sample
  sample="$(timeout 4s monitor-sensor --accel 2>&1 || true)"
  if [[ -n "$sample" ]]; then
    echo "$sample"
    if grep -q 'Accelerometer orientation changed' <<< "$sample"; then
      ok "iio-sensor-proxy entregó eventos de orientación"
    else
      warn "no se recibió un evento de orientación durante la prueba"
    fi
  else
    warn "monitor-sensor no produjo salida; prueba desde Alacritty dentro de i3"
  fi
}

check_session() {
  [[ -n "${DISPLAY:-}" ]] || warn "DISPLAY no está definido; ejecuta la prueba desde la sesión Xorg local"
  [[ -n "${DISPLAY:-}" ]] || return 1
  require_command xrandr
}

check() {
  echo -e "${BOLD}${CYAN}═══ Rotación ThinkPad X1 Yoga ═══${RESET}"
  printf 'tablet-mode-file='; [[ -e "$TABLET_MODE_FILE" ]] && echo "$TABLET_MODE_FILE" || echo missing
  if [[ -r "$TABLET_MODE_FILE" ]]; then
    printf 'tablet-mode=%s\n' "$(tablet_mode)"
  fi
  echo "iio-devices:"
  find /sys/bus/iio/devices -maxdepth 1 -type l -name 'iio:device*' -print 2>/dev/null | sort || true
  if [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1; then
    echo "xrandr:"
    xrandr --query || true
    printf 'internal-output='; internal_output || true
  else
    warn "xrandr requiere una sesión gráfica Xorg activa"
  fi
  if [[ -n "${DISPLAY:-}" ]] && command -v xinput >/dev/null 2>&1; then
    echo "xinput-tablet-devices:"
    xinput_tablet_devices || true
  fi
  echo "wacom-devices:"
  if command -v xsetwacom >/dev/null 2>&1; then
    xsetwacom --list devices 2>/dev/null || true
  else
    warn "xsetwacom no está instalado"
  fi
  check_sensor
}

daemon() {
  require_command xrandr
  require_command monitor-sensor
  require_command flock
  check_session || die "la etapa daemon requiere DISPLAY en una sesión Xorg local"
  if [[ "$SENSOR_ONLY" -eq 0 && ! -r "$TABLET_MODE_FILE" ]]; then
    die "no existe $TABLET_MODE_FILE; usa --sensor-only para este hardware"
  fi

  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
  local lock_path="$runtime_dir/autorotate-x1-yoga-${UID}.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "ya existe otra instancia de autorrotación"

  local sensor_fifo
  local line=""
  local sensor_orientation="normal"
  local current_mode
  local desired_orientation
  local desired_mode
  local orientation_changed=0

  SENSOR_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autorotate-x1-yoga.XXXXXX")"
  sensor_fifo="$SENSOR_DIR/events"
  mkfifo "$sensor_fifo"
  monitor-sensor --accel > "$sensor_fifo" 2>&1 &
  SENSOR_PID="$!"
  exec 8< "$sensor_fifo"
  rm -f "$sensor_fifo"
  trap cleanup_sensor EXIT
  info "autorrotación activa; sensor-only=$SENSOR_ONLY, disable-inputs=$DISABLE_INPUTS"

  while kill -0 "$SENSOR_PID" 2>/dev/null; do
    if IFS= read -r -t 0.5 line <&8; then
      case "$line" in
        *"normal"*) sensor_orientation="normal"; orientation_changed=1 ;;
        *"right-up"*) sensor_orientation="right"; orientation_changed=1 ;;
        *"bottom-up"*) sensor_orientation="inverted"; orientation_changed=1 ;;
        *"left-up"*) sensor_orientation="left"; orientation_changed=1 ;;
      esac
    fi

    current_mode="$(tablet_mode)"
    if [[ "$SENSOR_ONLY" -eq 1 ]]; then
      desired_mode=1
      desired_orientation="$sensor_orientation"
    elif [[ "$current_mode" == "1" ]]; then
      desired_mode=1
      desired_orientation="$sensor_orientation"
    elif [[ "$current_mode" == "0" ]]; then
      desired_mode=0
      desired_orientation="normal"
    else
      warn "estado de modo tablet desconocido; no se cambia la orientación"
      continue
    fi

    if [[ "$desired_mode" != "$LAST_TABLET_MODE" ]]; then
      apply_orientation "$desired_orientation" || true
      set_tablet_input_state "$desired_mode"
      LAST_TABLET_MODE="$desired_mode"
      orientation_changed=0
    elif [[ "$orientation_changed" -eq 1 ]] &&
      [[ "$desired_orientation" != "$LAST_ORIENTATION" ]]; then
      apply_orientation "$desired_orientation" || true
      set_tablet_input_state "$desired_mode"
      LAST_TABLET_MODE="$desired_mode"
      orientation_changed=0
    fi
  done

  notify_failure "monitor-sensor terminó; la autorrotación se detuvo"
}

main() {
  parse_args "$@"
  require_linux
  case "$MODE" in
    check) check ;;
    once)
      check_session || die "--once requiere DISPLAY en una sesión Xorg local"
      apply_orientation "$ORIENTATION"
      ;;
    daemon) daemon ;;
  esac
}

main "$@"
