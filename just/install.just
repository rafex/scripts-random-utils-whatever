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

# Aplicar un perfil de dotfiles directamente en el usuario actual
# Uso: just install-profile thinkpad-x1-yoga-1st [--dry-run]
install-profile profile *args:
    bash dotfiles/install.sh --profile {{profile}} {{args}}

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

# Consultar versiones y binarios oficiales de Temurin, GraalVM y Semeru
# Uso: just scrape-java-runtimes --provider all --pretty
scrape-java-runtimes *args:
    python3 scripts/install/scrape_java_runtimes.py {{args}}

# Descargar y seleccionar un runtime Java local; registra Temurin automáticamente en mise
# Uso: just install-java-runtime --provider temurin --version 25 --apply
install-java-runtime *args:
    bash scripts/install/install_java_runtime_linux.sh {{args}}

# Registrar un JDK Temurin ya instalado en mise usando su ruta versionada directa
# Uso: just configure-java-mise --version 25 --apply
configure-java-mise *args:
    bash scripts/install/configure_java_mise_linux.sh {{args}}

# Instalar el comando reload-bash y su función en ~/.bashrc
# Uso: just install-bash-reload --apply
install-bash-reload *args:
    bash scripts/install/install_bash_reload_linux.sh {{args}}

# Instalar y configurar el MCP oficial Ether-rules para clientes detectados
# Uso: just install-ether-rules-mcp --apply
install-ether-rules-mcp *args:
    bash scripts/install/install_ether_rules_mcp_unix.sh {{args}}

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

# Instalar controles multimedia, Wi-Fi, modo avión, Rofi y configuraciones para i3
# Uso: just install-i3-laptop-controls --apply
install-i3-laptop-controls *args:
    bash scripts/install/install_i3_laptop_controls_linux.sh {{args}}

# Instalar y configurar UFW con SSH/Mosh y perfiles opcionales de desarrollo/media
# Uso: just install-ufw --apply [--profile base|dev|media|all]
install-ufw *args:
    bash scripts/install/install_ufw_linux.sh {{args}}

# Endurecer SSH y controles de seguridad de la ThinkPad por fases
# Uso: just harden-thinkpad --apply --stage ssh|local|all
harden-thinkpad *args:
    bash scripts/install/harden_thinkpad_linux.sh {{args}}
