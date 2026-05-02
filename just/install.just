# =============================================================================
# just/install.just — Tareas para scripts/install/
# =============================================================================

# Crear un USB booteable desde una ISO de Debian/Linux
# Uso: just create-usb --from debian.iso --to disk4
create-usb *args:
    bash scripts/install/create_usb_macos_debian.sh {{args}}
