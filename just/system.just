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

# Mostrar el estado compacto usado por tint2
# Uso: just tint2-status
tint2-status *args:
    bash scripts/system/tint2_status_linux.sh {{args}}

# Escanear una memoria USB extraíble montada con ClamAV
# Uso: just scan-usb --path /run/media/$USER/NOMBRE_USB
scan-usb *args:
    bash scripts/system/scan_usb_clamav_linux.sh {{args}}

# Escanear un documento con el Epson XP-241 mediante SANE, sin sudo
# Uso: just scan-document --output ~/Documents/escaneo.png
scan-document *args:
    bash scripts/system/scan_document_linux.sh {{args}}

# Cifrar o descifrar un archivo con age sin exponer frases en argumentos
# Uso: just age-file --encrypt --input archivo --output archivo.age --recipient age1...
age-file *args:
    bash scripts/system/age_file_linux.sh {{args}}
