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

packages=(rofi pavucontrol network-manager network-manager-gnome nm-connection-editor
  blueman bluez arandr xev xinput libnotify-bin brightnessctl rfkill gnome-disk-utility
  thunar xdg-utils)

install_packages() {
  info "Paquetes: ${packages[*]}"
  [[ "$ACTION" == plan ]] && { info "[plan] sudo apt-get update"; info "[plan] sudo apt-get install -y ${packages[*]}"; return; }
  [[ "$ACTION" == apply ]] || return
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
  [[ "$ACTION" == apply ]] || return
  mkdir -p "$HOME/.local/bin"
  if [[ -e "$target" && ! -L "$target" ]]; then
    cp -a "$target" "$target.bak.$BACKUP_STAMP"
  fi
  install -m 755 "$REPO_ROOT/$source" "$target"
}

configure_i3() {
  local begin='# >>> i3-laptop-controls managed >>>'
  local end='# <<< i3-laptop-controls managed <<<'
  local block
  block="$begin
bindsym XF86AudioMicMute exec --no-startup-id ~/.local/bin/microphone-notify.sh toggle
bindsym XF86WLAN exec --no-startup-id ~/.local/bin/wifi-toggle.sh toggle
bindsym XF86RFKill exec --no-startup-id ~/.local/bin/flight-mode-toggle.sh toggle
bindsym XF86Search exec --no-startup-id ~/.local/bin/rofi-search.sh apps
bindsym XF86Explorer exec --no-startup-id ~/.local/bin/rofi-search.sh browser
bindsym XF86WakeUp exec --no-startup-id ~/.local/bin/i3-settings-menu.sh power
bindsym XF86Tools exec --no-startup-id ~/.local/bin/i3-settings-menu.sh
$end"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] actualizar bloque administrado en $I3_CONFIG"
    return
  fi
  [[ "$ACTION" == apply ]] || return
  mkdir -p "$(dirname "$I3_CONFIG")"
  if [[ -f "$I3_CONFIG" ]]; then cp -a "$I3_CONFIG" "$I3_CONFIG.bak.$BACKUP_STAMP"; fi
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
  require_linux
  echo "═══ Controles i3 para laptop ═══"
  install_packages
  install_helper scripts/hardware/notify_microphone_linux.sh microphone-notify.sh
  install_helper scripts/network/wifi_toggle_linux.sh wifi-toggle.sh
  install_helper scripts/network/flight_mode_toggle_linux.sh flight-mode-toggle.sh
  install_helper scripts/system/rofi_search_linux.sh rofi-search.sh
  install_helper scripts/system/i3_settings_menu_linux.sh i3-settings-menu.sh
  install_helper scripts/hardware/test_wacom_pen_linux.sh test-wacom-pen.sh
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
