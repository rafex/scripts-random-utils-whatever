#!/usr/bin/env bash
# rafex_ratmenu_linux.sh v1.2.0
# Menú ligero de acciones del perfil ThinkPad usando ratmenu.
# shellcheck disable=SC2016
set -Eeuo pipefail
umask 077

export LC_ALL=C

managed_menu_running() {
  local uid pid process cmdline
  uid="$(id -u)"
  for process in ratmenu 9menu; do
    while read -r pid; do
      [[ -n "$pid" && "$pid" != "$$" ]] || continue
      [[ -r "/proc/$pid/cmdline" ]] || continue
      cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
      case "$cmdline" in
        *"Rafex ThinkPad"*) return 0 ;;
      esac
    done < <(pgrep -u "$uid" -x "$process" 2>/dev/null || true)
  done
  return 1
}

runtime_dir="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/rafex}"
mkdir -p -- "$runtime_dir"
chmod 700 -- "$runtime_dir" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$runtime_dir/ratmenu.lock"
  if ! flock -n 9; then
    printf 'ratmenu de Rafex ya está en proceso de apertura; no se duplica.\n'
    exit 0
  fi
fi

if managed_menu_running; then
  printf 'ratmenu de Rafex ya está abierto; no se duplica.\n'
  exit 0
fi

if ! command -v ratmenu >/dev/null 2>&1; then
  fallback_menu="${XDG_CONFIG_HOME:-$HOME/.config}/9menu/laptop.menu"
  if command -v 9menu >/dev/null 2>&1 && [[ -s "$fallback_menu" ]]; then
    exec 9menu -popup -label 'Rafex ThinkPad (fallback)' -file "$fallback_menu"
  fi
  printf '✗ ERROR: ratmenu no está instalado y no hay fallback 9menu disponible.\n' >&2
  exit 1
fi

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/rafex/theme"
theme="nord"
[[ -r "$theme_file" ]] && theme="$(head -n 1 "$theme_file")"

case "$theme" in
  paper) fg='#263238'; bg='#eceff1';;
  everforest) fg='#d3c6aa'; bg='#2d353b';;
  dracula) fg='#f8f8f2'; bg='#282a36';;
  *) fg='#e5e9f0'; bg='#2e3440';;
esac

menu=(
  'Terminal y tmux' 'alacritty'
  'Terminal RXVT y tmux' 'urxvt -e "$HOME/.local/bin/start-thinkpad-tmux"'
  'Aplicaciones' 'rofi -show drun -show-icons'
  'Navegador' 'firefox'
  'Archivos' 'thunar'
  'Panel de control Rafex' '"$HOME/.local/bin/rafex-control-panel.sh"'
  'Audio' 'pavucontrol'
  'Red' 'nm-connection-editor'
  'Wi-Fi' '"$HOME/.local/bin/wifi-toggle.sh" toggle'
  'Modo avion' '"$HOME/.local/bin/flight-mode-toggle.sh" toggle'
  'Bluetooth' 'blueman-manager'
  'Microfono' '"$HOME/.local/bin/microphone-notify.sh" toggle'
  'Pantallas' 'arandr'
  'Proyector' '"$HOME/.local/bin/screen-projector.sh" --apply --mode next'
  'Camara' 'guvcview'
  'Pluma Wacom' '"$HOME/.local/bin/test-wacom-pen.sh" --check'
  'Captura completa' '"$HOME/.local/bin/screenshot.sh" --full'
  'Captura de area' '"$HOME/.local/bin/screenshot.sh" --select'
  'Captura de ventana' '"$HOME/.local/bin/screenshot.sh" --window'
  'Portapapeles CopyQ' '"$HOME/.local/bin/clipboard-menu.sh" --show'
  'Tema claro/oscuro' '"$HOME/.local/bin/theme-toggle.sh" --toggle'
  'Estado del sistema' 'alacritty -e btop'
  'Bloquear sesion' 'loginctl lock-session'
  'Energia' '"$HOME/.local/bin/desktop-settings-menu.sh" power'
  'Cerrar sesion' '"$HOME/.local/bin/desktop-settings-menu.sh" logout'
  'Suspender' '"$HOME/.local/bin/desktop-settings-menu.sh" suspend'
  'Hibernar' '"$HOME/.local/bin/desktop-settings-menu.sh" hibernate'
  'Reiniciar' '"$HOME/.local/bin/desktop-settings-menu.sh" reboot'
  'Apagar' '"$HOME/.local/bin/desktop-settings-menu.sh" poweroff'
  'Cerrar menu' 'exit'
)

# ratmenu usa XCreateFontSet (fuentes X11), no nombres Fontconfig/Xft.
# El alias fixed está disponible en el servidor X11 de la ThinkPad.
exec ratmenu -label 'Rafex ThinkPad' -font fixed \
  -fg "$fg" -bg "$bg" -style dreary -align left "${menu[@]}"
