# =============================================================================
# just/system.just — Tareas para scripts/system/
# =============================================================================

# Seleccionar y alternar las paletas de i3, tmux, Alacritty, Rofi y Dunst
# Uso: just theme-toggle --list | just theme-toggle --set nord | just theme-toggle --cycle
theme-toggle *args:
    bash scripts/system/theme_toggle_linux.sh {{args}}

# Materializar las paletas Paper, Nord, Everforest y Dracula
# Uso: just generate-terminal-themes --apply --theme all
generate-terminal-themes *args:
    bash scripts/system/generate_terminal_themes_linux.sh {{args}}

# Ajustar la posición de Dunst según el borde ocupado por i3bar
# Uso: just dunst-smart --check | just dunst-smart --start
dunst-smart *args:
    bash scripts/system/dunst_smart_start_linux.sh {{args}}

# Abrir el centro de control común para sesiones i3 y Openbox
# Uso: just desktop-settings-menu
desktop-settings-menu *args:
    bash scripts/system/desktop_settings_menu_linux.sh {{args}}

# Activar o desactivar picom sin sudo
# Uso: just picom-toggle --check | just picom-toggle --toggle
picom-toggle *args:
    bash scripts/system/picom_toggle_linux.sh {{args}}

# Usar Picom Debian con la configuración y shaders visuales del perfil Rafex
# Uso: just picom-debian --check|--plan|--apply|--status|--reload
picom-debian *args:
    bash scripts/system/picom_debian_linux.sh {{args}}

# Mostrar el estado compacto usado por tint2
# Uso: just tint2-status
tint2-status *args:
    bash scripts/system/tint2_status_linux.sh {{args}}

# Mostrar el estado seguro que consume el panel Conky
# Uso: just conky-status [--section network|power|temperature|audio|lab|security]
conky-status *args:
    bash scripts/system/conky_status_linux.sh {{args}}

# Escanear una memoria USB extraíble montada con ClamAV
# Uso: just scan-usb --path /run/media/$USER/NOMBRE_USB
scan-usb *args:
    bash scripts/system/scan_usb_clamav_linux.sh {{args}}

# Escanear un documento con el Epson XP-241 mediante SANE, sin sudo
# Uso: just scan-document --output ~/Documents/escaneo.png
scan-document *args:
    bash scripts/system/scan_document_linux.sh {{args}}

# Capturar pantalla completa, selección o ventana activa en X11
# Uso: just screenshot --select [--copy]
screenshot *args:
    bash scripts/system/screenshot_linux.sh {{args}}

# Abrir el historial visual de CopyQ desde la sesión gráfica
# Uso: just clipboard-menu --show | just clipboard-menu --status
clipboard-menu *args:
    bash scripts/system/clipboard_menu_linux.sh {{args}}

# Cifrar o descifrar un archivo con age sin exponer frases en argumentos
# Uso: just age-file --encrypt --input archivo --output archivo.age --recipient age1...
age-file *args:
    bash scripts/system/age_file_linux.sh {{args}}

# Abrir el menú ligero ratmenu del perfil ThinkPad
# Uso: just rafex-ratmenu
rafex-ratmenu *args:
    bash scripts/system/rafex_ratmenu_linux.sh {{args}}

# Abrir, cerrar, alternar o recargar la columna de widgets EWW sin reservar espacio
# Uso: just eww-widgets --open dashboard | --close dashboard | --toggle dashboard | --reload | --status
eww-widgets *args:
    bash scripts/system/eww_widgets_linux.sh {{args}}

# Bloquear la sesión con i3lock-color en modo imagen, sólido o desenfoque
# Uso: just lock-screen --mode image|solid|blur|--status
lock-screen *args:
    bash scripts/system/lock_screen_linux.sh {{args}}

# Abrir el panel GTK3 del perfil Rafex
# Uso: just rafex-control-panel
rafex-control-panel *args:
    python3 scripts/system/rafex_control_panel.py {{args}}

# Consultar teléfonos Android, instalar APKs explícitas o abrir scrcpy
# Uso: just android-tools --status|--devices|--install-apk --path app.apk|--scrcpy
android-tools *args:
    bash scripts/system/android_tools_linux.sh {{args}}

# Diagnosticar y leer Firefox OS por USB sin shell remoto ni modificaciones
# Uso: just firefoxos-tools --status|--devices|--list --remote /ruta|--pull --remote /ruta --target ~/Documents/firefoxos-exports
firefoxos-tools *args:
    bash scripts/system/firefoxos_tools_linux.sh {{args}}

# Adquirir, identificar, verificar, instalar o revertir raíces Mozilla en el
# conjunto NSS del perfil Firefox OS; --apply exige runtime B2G exacto.
# Uso: just firefoxos-ca --status|--acquire|--verify-source|--identify-runtime|--preflight|--plan|--apply --confirm ...|--test|--rollback --confirm ...
firefoxos-ca *args:
    bash scripts/system/firefoxos_ca_linux.sh {{args}}

# Verificar y flashear de forma controlada la base v18D de un Mozilla Flame
# Uso: just firefoxos-flash-base --check|--plan|--fastboot|--apply --archive /tmp/v18D.zip
firefoxos-flash-base *args:
    bash scripts/system/firefoxos_flash_base_linux.sh {{args}}

# Verificar y flashear de forma controlada la base v18D nightly v5 de Firefox OS 2.6
# Uso: just firefoxos-flash-nightly --check|--plan|--fastboot|--apply --archive /tmp/v18D_nightly_v5.zip
firefoxos-flash-nightly *args:
    bash scripts/system/firefoxos_flash_nightly_linux.sh {{args}}

# Validar, empaquetar o publicar localmente la aplicación Firefox OS Hola Mundo
# Uso: just firefoxos-hello-world --check | --status | --package | --plan | --serve-podman | --stop-podman
firefoxos-hello-world *args:
    bash scripts/system/firefoxos_hello_world_linux.sh {{args}}

# Administrar la cola SMS local y su publicador Podman para Firefox OS
# Uso: just firefoxos-sms --serve-podman|--status|--pair|--enqueue|--history|--revoke|--purge
firefoxos-sms *args:
    bash scripts/system/firefoxos_sms_bridge_linux.sh {{args}}
