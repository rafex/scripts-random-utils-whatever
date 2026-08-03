# =============================================================================
# just/hardware.just — Tareas para scripts/hardware/
# =============================================================================

# Activar/desactivar protector de pantalla (xset Screen Saver + DPMS)
# Uso: just screensaver off | just screensaver on | just screensaver toggle | just screensaver status
screensaver-toggle *args:
    bash scripts/hardware/screensaver_toggle_linux.sh {{args}}

# Diagnosticar/corregir permisos de montaje USB sin sudo (polkit + udev + udiskie)
# Uso: just usb-perms --check | just usb-perms --fix | just usb-perms --dry-run --fix
usb-perms *args:
    bash scripts/hardware/usb_mount_perms_linux.sh {{args}}
