# =============================================================================
# just/hardware.just — Tareas para scripts/hardware/
# =============================================================================

# Activar/desactivar protector de pantalla (xset Screen Saver + DPMS)
# Uso: just screensaver off | just screensaver on | just screensaver toggle | just screensaver status
screensaver-toggle *args:
    bash scripts/hardware/screensaver_toggle_linux.sh {{args}}
