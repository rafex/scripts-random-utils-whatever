#!/usr/bin/env bash
# i3_hotkey_helper_linux.sh v1.0.0
# Muestra atajos de i3 y permite ejecutar su acción desde Rofi.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  i3_hotkey_helper_linux.sh
  i3_hotkey_helper_linux.sh --list
  i3_hotkey_helper_linux.sh --help

Sin argumentos abre el menú Rofi. Al seleccionar una entrada, ejecuta la acción.
EOF
}

labels=(
  'Win+Enter — Abrir terminal Alacritty'
  'Win+Space — Abrir Ulauncher'
  'Win+Tab — Selector de ventanas'
  'Win+Shift+Tab — Enfocar la siguiente ventana'
  'Win+Shift+E — Ejecutar un comando con Rofi Run'
  'Win+Shift+E — xkill: cerrar una ventana con un clic'
  'Win+Shift+E — killall firefox: cerrar Firefox'
  'Win+Shift+V — Abrir el historial del portapapeles'
  'Win+Shift+L — Bloquear la sesión'
  'Win+F9 — Abrir el menú de laptop'
  'Win+Ctrl+P — Abrir el panel de control Rafex'
  'Win+Shift+T — Cambiar el tema'
  'Win+Shift+B — Buscar en la web'
  'Win+Shift+C — Recargar la configuración de i3'
  'Win+Shift+R — Reiniciar i3'
  'Win+Shift+P — Alternar Picom'
  'Win+Ctrl+W — Alternar panel de widgets'
  'Win+Shift+S — Alternar el salvapantallas'
  'Win+P — Captura de pantalla completa'
  'Print — Captura de pantalla completa'
  'Shift+Print — Captura de una selección'
  'Ctrl+Print — Captura de la ventana activa'
  'Win+Left — Enfocar ventana a la izquierda'
  'Win+Down — Enfocar ventana abajo'
  'Win+Up — Enfocar ventana arriba'
  'Win+Right — Enfocar ventana a la derecha'
  'Win+Shift+Left — Mover ventana a la izquierda'
  'Win+Shift+Down — Mover ventana abajo'
  'Win+Shift+Up — Mover ventana arriba'
  'Win+Shift+Right — Mover ventana a la derecha'
  'Win+R — Entrar al modo de redimensionamiento'
  'Win+F — Alternar pantalla completa'
  'Win+Shift+F — Alternar ventana flotante y centrarla'
  'Win+Q — Cerrar la ventana activa'
  'Win+B — Dividir horizontalmente'
  'Win+V — Dividir verticalmente'
  'Win+E — Alternar división'
  'Win+S — Diseño apilado'
  'Win+W — Diseño de pestañas'
  'Win+A — Enfocar contenedor padre'
  'Win+D — Alternar foco entre contenedor y padre'
  'Win+Shift+Minus — Enviar ventana al scratchpad'
  'Win+Minus — Mostrar u ocultar scratchpad'
  'XF86MonBrightnessUp — Subir brillo de pantalla'
  'XF86MonBrightnessDown — Bajar brillo de pantalla'
  'XF86AudioRaiseVolume — Subir volumen'
  'XF86AudioLowerVolume — Bajar volumen'
  'XF86AudioMute — Alternar silencio'
  'XF86KbdBrightnessUp — Subir brillo del teclado'
  'XF86KbdBrightnessDown — Bajar brillo del teclado'
  'XF86LaunchA — Alias para bajar brillo del teclado'
  'XF86Explorer — Alias para subir brillo del teclado'
  'XF86LaunchB — Mostrar u ocultar scratchpad'
  'XF86AudioMicMute — Alternar micrófono'
  'XF86WLAN — Alternar Wi-Fi'
  'XF86RFKill — Alternar modo avión'
  'XF86Display — Cambiar modo de pantalla'
  'XF86WakeUp — Abrir menú de energía'
  'XF86Tools — Abrir el menú de laptop'
)

