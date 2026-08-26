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

# Empaquetar dotfiles i3wm en tar.gz distribuible con instalador autocontenido
# Uso: just install-dotfiles | just install-dotfiles --dry-run
install-dotfiles *args:
    bash scripts/install/install_dotfiles_unix.sh {{args}}

# Configurar sudo para un usuario Debian recién instalado (ejecutar como root)
# Uso: su -; just configure-sudo --user rafex --apply
configure-sudo *args:
    bash scripts/install/configure_sudo_linux.sh {{args}}

# Instalar Mosh/tmux/Kitty y configurar el portapapeles OSC 52
# Uso: just install-mosh-tmux-kitty --apply
install-mosh-tmux-kitty *args:
    bash scripts/install/install_mosh_tmux_kitty_unix.sh {{args}}

# Habilitar main, contrib, non-free y non-free-firmware de Debian
# Uso: just enable-debian-repositories --apply
enable-debian-repositories *args:
    bash scripts/install/enable_debian_repositories_linux.sh {{args}}

# Generar clave SSH y establecer confianza instalando solo la pública
# Uso: just setup-ssh-trust --apply --target rafex@192.168.3.91
setup-ssh-trust *args:
    bash scripts/install/setup_ssh_trust_unix.sh {{args}}

# Migrar configuración segura y hardware desde otra laptop Debian/Linux
# Uso: just migrate-laptop --source rafex@192.168.3.174 --check
# Hardware: just migrate-laptop --stage hardware --apply
migrate-laptop *args:
    bash scripts/install/migrate_laptop_linux.sh {{args}}
