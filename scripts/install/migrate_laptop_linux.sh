#!/usr/bin/env bash
# shellcheck shell=bash
#
# Migración segura de una instalación Debian Linux a otra laptop.
# No transporta secretos ni acepta contraseñas como argumentos.
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"
REPO_ROOT="${MIGRATE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

SOURCE="${MIGRATE_SOURCE:-rafex@192.168.3.174}"
ACTION="check"
STAGE="${MIGRATE_STAGE:-audit}"
TARGET_USER="${SUDO_USER:-${USER:-}}"
APT_UPDATED=0
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  migrate_laptop_linux.sh [--source usuario@host] --check
  migrate_laptop_linux.sh [--source usuario@host] --plan [--stage ETAPA]
  migrate_laptop_linux.sh [--source usuario@host] --apply --stage ETAPA

Etapas:
  audit       Auditoría de origen y destino (default)
  hardware    Drivers, firmware, GPU, audio, input y WWAN
  desktop     Xorg, LightDM, i3 y perfil ThinkPad
  network     NetworkManager, polkit y grupo netdev
  usb         udisks2, udiskie y montaje USB sin sudo
  cameras     Cámara física, PipeWire, VA-API y v4l2loopback
  laptop      TLP, energía, brillo, thermald y NVMe
  display     Herramientas de pantalla; el ajuste se hace en sesión Xorg
  all         Todas las etapas en el orden recomendado

Opciones:
  --source usuario@host  Laptop fuente para auditoría no secreta
  --check                Solo auditar, sin modificar nada
  --plan                 Mostrar cambios previstos, sin modificar nada
  --dry-run              Alias de --plan
  --apply                Aplicar la etapa seleccionada
  --stage ETAPA          Etapa a ejecutar
  -h, --help             Mostrar esta ayuda

La contraseña de sudo se solicita únicamente mediante sudo -v. Nunca se
lee desde argumentos, variables de entorno ni archivos.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        [[ $# -ge 2 ]] || die "--source requiere usuario@host"
        SOURCE="$2"
        shift 2
        ;;
      --check) ACTION="check"; shift ;;
      --plan) ACTION="plan"; shift ;;
      --dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --stage)
        [[ $# -ge 2 ]] || die "--stage requiere un valor"
        STAGE="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done

  case "$STAGE" in
    audit|hardware|desktop|network|usb|cameras|laptop|display|all) ;;
    *) die "etapa inválida: $STAGE" ;;
  esac
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este script solo funciona en Linux"
  [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || \
    die "ejecuta el script como el usuario de la laptop, no como root"
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
  if [[ "$ACTION" == "apply" ]] && ! command -v sudo >/dev/null 2>&1; then
    die "sudo no está instalado. Como root ejecuta: bash $REPO_ROOT/scripts/install/configure_sudo_linux.sh --user $TARGET_USER --apply; después inicia una nueva sesión"
  fi
}

run_root() {
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] sudo $*"
  else
    sudo "$@"
  fi
}

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  local temporary

  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] instalar $destination (modo $mode)"
    return 0
  fi

  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  run_root install -D -m "$mode" "$temporary" "$destination"
  rm -f "$temporary"
}

backup_root_file() {
  local destination="$1"
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] respaldar $destination → ${destination}.bak.$BACKUP_STAMP"
  elif [[ -e "$destination" ]]; then
    run_root cp -a "$destination" "${destination}.bak.$BACKUP_STAMP"
  fi
}

ensure_sudo() {
  [[ "$ACTION" == "apply" ]] || return 0
  info "Se solicitará sudo para aplicar la etapa '$STAGE'."
  sudo -v
}

