# =============================================================================
# just/install.just — Tareas para scripts/install/
# =============================================================================

# Crear un USB booteable desde una ISO de Debian/Linux
# Uso: just create-usb --from debian.iso --to disk4
create-usb *args:
    bash scripts/install/create_usb_unix.sh {{args}}

# Formatear un disco USB (FAT32, exFAT, ext4, APFS, HFS+)
# Uso: just format-usb --disk disk5 --format FAT32 --name MI_USB
format-usb *args:
    bash scripts/install/format_usb_unix.sh {{args}}
