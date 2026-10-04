#!/usr/bin/env bash
# shellcheck shell=bash
# Centro de control común para sesiones i3 y Openbox en Xorg.
set -Eeuo pipefail
umask 077

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_FILE="$STATE_HOME/rafex/ratmenu-actions.jsonl"
ACTION_SOURCE="${RAFEX_ACTION_SOURCE:-desktop-settings-menu}"
ACTION_OUTPUT=''
ACTION_EXIT_CODE=0

command -v rofi >/dev/null 2>&1 || {
  echo "No se encontró rofi." >&2
  exit 1
}

section="${1:-all}"
direct_action=''
case "$section" in
  all)
    menu_prompt='Centro de control'
    menu_items=(
      'Red — NetworkManager'
      'Software — Synaptic'
      'Wi-Fi — alternar'
      'Modo avión — alternar radios'
      'Audio — pavucontrol'
      'Tema visual — alternar'
      'Tema — Nord'
      'Tema — Paper'
      'Tema — Everforest'
      'Tema — Dracula'
      'Micrófono — alternar mute'
      'Pantallas — arandr'
      'Proyector — siguiente modo'
      'Bluetooth — blueman-manager'
      'Cámara — guvcview'
      'Pluma — diagnóstico Wacom'
      'Archivos — explorador'
      'Navegador — predeterminado'
      'Configuración de ventanas'
      'Configuración tint2'
      'Terminal — Alacritty/tmux'
      'Estado hardware — btop'
      'Picom — alternar'
      'Bloquear sesión'
      'Cerrar sesión'
      'Suspender equipo'
      'Hibernar equipo'
      'Reiniciar equipo'
      'Apagar equipo'
    )
    ;;
  power)
    menu_prompt='Energía y sesión'
    menu_items=('Bloquear sesión' 'Cerrar sesión' 'Suspender equipo' 'Hibernar equipo' 'Reiniciar equipo' 'Apagar equipo')
    ;;
  logout|suspend|hibernate|reboot|poweroff)
    direct_action="$section"
    ;;
  -h|--help)
    echo "Uso: $0 [all|power|logout|suspend|hibernate|reboot|poweroff]"
    exit 0
    ;;
  *)
    echo "Uso: $0 [all|power|logout|suspend|hibernate|reboot|poweroff]" >&2
    exit 1
    ;;
esac

notify_error() {
  local message="$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Acción no disponible" "$message"
  else
    echo "$message" >&2
  fi
}

record_action() {
  local action="$1" result="$2" exit_code="$3" output="$4" diagnostics="$5"
  shift 5

  if ! printf '%s' "$output" | python3 -c '
import datetime
import json
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
record = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "source": sys.argv[2],
    "action": sys.argv[3],
    "result": sys.argv[4],
    "exit_code": None if sys.argv[5] == "" else int(sys.argv[5]),
    "command": sys.argv[7:],
    "output": sys.stdin.read(),
    "diagnostics": sys.argv[6],
}
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(path.parent, 0o700)
with path.open("a", encoding="utf-8") as handle:
    json.dump(record, handle, ensure_ascii=False)
    handle.write("\n")
os.chmod(path, 0o600)
' "$LOG_FILE" "$ACTION_SOURCE" "$action" "$result" "$exit_code" "$diagnostics" "$@"; then
    printf 'No se pudo escribir el log de acciones: %s\n' "$LOG_FILE" >&2
    return 1
  fi
}

collect_power_diagnostics() {
  local capability_suspend='no disponible' capability_hibernate='no disponible'
  local inhibitors='no disponible' session='no disponible'
  local power_states='no disponible' mem_sleep='no disponible'

  if command -v busctl >/dev/null 2>&1; then
    capability_suspend="$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend 2>&1 || true)"
    capability_hibernate="$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>&1 || true)"
  fi
  if command -v systemd-inhibit >/dev/null 2>&1; then
    inhibitors="$(systemd-inhibit --list --no-pager 2>&1 || true)"
  fi
  if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
    session="$(loginctl show-session "$XDG_SESSION_ID" -p Active -p State -p Type -p Remote -p Seat 2>&1 || true)"
  fi
  [[ -r /sys/power/state ]] && power_states="$(cat /sys/power/state 2>&1 || true)"
  [[ -r /sys/power/mem_sleep ]] && mem_sleep="$(cat /sys/power/mem_sleep 2>&1 || true)"

  printf 'CanSuspend: %s\nCanHibernate: %s\nSession:\n%s\nInhibitors:\n%s\n/sys/power/state: %s\n/sys/power/mem_sleep: %s' \
    "$capability_suspend" "$capability_hibernate" "$session" "$inhibitors" "$power_states" "$mem_sleep"
}

