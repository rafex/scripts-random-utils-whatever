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

# Configurar el repositorio oficial de Mozilla e instalar Firefox DEB nativo
# Uso: just install-firefox-mozilla --apply
install-firefox-mozilla *args:
    bash scripts/install/install_firefox_mozilla_linux.sh {{args}}

# Configurar el repositorio oficial e instalar GitHub CLI (`gh`)
# Uso: just install-github-cli --apply
install-github-cli *args:
    bash scripts/install/install_github_cli_linux.sh {{args}}

# Configurar el repositorio oficial e instalar VSCodium como paquete DEB
# Uso: just install-vscodium --apply
install-vscodium *args:
    bash scripts/install/install_vscodium_linux.sh {{args}}

# Extraer versiones/enlaces oficiales de Eclipse IDE Java y Enterprise Java
# Uso: just scrape-eclipse-packages --package all --pretty
scrape-eclipse-packages *args:
    python3 scripts/install/scrape_eclipse_packages.py {{args}}

# Descargar, verificar e instalar Eclipse IDE Java o Enterprise Java/Web
# Uso: just install-eclipse-ide --package jee --apply
install-eclipse-ide *args:
    bash scripts/install/install_eclipse_ide_linux.sh {{args}}

# Generar clave SSH y establecer confianza instalando solo la pública
# Uso: just setup-ssh-trust --apply --target rafex@192.168.3.91
setup-ssh-trust *args:
    bash scripts/install/setup_ssh_trust_unix.sh {{args}}

# Migrar configuración segura y hardware desde otra laptop Debian/Linux
# Uso: just migrate-laptop --source rafex@192.168.3.174 --check
# Hardware: just migrate-laptop --stage hardware --apply
# Tablet: just migrate-laptop --stage tablet --apply
migrate-laptop *args:
    bash scripts/install/migrate_laptop_linux.sh {{args}}

# Preparar terminal, editor, runtimes, OpenCode y Podman rootless en Debian
# Uso: just install-terminal-workstation --apply --stage all
install-terminal-workstation *args:
    bash scripts/install/install_terminal_workstation_linux.sh {{args}}