apt_install() {
  local packages=("$@")
  [[ ${#packages[@]} -gt 0 ]] || return 0
  info "Paquetes: ${packages[*]}"
  if [[ "$ACTION" == "plan" ]]; then
    run_root apt-get install -y "${packages[@]}"
    return 0
  fi
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    run_root apt-get update
    APT_UPDATED=1
  fi
  run_root apt-get install -y "${packages[@]}"
}

enable_service() {
  local service="$1"
  if systemctl list-unit-files "$service" >/dev/null 2>&1; then
    run_root systemctl enable --now "$service"
  else
    warn "servicio no disponible: $service"
  fi
}

enable_user_service() {
  local service="$1"
  if [[ "$ACTION" != "apply" ]]; then
    info "[plan] systemctl --user enable --now $service"
  elif systemctl --user list-unit-files "$service" >/dev/null 2>&1; then
    systemctl --user enable --now "$service" || warn "no se pudo activar el servicio de usuario: $service"
  else
    warn "servicio de usuario no disponible todavía: $service"
  fi
}

ensure_group_membership() {
  local group="$1"
  if ! getent group "$group" >/dev/null 2>&1; then
    run_root groupadd "$group"
  fi
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx "$group"; then
    ok "$TARGET_USER ya pertenece a $group"
  else
    run_root usermod -aG "$group" "$TARGET_USER"
    ok "$TARGET_USER agregado a $group; requiere nueva sesión"
  fi
}

print_packages() {
  cat <<'EOF'
Paquetes por etapa:
  hardware: pciutils usbutils lshw dmidecode dkms gcc linux-headers-amd64
            libgl1-mesa-dri libglx-mesa0 mesa-utils mesa-vulkan-drivers
            vulkan-tools vainfo intel-gpu-tools ffmpeg
            intel-media-va-driver-non-free
            pipewire pipewire-pulse pipewire-audio wireplumber alsa-utils
            pavucontrol v4l-utils guvcview obs-studio
            xserver-xorg-input-libinput xserver-xorg-input-wacom
            libinput-tools iio-sensor-proxy libwacom-common libwacom-bin
            modemmanager usb-modeswitch bluez blueman fwupd
            fprintd libpam-fprintd (opcionales)
  desktop: xorg lightdm lightdm-gtk-greeter i3-wm i3status rofi dunst
           alacritty picom feh maim brightnessctl pavucontrol
           x11-xserver-utils x11-xkb-utils xss-lock i3lock dex libnotify-bin
  network: network-manager network-manager-applet polkitd lxpolkit
  usb:     udisks2 udiskie libnotify-bin
  cameras: v4l-utils ffmpeg guvcview obs-studio pipewire pipewire-pulse
           pipewire-audio wireplumber gstreamer1.0-pipewire mesa-utils vainfo
           mesa-va-drivers intel-media-va-driver v4l2loopback-dkms
           v4l2loopback-utils linux-headers-amd64
  laptop:  tlp tlp-rdw upower acpi thermald nvme-cli smartmontools
  display: xrandr autorandr xinput libinput-tools
EOF
}

ensure_debian_repositories() {
  local repository_script="$REPO_ROOT/scripts/install/enable_debian_repositories_linux.sh"
  [[ -x "$repository_script" || -f "$repository_script" ]] || \
    die "falta el script de repositorios: $repository_script"

  if [[ "$ACTION" == "plan" ]]; then
    bash "$repository_script" --plan
  else
    bash "$repository_script" --apply
  fi
}

apt_install_optional() {
  local requested=()
  local package
  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      requested+=("$package")
    else
      warn "paquete opcional no disponible en los repositorios: $package"
    fi
  done
  [[ ${#requested[@]} -gt 0 ]] || return 0
  apt_install "${requested[@]}"
}

run_readonly_check() {
  local label="$1"
  shift
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "$label: herramienta no instalada ($1)"
    return 0
  fi
  if "$@"; then
    ok "$label"
  else
    warn "$label: no disponible en la sesión actual"
  fi
}

audit_hardware() {
  echo
  echo -e "${BOLD}${CYAN}═══ Diagnóstico detallado de hardware ═══${RESET}"
  echo "pci-drivers:"
  lspci -nnk 2>/dev/null || warn "lspci no disponible"
  echo "usb-drivers:"
  lsusb -t 2>/dev/null || warn "lsusb no disponible"
  echo "drm-nodes:"
  stat -c '%n %A %U:%G' /dev/dri/* 2>/dev/null || warn "nodos DRM no encontrados"
  printf "render-group="
  id -nG 2>/dev/null | tr ' ' '\n' | grep -qx render && echo yes || echo no
  echo "firmware-packages:"
  dpkg-query -W -f='${Package}\t${Version}\n' \
    firmware-intel-graphics firmware-intel-misc firmware-iwlwifi \
    firmware-sof-signed intel-microcode firmware-realtek 2>/dev/null || true
  echo "kernel-modules:"
  lsmod 2>/dev/null | grep -E '^(i915|snd|uvcvideo|wacom|iwlwifi|btusb|cdc_mbim|nvme|v4l2loopback)' || true
  echo "fingerprint:"
  lsusb 2>/dev/null | grep -iE 'validity|fingerprint|138a:' || echo "no identificado por lsusb"
  echo "power-and-sensors:"
  for path in /sys/class/power_supply/* /sys/class/thermal/thermal_zone*; do
    [[ -e "$path" ]] && basename "$path"
  done
  echo "diagnostic-tools:"
  for command_name in vainfo glxinfo vulkaninfo ffmpeg aplay wpctl v4l2-ctl nmcli mmcli fwupdmgr; do
    command -v "$command_name" >/dev/null 2>&1 && echo "$command_name=available" || echo "$command_name=missing"
  done
}

verify_hardware_stack() {
  echo
  echo -e "${BOLD}${CYAN}═══ Verificación de aceleración y periféricos ═══${RESET}"
  run_readonly_check "VA-API DRM" vainfo --display drm --device /dev/dri/renderD128
  run_readonly_check "OpenGL" glxinfo -B
  run_readonly_check "Vulkan" vulkaninfo --summary
  run_readonly_check "FFmpeg hardware acceleration" ffmpeg -hide_banner -hwaccels
  run_readonly_check "ALSA" aplay -l
  run_readonly_check "PipeWire" wpctl status
  run_readonly_check "V4L2" v4l2-ctl --list-devices
  run_readonly_check "NetworkManager" nmcli device
  run_readonly_check "ModemManager" mmcli -L
  run_readonly_check "Bluetooth" bluetoothctl list
  run_readonly_check "fwupd" fwupdmgr get-devices
}

audit_source() {
  echo
  echo -e "${BOLD}${CYAN}═══ Auditoría de origen: $SOURCE ═══${RESET}"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SOURCE" 'true' >/dev/null 2>&1; then
    warn "no se pudo conectar por SSH a $SOURCE"
    return 0
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$SOURCE" '
    echo "host=$(hostname)"
    printf "os="; . /etc/os-release 2>/dev/null && printf "%s %s\\n" "$ID" "${VERSION_ID:-$VERSION_CODENAME}"
    printf "kernel="; uname -r
    printf "user-groups="; id -nG
    printf "packages="; dpkg-query -W 2>/dev/null | cut -f1 | grep -E "^(i3-wm|i3status|network-manager|network-manager-applet|polkitd|udisks2|udiskie|pipewire|wireplumber|v4l-utils|v4l2loopback|tlp|autorandr)$" | sort | tr "\\n" " " || true; echo
    echo "network-profiles-no-secrets:"
    nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null || true
    echo "safe-system-configs:"
    for f in /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/dns.conf /etc/NetworkManager/conf.d/wifi-powersave.conf; do
      [ -f "$f" ] && echo "$f"
    done
    echo "camera-devices:"
    ls -1 /dev/video* 2>/dev/null || true
    echo "user-configs:"
    find "$HOME/.config" -maxdepth 2 -type f \( -path "*/i3/*" -o -path "*/i3status/*" -o -path "*/udiskie/*" -o -path "*/dunst/*" -o -path "*/rofi/*" -o -path "*/alacritty/*" -o -path "*/picom/*" \) -print 2>/dev/null | sort
  ' 2>/dev/null || warn "la auditoría SSH de origen no terminó correctamente"
}

audit_target() {
  echo
  echo -e "${BOLD}${CYAN}═══ Auditoría de destino ═══${RESET}"
  echo "host=$(hostname)"
  printf "os="; . /etc/os-release 2>/dev/null && printf "%s %s\n" "$ID" "${VERSION_ID:-$VERSION_CODENAME}"
  printf "kernel="; uname -r
  printf "model="; cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo desconocido
  printf "cpu="; lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}'
  printf "groups="; id -nG
  echo "interfaces:"
  ip -br link 2>/dev/null || true
  echo "drm-connectors:"
  for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" ]] || continue
    printf '%s=' "${status%/status}" | sed 's#^.*/##'
    cat "$status"
  done
  echo "video-devices:"
  ls -l /dev/video* 2>/dev/null || true
  echo "power-supplies:"
  for supply in /sys/class/power_supply/*; do
    [[ -e "$supply" ]] && basename "$supply"
  done
  echo "backlight-devices:"
  for device in /sys/class/backlight/* /sys/class/leds/*; do
    [[ -d "$device" ]] || continue
    case "$(basename "$device")" in
      intel_backlight|*kbd_backlight*) basename "$device" ;;
    esac
  done
  echo "installed-relevant-packages:"
  dpkg-query -W 2>/dev/null | cut -f1 | grep -E "^(network-manager|polkitd|udisks2|i3|lightdm|pipewire|wireplumber|tlp|firmware-iwlwifi|firmware-sof-signed)$" | sort || true
}

stage_desktop() {
  apt_install xorg lightdm lightdm-gtk-greeter i3-wm i3status rofi dunst \
    alacritty picom feh maim brightnessctl pavucontrol x11-xserver-utils \
    x11-xkb-utils xss-lock i3lock dex libnotify-bin xinput \
    xserver-xorg-input-libinput

  if [[ "$ACTION" == "apply" ]]; then
    enable_service lightdm
    bash "$REPO_ROOT/dotfiles/install.sh" --profile thinkpad-x1-yoga-1st
    install_user_helpers
  elif [[ "$ACTION" == "plan" ]]; then
    bash "$REPO_ROOT/dotfiles/install.sh" --profile thinkpad-x1-yoga-1st --dry-run
    install_user_helpers
  fi
  ok "etapa desktop preparada; inicia sesión gráfica y valida i3 antes de continuar"
}

stage_hardware() {
  ensure_debian_repositories
  apt_install pciutils usbutils lshw dmidecode dkms gcc linux-headers-amd64 \
    libgl1-mesa-dri libglx-mesa0 mesa-utils mesa-vulkan-drivers vulkan-tools \
    vainfo intel-gpu-tools ffmpeg intel-media-va-driver-non-free \
    pipewire pipewire-pulse pipewire-audio wireplumber alsa-utils pavucontrol \
    v4l-utils guvcview obs-studio \
    xserver-xorg-input-libinput xserver-xorg-input-wacom libinput-tools \
    iio-sensor-proxy libwacom-common libwacom-bin modemmanager usb-modeswitch \
    bluez blueman fwupd
  apt_install_optional fprintd libpam-fprintd

  ensure_group_membership video
  ensure_group_membership render

  if [[ "$ACTION" == "apply" ]]; then
    enable_service ModemManager
    enable_service bluetooth
    enable_user_service pipewire
    enable_user_service pipewire-pulse
    enable_user_service wireplumber
    verify_hardware_stack
    info "Si se agregó el grupo render, cierra sesión y vuelve a entrar antes de repetir las pruebas GPU"
    info "La huella se valida manualmente con: fprintd-enroll"
  fi
  ok "drivers, firmware de usuario, aceleración, audio, input y WWAN preparados"
}

install_user_helpers() {
  local destination="$HOME/.local/bin"
  local mapping=(
    "scripts/hardware/notify_volume_linux.sh:volume-notify.sh"
    "scripts/hardware/notify_brightness_linux.sh:brightness-notify.sh"
    "scripts/hardware/notify_kbd_brightness_linux.sh:kbd-brightness-notify.sh"
    "scripts/hardware/notify_power_linux.sh:power-notify.sh"
    "scripts/hardware/screensaver_toggle_linux.sh:screensaver-toggle"
    "scripts/display/hidpi_xorg_linux.sh:hidpi_xorg.sh"
    "scripts/display/screen_auto_mirror_linux.sh:screen-auto-mirror.sh"
    "scripts/display/screen_auto_edge_mirror_linux.sh:screen-auto-edge-mirror.sh"
    "scripts/display/screen_extend_auto_linux.sh:screen-extend-auto.sh"
    "scripts/display/screen_mirror_linux.sh:screen-mirror.sh"
    "scripts/hardware/usb_mount_perms_linux.sh:usb-mount-perms"
  )

  for entry in "${mapping[@]}"; do
    local source_path="${entry%%:*}"
    local name="${entry##*:}"
    local source_file="$REPO_ROOT/$source_path"
    local target="$destination/$name"
    [[ -f "$source_file" ]] || { warn "helper ausente: $source_path"; continue; }
    if [[ "$ACTION" == "plan" ]]; then
      info "[plan] instalar helper $target"
      continue
    fi
    mkdir -p "$destination"
    if [[ -e "$target" && ! -L "$target" ]]; then
      cp -a "$target" "${target}.bak.$BACKUP_STAMP"
    fi
    install -m 755 "$source_file" "$target"
  done
  ok "helpers de hardware y pantalla instalados en $destination"
}

stage_network() {
  apt_install network-manager network-manager-applet polkitd lxpolkit
  ensure_group_membership netdev

  local rule='/etc/polkit-1/rules.d/50-networkmanager-netdev.rules'
  local content='polkit.addRule(function(action, subject) {
    var allowed = [
        "org.freedesktop.NetworkManager.settings.modify.system",
        "org.freedesktop.NetworkManager.settings.modify.own",
        "org.freedesktop.NetworkManager.network-control",
        "org.freedesktop.NetworkManager.enable-disable-wifi",
        "org.freedesktop.NetworkManager.enable-disable-network",
        "org.freedesktop.NetworkManager.wifi.scan"
    ];
    if (subject.local && subject.active && subject.isInGroup("netdev") &&
        allowed.indexOf(action.id) >= 0) {
        return polkit.Result.YES;
    }
});'
  backup_root_file "$rule"
  write_root_file "$rule" 644 "$content"

  if [[ "$ACTION" == "apply" ]]; then
    enable_service NetworkManager
    if systemctl is-active --quiet wpa_supplicant.service 2>/dev/null; then
      warn "wpa_supplicant.service ya está activo; no se desactiva automáticamente para evitar perder conectividad"
    fi
    ok "NetworkManager configurado; cierra sesión y entra de nuevo para netdev"
  fi
  info "Perfiles Wi-Fi del origen se recrearán manualmente con: nmcli device wifi connect SSID --ask"
}

stage_usb() {
  apt_install udisks2 udiskie polkitd libnotify-bin
  ensure_group_membership plugdev
  if [[ "$ACTION" == "apply" ]]; then
    bash "$REPO_ROOT/scripts/hardware/usb_mount_perms_linux.sh" --fix --yes --no-legacy-udev
  else
    bash "$REPO_ROOT/scripts/hardware/usb_mount_perms_linux.sh" --dry-run --fix --yes --no-legacy-udev
  fi
}

stage_cameras() {
  apt_install v4l-utils ffmpeg guvcview obs-studio pipewire pipewire-pulse \
    pipewire-audio wireplumber gstreamer1.0-pipewire mesa-utils vainfo \
    mesa-va-drivers intel-media-va-driver v4l2loopback-dkms \
    v4l2loopback-utils linux-headers-amd64
  ensure_group_membership video

  local modprobe_conf='/etc/modprobe.d/v4l2loopback.conf'
  local modules_conf='/etc/modules-load.d/v4l2loopback.conf'
  local options='options v4l2loopback video_nr=10,11,12,13,14,15,16,17 card_label="MacOS Window 1,MacOS Window 2,Guest 1 (SRT),Guest 2 (SRT),Guest 3 (SRT),Guest 4 (SRT),Guest 5 (SRT),Guest 6 (SRT)" exclusive_caps=0'
  backup_root_file "$modprobe_conf"
  write_root_file "$modprobe_conf" 644 "$options"
  backup_root_file "$modules_conf"
  write_root_file "$modules_conf" 644 'v4l2loopback'

  if [[ "$ACTION" == "apply" ]]; then
    if lsmod | awk '{print $1}' | grep -qx v4l2loopback; then
      warn "v4l2loopback ya está cargado; no se descarga ni se reinicia automáticamente"
    else
      run_root modprobe v4l2loopback || warn "no se pudo cargar v4l2loopback; revisa DKMS y headers"
    fi
  fi
  ok "cámaras físicas, PipeWire, VA-API y v4l2loopback preparados"
}

stage_laptop() {
  apt_install tlp tlp-rdw upower acpi thermald nvme-cli smartmontools
  if [[ "$ACTION" == "apply" ]]; then
    enable_service tlp
    enable_service thermald
    run_root systemctl enable --now fstrim.timer
    for conflicting in power-profiles-daemon auto-cpufreq laptop-mode-tools; do
      if dpkg-query -W -f='${Status}' "$conflicting" 2>/dev/null | grep -q 'install ok installed'; then
        warn "$conflicting está instalado; no se elimina automáticamente, pero no debe ejecutarse junto con TLP"
      fi
    done
  else
    run_root systemctl enable --now fstrim.timer
  fi
  ok "TLP, thermald y mantenimiento NVMe preparados"
}

stage_display() {
  apt_install xrandr autorandr xinput libinput-tools
  info "El ajuste de pantalla requiere una sesión Xorg activa. Ejecuta después:"
  echo "  xrandr --query"
  echo "  xinput list"
  echo "  autorandr --query"
  echo "  ~/.local/bin/hidpi_xorg.sh --check"
}

run_stage() {
  case "$1" in
    hardware) stage_hardware ;;
    desktop) stage_desktop ;;
    network) stage_network ;;
    usb) stage_usb ;;
    cameras) stage_cameras ;;
    laptop) stage_laptop ;;
    display) stage_display ;;
    *) die "etapa no aplicable: $1" ;;
  esac
}

main() {
  parse_args "$@"
  require_linux

  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  Migración segura Debian → ThinkPad${RESET}"
  echo -e "  Acción: $ACTION | Etapa: $STAGE | Origen: $SOURCE"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

  if [[ "$ACTION" == "plan" ]]; then
    print_packages
    echo
    info "No se modificarán archivos durante --plan."
  fi

  audit_source
  audit_target
  audit_hardware

  [[ "$STAGE" == "audit" || "$ACTION" == "check" ]] && {
    ok "auditoría completada; no se modificó el sistema"
    exit 0
  }

  ensure_sudo

  if [[ "$STAGE" == "all" ]]; then
    for stage in hardware desktop network usb cameras laptop display; do
      run_stage "$stage"
    done
  else
    run_stage "$STAGE"
  fi
}

main "$@"