run_logged_command() {
  local action="$1"
  shift
  local result diagnostics=''

  if ACTION_OUTPUT="$("$@" 2>&1)"; then
    ACTION_EXIT_CODE=0
    result=success
  else
    ACTION_EXIT_CODE=$?
    result=failure
    case "$action" in
      suspend|hibernate) diagnostics="$(collect_power_diagnostics)" ;;
    esac
  fi

  record_action "$action" "$result" "$ACTION_EXIT_CODE" "$ACTION_OUTPUT" "$diagnostics" "$@" || true
  return "$ACTION_EXIT_CODE"
}

notify_action_failure() {
  local label="$1"
  local detail="${ACTION_OUTPUT//$'\n'/ }"
  [[ -n "$detail" ]] || detail='el comando no devolvió detalles'
  detail="${detail:0:400}"
  notify_error "$label (código ${ACTION_EXIT_CODE}): ${detail}. Registro: ${LOG_FILE}"
}

confirm() {
  local action="$1"
  local answer
  answer="$(printf 'Cancelar\nConfirmar' | rofi -dmenu -i -p "$action" || true)"
  [[ "$answer" == Confirmar ]]
}

run_action() {
  local action="$1"
  case "$action" in
    lock)
      loginctl lock-session
      ;;
    logout)
      if ! confirm '¿Cerrar sesión?'; then
        record_action logout cancelled '' '' '' || true
        return 0
      fi
      if [[ -n "${XDG_SESSION_ID:-}" ]] && loginctl show-session "$XDG_SESSION_ID" >/dev/null 2>&1 \
        && run_logged_command logout loginctl terminate-session "$XDG_SESSION_ID"; then
        return 0
      fi
      if command -v i3-msg >/dev/null 2>&1 && run_logged_command logout i3-msg exit; then
        return 0
      fi
      if command -v openbox >/dev/null 2>&1 && run_logged_command logout openbox --exit; then
        return 0
      fi
      if (( ACTION_EXIT_CODE != 0 )) || [[ -n "$ACTION_OUTPUT" ]]; then
        notify_action_failure 'No se pudo terminar la sesión gráfica actual'
      else
        notify_error 'No se pudo terminar la sesión gráfica actual.'
      fi
      return 1
      ;;
    suspend)
      if ! confirm '¿Suspender equipo?'; then
        record_action suspend cancelled '' '' '' || true
        return 0
      fi
      if ! run_logged_command suspend loginctl suspend; then
        notify_action_failure 'No se pudo suspender el equipo'
      fi
      ;;
    hibernate)
      if ! confirm '¿Hibernar equipo?'; then
        record_action hibernate cancelled '' '' '' || true
        return 0
      fi
      local capability
      local capability_status
      if capability="$(loginctl can-hibernate 2>&1)"; then
        capability_status=0
      else
        capability_status=$?
        ACTION_OUTPUT="$capability"
        ACTION_EXIT_CODE="$capability_status"
        local diagnostics
        diagnostics="$(collect_power_diagnostics)"
        record_action hibernate unavailable "$ACTION_EXIT_CODE" "$ACTION_OUTPUT" "$diagnostics" loginctl can-hibernate || true
        notify_action_failure 'No se pudo comprobar si la hibernación está disponible'
        return 0
      fi
      if [[ "$capability" != yes && "$capability" != challenge ]]; then
        ACTION_OUTPUT="${capability:-logind informó que no está disponible}"
        ACTION_EXIT_CODE=0
        local diagnostics
        diagnostics="$(collect_power_diagnostics)"
        record_action hibernate unavailable 0 "$ACTION_OUTPUT" "$diagnostics" loginctl can-hibernate || true
        notify_error "La hibernación no está disponible: ${ACTION_OUTPUT}. Registro: ${LOG_FILE}"
        return 0
      fi
      if ! run_logged_command hibernate loginctl hibernate; then
        notify_action_failure 'No se pudo hibernar el equipo'
      fi
      ;;
    reboot)
      if ! confirm '¿Reiniciar equipo?'; then
        record_action reboot cancelled '' '' '' || true
        return 0
      fi
      if ! run_logged_command reboot systemctl reboot; then
        notify_action_failure 'No se pudo reiniciar el equipo'
      fi
      ;;
    poweroff)
      if ! confirm '¿Apagar equipo?'; then
        record_action poweroff cancelled '' '' '' || true
        return 0
      fi
      if ! run_logged_command poweroff systemctl poweroff; then
        notify_action_failure 'No se pudo apagar el equipo'
      fi
      ;;
    *)
      notify_error "Acción desconocida: $action"
      return 1
      ;;
  esac
}

