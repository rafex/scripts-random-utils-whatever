#!/usr/bin/env bash
# eww_actions_linux.sh v1.0.0
# Datos no sensibles y acciones permitidas para los widgets EWW de Rafex.
set -Eeuo pipefail
umask 077
export LC_ALL=C

ACTION=''
VALUE=''
BIN_DIR="$HOME/.local/bin"

info() { printf '%s\n' "$*"; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  eww_actions_linux.sh --value time|date|calendar|media|notifications|devices|battery|printers|scanner|theme
  eww_actions_linux.sh --action NOMBRE
  eww_actions_linux.sh --status

Las acciones son una lista cerrada usada por EWW; no se aceptan comandos libres.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --action)
        (($# >= 2)) || die '--action requiere un nombre'
        ACTION="$2"
        shift 2
        ;;
      --value)
        (($# >= 2)) || die '--value requiere un nombre'
        VALUE="$2"
        shift 2
        ;;
      --status) ACTION='status'; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
  [[ -n "$ACTION" || -n "$VALUE" ]] || die 'indica --value, --action o --status'
  [[ -z "$ACTION" || -z "$VALUE" ]] || die 'no combines --value con --action'
}

command_available() { command -v "$1" >/dev/null 2>&1; }

run_helper() {
  local helper="$1"
  shift
  [[ -x "$BIN_DIR/$helper" ]] || die "falta el helper $BIN_DIR/$helper; ejecuta just install-eww --apply"
  "$BIN_DIR/$helper" "$@"
}

notify() {
  local title="$1" body="$2"
  if command_available notify-send; then
    notify-send --expire-time=1800 "$title" "$body" >/dev/null 2>&1 || true
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

value_time() { date '+%H:%M'; }

value_date() {
  command_available python3 || { info 'N/D'; return 0; }
  python3 - <<'PY'
from datetime import datetime

now = datetime.now()
days = ('lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo')
months = ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
          'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre')
print(f'{days[now.weekday()]} {now.day} de {months[now.month - 1]} de {now.year}')
print(f'Semana {now.isocalendar().week}')
PY
}

value_calendar() {
  command_available python3 || { info 'N/D'; return 0; }
  python3 - <<'PY'
import calendar
from datetime import date

now = date.today()
months = ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
          'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre')
days = ('lu', 'ma', 'mi', 'ju', 'vi', 'sá', 'do')
print(f'{months[now.month - 1].capitalize()} {now.year}')
print(' '.join(f'{day:>2}' for day in days))
for week in calendar.monthcalendar(now.year, now.month):
    print(' '.join(f'{day:>2}' if day else '  ' for day in week))
PY
}

value_media() {
  if ! command_available playerctl; then
    info 'N/D'
    return 0
  fi
  local media
  media="$(playerctl -a metadata --format '{{status}}\t{{title}}\t{{artist}}' 2>/dev/null | head -n 1 || true)"
  [[ -n "$media" ]] || { info 'N/D'; return 0; }
  awk -F '\t' '
    function clean(value) { gsub(/[\r\n]/, " ", value); return value }
    {
      state = $1
      if (state == "Playing") state = "▶ reproduciendo"
      else if (state == "Paused") state = "Ⅱ pausado"
      else if (state == "Stopped") state = "■ detenido"
      title = clean($2); artist = clean($3)
      if (title == "") title = "N/D"
      if (artist == "") artist = "N/D"
      printf "%s\n%s\n%s\n", state, title, artist
    }
  ' <<<"$media"
}

value_notifications() {
  if command_available dunstctl; then
    printf 'Pendientes: %s\n' "$(dunstctl count waiting 2>/dev/null || printf 'N/D')"
  else
    info 'Pendientes: N/D'
  fi
}

value_devices() {
  local usb_count='0' bluetooth_count='0'
  if command_available findmnt; then
    usb_count="$(findmnt -rn -o TARGET 2>/dev/null | awk -v a="/run/media/$USER/" -v b="/media/$USER/" 'index($0, a) == 1 || index($0, b) == 1 {n++} END {print n+0}' || printf '0')"
  fi
  if command_available bluetoothctl; then
    bluetooth_count="$(bluetoothctl devices Connected 2>/dev/null | wc -l | tr -d ' ' || printf '0')"
  fi
  printf 'USB montados: %s\nBluetooth conectados: %s\n' "$usb_count" "$bluetooth_count"
}

