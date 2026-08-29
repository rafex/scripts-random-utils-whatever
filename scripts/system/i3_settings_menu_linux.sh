#!/usr/bin/env bash
# shellcheck shell=bash
# Centro de control Rofi para una sesión i3 sin escritorio completo.
set -Eeuo pipefail

command -v rofi >/dev/null 2>&1 || { echo "No se encontró rofi." >&2; exit 1; }

section="${1:-all}"
case "$section" in
  all)
    menu_prompt='Centro de control'
    menu_items=(
      'Red — NetworkManager'
      'Software — Synaptic'
      'Wi‑Fi — alternar'
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
      'Configuración i3 — Neovim'
      'Terminal — Alacritty/tmux'
      'Estado hardware — btop'
      'Bloquear sesión'
      'Suspender equipo'
      'Reiniciar equipo'
      'Apagar equipo'
    )
    ;;
  power)
    menu_prompt='Energía y sesión'
    menu_items=('Bloquear sesión' 'Suspender equipo' 'Reiniciar equipo' 'Apagar equipo')
    ;;
  -h|--help)
    echo "Uso: $0 [all|power]"
    exit 0
    ;;
  *)
    echo "Uso: $0 [all|power]" >&2
    exit 1
    ;;
esac

choice="$(printf '%s\n' "${menu_items[@]}" | rofi -dmenu -i -p "$menu_prompt")"

confirm() {
  local action="$1"
  [[ "$(printf 'Cancelar\nConfirmar' | rofi -dmenu -i -p "$action")" == Confirmar ]]
}

case "$choice" in
  'Red — NetworkManager') exec nm-connection-editor ;;
  'Software — Synaptic') exec synaptic-pkexec ;;
  'Wi‑Fi — alternar') exec "$HOME/.local/bin/wifi-toggle.sh" toggle ;;
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
  'Configuración i3 — Neovim') exec alacritty -e nvim "$HOME/.config/i3/config" ;;
  'Terminal — Alacritty/tmux') exec alacritty ;;
  'Estado hardware — btop') exec alacritty -e btop ;;
  'Bloquear sesión') exec loginctl lock-session ;;
  'Suspender equipo') confirm "¿Suspender equipo?" && exec systemctl suspend ;;
  'Reiniciar equipo') confirm "¿Reiniciar equipo?" && exec systemctl reboot ;;
  'Apagar equipo') confirm "¿Apagar equipo?" && exec systemctl poweroff ;;
  *) exit 0 ;;
esac
