#!/usr/bin/env bash
# shellcheck shell=bash
# Instala controles multimedia y accesos de configuración para i3/Xorg.
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACTION="check"
TARGET_USER="${SUDO_USER:-${USER:-}}"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
I3_CONFIG="${I3_CONTROLS_CONFIG:-$HOME/.config/i3/config}"
LOG_FILE="${I3_CONTROLS_LOG_FILE:-}"
LOG_DIR="${I3_CONTROLS_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scripts-random-utils-whatever/logs}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_i3_laptop_controls_linux.sh --check
  install_i3_laptop_controls_linux.sh --plan
  install_i3_laptop_controls_linux.sh --apply
  install_i3_laptop_controls_linux.sh --apply --log-file <archivo>

Instala toggles de micrófono, Wi‑Fi y modo avión, búsqueda Rofi y un menú
de configuraciones para i3. No acepta ni guarda contraseñas.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION=check; shift ;;
      --plan|--dry-run) ACTION=plan; shift ;;
      --apply) ACTION=apply; shift ;;
      --log-file)
        [[ $# -ge 2 ]] || die "--log-file requiere un archivo"
        LOG_FILE="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die "este script solo funciona en Linux"
  [[ "$TARGET_USER" != root && -n "$TARGET_USER" ]] || die "ejecútalo como usuario normal"
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
    sudo -v
  fi
}

packages=(rofi dunst pavucontrol network-manager network-manager-applet nm-connection-editor
  blueman bluez arandr x11-utils xinput libnotify-bin brightnessctl rfkill gnome-disk-utility
  thunar xdg-utils lxpolkit synaptic)

init_logging() {
  [[ "$ACTION" == apply || -n "$LOG_FILE" ]] || return 0
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$LOG_DIR/install_i3_laptop_controls_${BACKUP_STAMP}.log"
  fi
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "log: $LOG_FILE"
}

report_failure() {
  local status="$?"
  if [[ "$status" -ne 0 && -n "$LOG_FILE" ]]; then
    echo "✗ ejecución fallida; log: $LOG_FILE" >&2
  fi
  exit "$status"
}

trap report_failure EXIT

install_packages() {
  info "Paquetes: ${packages[*]}"
  if [[ "$ACTION" == check ]]; then
    local missing=()
    local package
    for package in "${packages[@]}"; do
      if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fq 'install ok installed'; then
        missing+=("$package")
      fi
    done
    if ((${#missing[@]} > 0)); then
      warn "paquetes pendientes: ${missing[*]}"
    else
      ok "paquetes instalados"
    fi
    return 0
  fi
  [[ "$ACTION" == plan ]] && { info "[plan] sudo apt-get update"; info "[plan] sudo apt-get install -y ${packages[*]}"; return; }
  if [[ "$ACTION" != apply ]]; then
    return 0
  fi
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

install_helper() {
  local source="$1" name="$2"
  local target="$HOME/.local/bin/$name"
  [[ -f "$REPO_ROOT/$source" ]] || die "falta el script: $source"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $target"
    return
  fi
  if [[ "$ACTION" != apply ]]; then
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if [[ -e "$target" && ! -L "$target" ]]; then
    cp -a "$target" "$target.bak.$BACKUP_STAMP"
  fi
  install -m 755 "$REPO_ROOT/$source" "$target"
}

configure_i3() {
  local begin='# >>> i3-laptop-controls managed >>>'
  local end='# <<< i3-laptop-controls managed <<<'
  local dunst_line='exec_always --no-startup-id ~/.local/bin/dunst-smart.sh --start'
  local block
  block="$begin
bindsym XF86AudioMicMute exec --no-startup-id ~/.local/bin/microphone-notify.sh toggle
bindsym XF86WLAN exec --no-startup-id ~/.local/bin/wifi-toggle.sh toggle
bindsym XF86RFKill exec --no-startup-id ~/.local/bin/flight-mode-toggle.sh toggle
bindsym XF86Search exec --no-startup-id ~/.local/bin/rofi-search.sh apps
bindsym XF86KbdBrightnessDown exec --no-startup-id ~/.local/bin/kbd-brightness-notify.sh down
bindsym XF86KbdBrightnessUp exec --no-startup-id ~/.local/bin/kbd-brightness-notify.sh up
bindsym XF86LaunchA exec --no-startup-id ~/.local/bin/kbd-brightness-notify.sh down
bindsym XF86Explorer exec --no-startup-id ~/.local/bin/kbd-brightness-notify.sh up
bindsym \$mod+Shift+b exec --no-startup-id ~/.local/bin/rofi-search.sh browser
bindsym XF86WakeUp exec --no-startup-id ~/.local/bin/i3-settings-menu.sh power
bindsym XF86Tools exec --no-startup-id 9menu -popup -label \"ThinkPad\" -file ~/.config/9menu/laptop.menu
exec_always --no-startup-id sh -c 'command -v lxpolkit >/dev/null 2>&1 && ! pgrep -x lxpolkit >/dev/null 2>&1 && exec lxpolkit'
$end"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] actualizar bloque administrado en $I3_CONFIG"
    return
  fi
  if [[ "$ACTION" != apply ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$I3_CONFIG")"
  if [[ -f "$I3_CONFIG" ]]; then cp -a "$I3_CONFIG" "$I3_CONFIG.bak.$BACKUP_STAMP"; fi

  # El perfil ThinkPad antiguo definía estas teclas fuera del bloque
  # administrado. Retirarlas evita que el perfil y este instalador compitan
  # por el mismo keysym y permite reparar instalaciones ya duplicadas.
  # También elimina la regla legacy que forzaba Thunar a flotante; la
  # asignación de Thunar al escritorio 5 permanece en el perfil.
  if [[ -f "$I3_CONFIG" ]]; then
    local cleaned
    cleaned="$(mktemp "${I3_CONFIG}.tmp.XXXXXX")"
    awk -v begin="$begin" -v end="$end" -v dunst_line="$dunst_line" '
      $0 == begin {inside=1; print; next}
      $0 == end {inside=0; print; next}
      !inside && $0 == dunst_line {
        if (!dunst_found) { print; dunst_found=1 }
        next
      }
      !inside && $0 ~ /^[[:space:]]*exec_always[[:space:]]+--no-startup-id[[:space:]]+dunst[[:space:]]+--config[[:space:]]+/ {
        if (!dunst_found) { print dunst_line; dunst_found=1 }
        next
      }
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86WakeUp[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/i3-settings-menu\.sh[[:space:]]+power[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86Tools[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/i3-settings-menu\.sh[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86Explorer[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/rofi-search\.sh[[:space:]]+browser[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86LaunchA[[:space:]]+move[[:space:]]+scratchpad[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86LaunchA[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/kbd-brightness-notify\.sh[[:space:]]+down[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86Explorer[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/kbd-brightness-notify\.sh[[:space:]]+up[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86KbdBrightnessDown[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/kbd-brightness-notify\.sh[[:space:]]+down[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+XF86KbdBrightnessUp[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/kbd-brightness-notify\.sh[[:space:]]+up[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+b[[:space:]]+exec[[:space:]]+--no-startup-id[[:space:]]+~\/.local\/bin\/rofi-search\.sh[[:space:]]+browser[[:space:]]*$/ {removed=1; next}
      !inside && $0 ~ /^[[:space:]]*for_window[[:space:]]+\[class="Thunar"\][[:space:]]+floating[[:space:]]+enable,[[:space:]]+resize[[:space:]]+set[[:space:]]+800[[:space:]]+600[[:space:]]*$/ {removed=1; next}
      {print}
      END {
        if (!dunst_found) print dunst_line
        if (removed) print "# i3-laptop-controls: bindings legacy conflictivos eliminados"
      }
    ' "$I3_CONFIG" > "$cleaned"
    mv "$cleaned" "$I3_CONFIG"
  fi

  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$begin" "$I3_CONFIG"; then
    awk -v begin="$begin" -v end="$end" -v block="$block" '
      $0 == begin {if (!done) {print block; done=1} skip=1; next}
      skip && $0 == end {skip=0; next}
      !skip {print}
    ' "$I3_CONFIG" > "$I3_CONFIG.tmp"
    mv "$I3_CONFIG.tmp" "$I3_CONFIG"
  else
    printf '\n%s\n' "$block" >> "$I3_CONFIG"
  fi
}

main() {
  parse_args "$@"
  init_logging
  require_linux
  echo "═══ Controles i3 para laptop ═══"
  install_packages
  install_helper scripts/hardware/notify_microphone_linux.sh microphone-notify.sh
  install_helper scripts/hardware/notify_brightness_linux.sh brightness-notify.sh
  install_helper scripts/hardware/notify_kbd_brightness_linux.sh kbd-brightness-notify.sh
  install_helper scripts/network/wifi_toggle_linux.sh wifi-toggle.sh
  install_helper scripts/network/flight_mode_toggle_linux.sh flight-mode-toggle.sh
  install_helper scripts/system/rofi_search_linux.sh rofi-search.sh
  install_helper scripts/system/desktop_settings_menu_linux.sh desktop-settings-menu.sh
  install_helper scripts/system/picom_toggle_linux.sh picom-toggle.sh
  install_helper scripts/system/i3_settings_menu_linux.sh i3-settings-menu.sh
  install_helper scripts/system/dunst_smart_start_linux.sh dunst-smart.sh
  install_helper scripts/hardware/test_wacom_pen_linux.sh test-wacom-pen.sh
  if [[ "$ACTION" == plan ]]; then
    bash "$REPO_ROOT/scripts/install/install_kbd_brightness_policy_linux.sh" --plan
  elif [[ "$ACTION" == check ]]; then
    bash "$REPO_ROOT/scripts/install/install_kbd_brightness_policy_linux.sh" --check
  elif [[ "$ACTION" == apply ]]; then
    bash "$REPO_ROOT/scripts/install/install_kbd_brightness_policy_linux.sh" --apply
  fi
  configure_i3
  if [[ "$ACTION" == apply ]]; then
    ok "controles instalados; recarga i3 con Mod4+Shift+r"
  elif [[ "$ACTION" == plan ]]; then
    ok "plan terminado; no se modificó el sistema"
  else
    info "usa --plan para ver cambios o --apply para instalarlos"
  fi
}

main "$@"
