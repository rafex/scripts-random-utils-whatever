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