value_battery() {
  command_available upower || { info 'Batería: N/D'; return 0; }
  local battery_path details state time_left health line_power line_path
  battery_path="$(upower -e 2>/dev/null | awk '/battery/ {print; exit}' || true)"
  [[ -n "$battery_path" ]] || { info 'Batería: N/D'; return 0; }
  details="$(upower -i "$battery_path" 2>/dev/null || true)"
  state="$(awk -F: '/^[[:space:]]*state:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' <<<"$details")"
  time_left="$(awk -F: '/time to empty:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' <<<"$details")"
  health="$(awk -F: '/capacity:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' <<<"$details")"
  line_path="$(upower -e 2>/dev/null | awk '/line_power/ {print; exit}' || true)"
  line_power='N/D'
  [[ -n "$line_path" ]] && line_power="$(upower -i "$line_path" 2>/dev/null | awk -F: '/online:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' || true)"
  [[ -n "$state" ]] || state='N/D'
  [[ -n "$time_left" ]] || time_left='N/D'
  [[ -n "$health" ]] || health='N/D'
  [[ -n "$line_power" ]] || line_power='N/D'
  printf 'Estado: %s\nTiempo: %s\nSalud: %s\nAC: %s\n' "$state" "$time_left" "$health" "$line_power"
}

value_printers() {
  local epson='N/D' xerox='N/D'
  if command_available lpstat; then
    lpstat -p Epson_XP_241 >/dev/null 2>&1 && epson='lista'
    lpstat -p Xerox_Phaser_3020 >/dev/null 2>&1 && xerox='lista'
  fi
  printf 'Epson XP-241: %s\nXerox Phaser 3020: %s\n' "$epson" "$xerox"
}

value_scanner() {
  if ! command_available scanimage; then
    info 'Escáner Epson: N/D'
    return 0
  fi
  if command_available timeout && timeout 5 scanimage -L 2>/dev/null | grep -qi epson; then
    info 'Escáner Epson: disponible'
  else
    info 'Escáner Epson: N/D'
  fi
}

value_theme() {
  local theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/theme"
  if [[ -r "$theme_file" ]]; then
    head -n 1 "$theme_file"
  else
    info 'nord'
  fi
}

run_player_action() {
  local action="$1"
  if command_available playerctl; then
    playerctl "$action" || notify 'Multimedia' 'No hay reproductor MPRIS'
  else
    notify 'Multimedia' 'playerctl no está instalado'
  fi
}

run_action() {
  local action="$1" state
  case "$action" in
    screen-down) run_helper brightness-notify.sh down ;;
    screen-up) run_helper brightness-notify.sh up ;;
    kbd-down) run_helper kbd-brightness-notify.sh down ;;
    kbd-up) run_helper kbd-brightness-notify.sh up ;;
    volume-down) run_helper volume-notify.sh down ;;
    volume-up) run_helper volume-notify.sh up ;;
    volume-mute) run_helper volume-notify.sh mute ;;
    microphone-toggle) run_helper microphone-notify.sh toggle ;;
    wifi-toggle) run_helper wifi-toggle.sh toggle ;;
    wwan-toggle)
      command_available nmcli || die 'falta nmcli'
      state="$(nmcli -t -f WWAN radio 2>/dev/null | tail -n 1)"
      if [[ "$state" == enabled ]]; then nmcli radio wwan off; notify 'WWAN' 'Desactivada'; else nmcli radio wwan on; notify 'WWAN' 'Activada'; fi
      ;;
    bluetooth-toggle)
      command_available bluetoothctl || die 'falta bluetoothctl'
      state="$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')"
      if [[ "$state" == yes ]]; then bluetoothctl power off >/dev/null; notify 'Bluetooth' 'Desactivado'; else bluetoothctl power on >/dev/null; notify 'Bluetooth' 'Activado'; fi
      ;;
    media-prev) run_player_action previous ;;
    media-play) run_player_action play-pause ;;
    media-next) run_player_action next ;;
    notifications-history)
      if ! command_available alacritty || ! command_available dunstctl; then
        die 'se requieren alacritty y dunstctl'
      fi
      alacritty -e sh -c 'dunstctl history; printf "\nPulsa Enter para cerrar..."; read -r' &
      ;;
    control-panel) run_helper rafex-control-panel.sh ;;
    screenshot) run_helper screenshot.sh --full ;;
    lock) run_helper lock-screen.sh --mode image ;;
    logout|suspend|hibernate|reboot|poweroff) run_helper desktop-settings-menu.sh "$action" ;;
    *) die "acción no permitida: $action" ;;
  esac
}

show_status() {
  printf '═══ Acciones EWW Rafex ═══\n'
  printf 'ejecución=usuario-normal\nacciones=allowlist\nsecretos=no-se-muestran\n'
  for tool in playerctl nmcli bluetoothctl lpstat scanimage upower dunstctl; do
    command_available "$tool" && printf '✓ %s disponible\n' "$tool" || printf '⚠ %s no disponible\n' "$tool"
  done
}

main() {
  parse_args "$@"
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal'
  if [[ "$ACTION" == status ]]; then
    show_status
  elif [[ -n "$VALUE" ]]; then
    case "$VALUE" in
      time) value_time ;;
      date) value_date ;;
      calendar) value_calendar ;;
      media) value_media ;;
      notifications) value_notifications ;;
      devices) value_devices ;;
      battery) value_battery ;;
      printers) value_printers ;;
      scanner) value_scanner ;;
      theme) value_theme ;;
      *) die "valor no permitido: $VALUE" ;;
    esac
  else
    run_action "$ACTION"
  fi
}

main "$@"
