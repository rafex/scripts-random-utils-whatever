#!/usr/bin/env bash
# shellcheck shell=bash
# Centro de control común para sesiones i3 y Openbox en Xorg.
set -Eeuo pipefail

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
      confirm '¿Cerrar sesión?' || return 0
      if [[ -n "${XDG_SESSION_ID:-}" ]] && loginctl show-session "$XDG_SESSION_ID" >/dev/null 2>&1 \
        && loginctl terminate-session "$XDG_SESSION_ID"; then
        return 0
      fi
      if command -v i3-msg >/dev/null 2>&1 && i3-msg exit >/dev/null 2>&1; then
        return 0
      fi
      if command -v openbox >/dev/null 2>&1 && openbox --exit >/dev/null 2>&1; then
        return 0
      fi
      notify_error 'No se pudo terminar la sesión gráfica actual.'
      return 1
      ;;
    suspend)
      confirm '¿Suspender equipo?' || return 0
      loginctl suspend || notify_error 'El sistema no permitió suspender el equipo.'
      ;;
    hibernate)
      confirm '¿Hibernar equipo?' || return 0
      local capability
      capability="$(loginctl can-hibernate 2>/dev/null || true)"
      if [[ "$capability" != yes && "$capability" != challenge ]]; then
        notify_error 'La hibernación no está disponible en este equipo.'
        return 0
      fi
      loginctl hibernate || notify_error 'El sistema no permitió hibernar el equipo.'
      ;;
    reboot)
      confirm '¿Reiniciar equipo?' || return 0
      systemctl reboot || notify_error 'El sistema no permitió reiniciar el equipo.'
      ;;
    poweroff)
      confirm '¿Apagar equipo?' || return 0
      systemctl poweroff || notify_error 'El sistema no permitió apagar el equipo.'
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