if [[ -n "$direct_action" ]]; then
  run_action "$direct_action"
  exit $?
fi

choice="$(printf '%s\n' "${menu_items[@]}" | rofi -dmenu -i -p "$menu_prompt" || true)"
case "$choice" in
  'Red — NetworkManager') exec nm-connection-editor ;;
  'Software — Synaptic') exec synaptic-pkexec ;;
  'Wi-Fi — alternar') exec "$HOME/.local/bin/wifi-toggle.sh" toggle ;;
  'Modo avión — alternar radios') exec "$HOME/.local/bin/flight-mode-toggle.sh" toggle ;;
  'Audio — pavucontrol') exec pavucontrol ;;
  'Tema visual — alternar') exec "$HOME/.local/bin/theme-toggle.sh" --toggle ;;
  'Tema — Nord') exec "$HOME/.local/bin/theme-toggle.sh" --set nord ;;
  'Tema — Paper') exec "$HOME/.local/bin/theme-toggle.sh" --set paper ;;
  'Tema — Everforest') exec "$HOME/.local/bin/theme-toggle.sh" --set everforest ;;
  'Tema — Dracula') exec "$HOME/.local/bin/theme-toggle.sh" --set dracula ;;
  'Micrófono — alternar mute') exec "$HOME/.local/bin/microphone-notify.sh" toggle ;;
  'Pantallas — arandr') exec arandr ;;
  'Proyector — siguiente modo') exec "$HOME/.local/bin/screen-projector.sh" --apply --mode next ;;
  'Bluetooth — blueman-manager') exec blueman-manager ;;
  'Cámara — guvcview') exec guvcview ;;
  'Pluma — diagnóstico Wacom') exec "$HOME/.local/bin/test-wacom-pen.sh" --check ;;
  'Archivos — explorador') exec xdg-open "$HOME" ;;
  'Navegador — predeterminado') exec "$HOME/.local/bin/rofi-search.sh" browser ;;
  'Configuración de ventanas')
    if [[ -f "$HOME/.config/openbox/rc.xml" ]]; then
      exec alacritty -e nvim "$HOME/.config/openbox/rc.xml"
    fi
    exec alacritty -e nvim "$HOME/.config/i3/config"
    ;;
  'Configuración tint2') exec alacritty -e nvim "$HOME/.config/tint2/tint2rc" ;;
  'Terminal — Alacritty/tmux') exec alacritty ;;
  'Estado hardware — btop') exec alacritty -e btop ;;
  'Picom — alternar') exec "$HOME/.local/bin/picom-toggle.sh" ;;
  'Bloquear sesión') run_action lock ;;
  'Cerrar sesión') run_action logout ;;
  'Suspender equipo') run_action suspend ;;
  'Hibernar equipo') run_action hibernate ;;
  'Reiniciar equipo') run_action reboot ;;
  'Apagar equipo') run_action poweroff ;;
  *) exit 0 ;;
esac