actions=(
  'i3-msg exec alacritty'
  'i3-msg exec ulauncher-toggle'
  'rofi -show window -show-icons'
  'i3-msg focus next'
  'rofi -show run'
  'xkill'
  'killall firefox'
  '$HOME/.local/bin/clipboard-menu.sh --show'
  '$HOME/.local/bin/lock-screen.sh --mode image'
  '$HOME/.local/bin/rafex-ratmenu.sh'
  '$HOME/.local/bin/rafex-control-panel.sh'
  '$HOME/.local/bin/theme-toggle.sh --toggle'
  '$HOME/.local/bin/rafex-browser-search.sh'
  'i3-msg reload'
  'i3-msg restart'
  '$HOME/.local/bin/picom-toggle.sh --toggle'
  '$HOME/.local/bin/eww-widgets.sh --toggle dashboard'
  '$HOME/.local/bin/screensaver-toggle toggle'
  '$HOME/.local/bin/screenshot.sh --full'
  '$HOME/.local/bin/screenshot.sh --full'
  '$HOME/.local/bin/screenshot.sh --select'
  '$HOME/.local/bin/screenshot.sh --window'
  'i3-msg focus left'
  'i3-msg focus down'
  'i3-msg focus up'
  'i3-msg focus right'
  'i3-msg move left'
  'i3-msg move down'
  'i3-msg move up'
  'i3-msg move right'
  'i3-msg mode resize'
  'i3-msg fullscreen toggle'
  'i3-msg floating toggle; i3-msg move position center'
  'i3-msg kill'
  'i3-msg split h'
  'i3-msg split v'
  'i3-msg layout toggle split'
  'i3-msg layout stacking'
  'i3-msg layout tabbed'
  'i3-msg focus parent'
  'i3-msg focus mode_toggle'
  'i3-msg move scratchpad'
  'i3-msg scratchpad show'
  '$HOME/.local/bin/brightness-notify.sh up'
  '$HOME/.local/bin/brightness-notify.sh down'
  '$HOME/.local/bin/volume-notify.sh up'
  '$HOME/.local/bin/volume-notify.sh down'
  '$HOME/.local/bin/volume-notify.sh mute'
  '$HOME/.local/bin/kbd-brightness-notify.sh up'
  '$HOME/.local/bin/kbd-brightness-notify.sh down'
  '$HOME/.local/bin/kbd-brightness-notify.sh down'
  '$HOME/.local/bin/kbd-brightness-notify.sh up'
  'i3-msg scratchpad show'
  '$HOME/.local/bin/microphone-notify.sh toggle'
  '$HOME/.local/bin/wifi-toggle.sh toggle'
  '$HOME/.local/bin/flight-mode-toggle.sh toggle'
  '$HOME/.local/bin/screen-projector.sh --apply --mode next'
  '$HOME/.local/bin/i3-settings-menu.sh power'
  '$HOME/.local/bin/rafex-ratmenu.sh'
)

for workspace in {1..10}; do
  key="$workspace"
  (( workspace == 10 )) && key=0
  labels+=("Win+$key — Cambiar a workspace $workspace")
  actions+=("i3-msg workspace number $workspace")
  labels+=("Win+Shift+$key — Mover ventana a workspace $workspace")
  actions+=("i3-msg move container to workspace number $workspace")
done

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --list)
    for index in "${!labels[@]}"; do
      printf '%-54s %s\n' "${labels[$index]}" "${actions[$index]}"
    done
    exit 0
    ;;
  '')
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

command -v rofi >/dev/null 2>&1 || {
  echo 'No se encontró rofi.' >&2
  exit 1
}

selection="$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -no-custom \
  -p 'Atajos i3' -mesg 'Selecciona una acción para ejecutarla')"
[[ -n "$selection" ]] || exit 0

for index in "${!labels[@]}"; do
  if [[ "${labels[$index]}" == "$selection" ]]; then
    bash -c "${actions[$index]}"
    exit $?
  fi
done

exit 0
