# =============================================================================
# just/system.just — Tareas para scripts/system/
# =============================================================================

# Alternar el tema claro/oscuro de i3, tmux, Alacritty, Rofi y Dunst
# Uso: just theme-toggle --check | just theme-toggle --set dark | just theme-toggle --toggle
theme-toggle *args:
    bash scripts/system/theme_toggle_linux.sh {{args}}
