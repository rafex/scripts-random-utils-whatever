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

# Descargar, verificar e instalar RustDesk 1.4.9 desde el DEB oficial
# Uso: just install-rustdesk --check|--plan|--apply|--status
install-rustdesk *args:
    bash scripts/install/install_rustdesk_linux.sh {{args}}

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

# Consultar descargas oficiales de Node.js
# Uso: just scrape-node-runtime --version lts
scrape-node-runtime *args:
    python3 scripts/install/scrape_node_runtime.py {{args}}

# Consultar descargas oficiales de Maven o Gradle
# Uso: just scrape-build-runtime --tool maven --version latest
scrape-build-runtime *args:
    python3 scripts/install/scrape_build_runtime.py {{args}}

# Descargar y seleccionar un runtime Java local; integra el proveedor en mise
# Uso: just install-java-runtime --provider temurin --version 25 --apply
install-java-runtime *args:
    bash scripts/install/install_java_runtime_linux.sh {{args}}

# Instalar Node.js oficial manualmente e integrarlo en mise
# Uso: just install-node-runtime --version lts --apply
install-node-runtime *args:
    bash scripts/install/install_node_runtime_linux.sh {{args}}

# Instalar Maven o Gradle oficiales manualmente e integrarlos en mise
# Uso: just install-build-runtime --tool maven --version latest --apply
install-build-runtime *args:
    bash scripts/install/install_build_runtime_linux.sh {{args}}

# Reconciliar runtimes propios y legacy de mise
# Uso: just reconcile-runtimes --check|--plan|--apply [--purge-legacy]
reconcile-runtimes *args:
    bash scripts/install/reconcile_runtimes_linux.sh {{args}}

# Registrar un JDK Temurin ya instalado en mise usando su ruta versionada directa
# Uso: just configure-java-mise --version 25 --apply
configure-java-mise *args:
    bash scripts/install/configure_java_mise_linux.sh {{args}}

# Instalar runtime-use y mantener JAVA_HOME en current-java
# Uso: just install-runtime-switcher --apply
install-runtime-switcher *args:
    bash scripts/install/install_runtime_switcher_linux.sh {{args}}

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

# Preparar permisos input y respaldo Polkit para brillo XF86 del teclado
# Uso: just install-kbd-brightness --check|--plan|--apply|--status
install-kbd-brightness *args:
    bash scripts/install/install_kbd_brightness_policy_linux.sh {{args}}

# Instalar gaps nativos de i3 (i3 >= 4.22), sin compilar el fork archivado
# Uso: just install-i3-gaps --apply
install-i3-gaps *args:
    bash scripts/install/install_i3_gaps_linux.sh {{args}}

# Configurar Xorg explícitamente para modesetting/DRI3 en la ThinkPad
# Uso: just configure-thinkpad-xorg-dri3 --check|--plan|--apply|--status
configure-thinkpad-xorg-dri3 *args:
    bash scripts/install/configure_thinkpad_xorg_dri3_linux.sh {{args}}

# Instalar el perfil Openbox paralelo con tint2 sin reemplazar i3
# Uso: just install-openbox-profile --dry-run | just install-openbox-profile
install-openbox-profile *args:
    bash scripts/install/install_openbox_profile_linux.sh {{args}}

# Instalar y configurar UFW con SSH/Mosh y perfiles opcionales de desarrollo/media
# Uso: just install-ufw --apply [--profile base|dev|media|all]
install-ufw *args:
    bash scripts/install/install_ufw_linux.sh {{args}}

# Endurecer SSH y controles de seguridad de la ThinkPad por fases
# Uso: just harden-thinkpad --apply --stage ssh|local|all
harden-thinkpad *args:
    bash scripts/install/harden_thinkpad_linux.sh {{args}}

# Instalar herramientas de auditoría y laboratorio de seguridad por fases
# Uso: just install-security-lab --apply --stage base|wireless|web|forensics|credentials|virtualization|all
install-security-lab *args:
    bash scripts/install/install_security_lab_linux.sh {{args}}

# Instalar ADB, fastboot, reglas udev Android y scrcpy desde Debian
# Uso: just install-android-tools --check|--plan|--apply|--status
install-android-tools *args:
    bash scripts/install/install_android_tools_linux.sh {{args}}

# Preparar runtime NSS legado en Podman para el almacén NSS de un Flame
# Uso: just install-firefoxos-ca-tools --check|--plan|--apply|--status
install-firefoxos-ca-tools *args:
    bash scripts/install/install_firefoxos_ca_tools_linux.sh {{args}}

# Preparar el puente SMS rootless entre la ThinkPad y un Firefox OS Flame
# Uso: just install-firefoxos-sms-bridge --check|--plan|--apply|--status
install-firefoxos-sms-bridge *args:
    bash scripts/install/install_firefoxos_sms_bridge_linux.sh {{args}}

# Instalar herramientas creativas: GIMP, ayuda en español y Krita
# Uso: just install-graphics --check|--apply
install-graphics *args:
    bash scripts/install/install_graphics_linux.sh {{args}}

