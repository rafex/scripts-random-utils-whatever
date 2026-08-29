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

# Diagnosticar herramientas y dispositivos de pluma Wacom
# Uso: just test-wacom-pen --check | just test-wacom-pen --apply
test-wacom-pen *args:
    bash scripts/hardware/test_wacom_pen_linux.sh {{args}}

# Preparar apagado, reinicio, suspensión, hibernación y bloqueo
# Uso: just power-control --check | just power-control --apply
power-control *args:
    bash scripts/hardware/power_control_linux.sh {{args}}

# Hacer permanente s2idle para mejorar la reanudación de la ThinkPad X1 Yoga
# Uso: just configure-thinkpad-s2idle --check | --plan | --apply
configure-thinkpad-s2idle *args:
    bash scripts/hardware/configure_thinkpad_s2idle_linux.sh {{args}}

# Activar TRIM periódico para SSD/NVMe mediante systemd
# Uso: just configure-fstrim --check | --plan | --apply | --status
configure-fstrim *args:
    bash scripts/hardware/configure_fstrim_linux.sh {{args}}