# Instalar LibreOffice y locale español de la sesión del usuario
# Uso: just install-office --apply --locale es_MX
install-office *args:
    bash scripts/install/install_office_linux.sh {{args}}

# Instalar ClamAV y configurar opcionalmente el escaneo USB con udiskie
# Uso: just install-antivirus --apply [--auto-usb]
install-antivirus *args:
    bash scripts/install/install_antivirus_linux.sh {{args}}

# Instalar reproducción, codificación y plugins multimedia desde Debian
# Uso: just install-multimedia --check|--apply
install-multimedia *args:
    bash scripts/install/install_multimedia_linux.sh {{args}}

# Instalar fuentes web/programación, Nerd Font para EWW o cobertura CJK opcional
# Uso: just install-fonts --apply --profile web-programming|nerd|cjk|all
install-fonts *args:
    bash scripts/install/install_fonts_linux.sh {{args}}

# Instalar CopyQ e integrar el historial de portapapeles en i3/Openbox
# Uso: just install-clipboard --check|--plan|--apply|--status
install-clipboard *args:
    bash scripts/install/install_clipboard_linux.sh {{args}}

# Instalar maim y atajos de captura de pantalla para i3/Openbox
# Uso: just install-screenshot --check|--plan|--apply|--status
install-screenshot *args:
    bash scripts/install/install_screenshot_linux.sh {{args}}

# Instalar Codex CLI y Claude Code con npm del usuario, sin sudo
# Uso: just install-ai-cli --check|--plan|--apply|--status
install-ai-cli *args:
    bash scripts/install/install_ai_cli_linux.sh {{args}}

# Instalar age y gopass oficial; no inicializa el almacén automáticamente
# Uso: just install-age-gopass --check|--plan|--apply|--status
install-age-gopass *args:
    bash scripts/install/install_age_gopass_linux.sh {{args}}

# Inicializar explícitamente un almacén gopass con el backend age
# Uso: just init-gopass-age
init-gopass-age *args:
    bash scripts/install/install_age_gopass_linux.sh --init-gopass-age {{args}}

# Instalar CUPS, SANE y controladores Debian para Epson XP-241 y Xerox Phaser 3020
# Uso: just install-printers --check|--plan|--apply|--status
install-printers *args:
    bash scripts/install/install_printers_linux.sh {{args}}

# Configurar colas CUPS idempotentes para Epson XP-241 y Xerox Phaser 3020
# Uso: just configure-printers --apply [--printer epson|xerox|all]
configure-printers *args:
    bash scripts/install/configure_printers_linux.sh {{args}}

# Enviar una página de prueba a una cola configurada sin sudo
# Uso: just printer-test --printer xerox|epson
printer-test *args:
    bash scripts/install/configure_printers_linux.sh --test-print {{args}}

# Instalar Restic y Secret Service sin inicializar repositorios
# Uso: just install-restic-backup --check|--plan|--apply
install-restic-backup *args:
    bash scripts/install/install_restic_backup_linux.sh {{args}}

# Configurar QEMU/KVM para virtualización de usuario sin bridges físicos
# Uso: just configure-kvm --check|--plan|--apply|--status
configure-kvm *args:
    bash scripts/install/configure_kvm_linux.sh {{args}}

# Auditar de forma integral la preparación de la ThinkPad; no modifica el sistema
# Uso: just audit-thinkpad --check
audit-thinkpad *args:
    bash scripts/install/audit_thinkpad_readiness_linux.sh {{args}}

# Instalar los fondos del perfil ThinkPad en i3, GRUB y LightDM por etapas
# Uso: just install-thinkpad-backgrounds --apply --stage desktop|grub|login|all
install-thinkpad-backgrounds *args:
    bash scripts/install/install_thinkpad_backgrounds_linux.sh {{args}}

# Instalar Conky e integrar el panel lateral en i3 y Openbox
# Uso: just install-conky --check|--plan|--apply|--status
install-conky *args:
    bash scripts/install/install_conky_linux.sh {{args}}

# Instalar feh y unificar el fondo del perfil ThinkPad en i3/Openbox
# Uso: just install-feh --check|--plan|--apply|--status
install-feh *args:
    bash scripts/install/install_feh_linux.sh {{args}}

# Instalar ratmenu y migrar el menú activo conservando 9menu como respaldo
# Uso: just install-ratmenu --check|--plan|--apply|--status
install-ratmenu *args:
    bash scripts/install/install_ratmenu_linux.sh {{args}}

# Compilar EWW X11 v0.6.0 e instalar el dashboard Rafex de usuario
# Uso: just install-eww --check|--plan|--apply|--status
install-eww *args:
    bash scripts/install/install_eww_linux.sh {{args}}

# Compilar i3lock-color en paralelo al bloqueador oficial
# Uso: just install-i3lock-color --check|--plan|--apply|--status
install-i3lock-color *args:
    bash scripts/install/install_i3lock_color_linux.sh {{args}}

# Instalar el panel GTK3/PyGObject del perfil Rafex
# Uso: just install-rafex-control-panel --check|--plan|--apply|--status
install-rafex-control-panel *args:
    bash scripts/install/install_rafex_control_panel_linux.sh {{args}}
