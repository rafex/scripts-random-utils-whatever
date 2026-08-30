#!/usr/bin/env bash
# shellcheck shell=bash
# Instala el perfil Openbox paralelo para la ThinkPad sin reemplazar i3.
set -Eeuo pipefail
umask 077

# Sin argumentos se aplica el perfil, como define la tarea Just. Usa
# --check o --dry-run para inspeccionar sin modificar el sistema.
ACTION="apply"
PROFILE="openbox-thinkpad-x1-yoga-1st"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE_ROOT="$REPO_ROOT/dotfiles/profiles/$PROFILE"
STAMP="$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_openbox_profile_linux.sh --check
  install_openbox_profile_linux.sh --plan
  install_openbox_profile_linux.sh --apply
  install_openbox_profile_linux.sh --dry-run

Sin opciones equivale a --apply. Usa --check para auditar sin cambios.
Instala Openbox y tint2 junto con el perfil paralelo de ThinkPad. No cambia
la sesión predeterminada de LightDM ni modifica el perfil i3.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die "este instalador solo funciona en Linux"
  [[ "$EUID" -ne 0 ]] || die "ejecuta el instalador como rafex, no como root"
  [[ -d "$PROFILE_ROOT" ]] || die "no existe el perfil: $PROFILE_ROOT"
  command -v bash >/dev/null 2>&1 || die "bash no está disponible"
  command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query no está disponible"
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo no está instalado"
    sudo -v
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

show_packages() {
  local package
  local packages=(openbox tint2)
  for package in "${packages[@]}"; do
    if package_installed "$package"; then
      printf '%s=installed\n' "$package"
    else
      printf '%s=missing\n' "$package"
    fi
  done
}

backup_file() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "${target}.bak.${STAMP}"
  info "respaldo creado: ${target}.bak.${STAMP}"
}

install_helper() {
  local source="$1" target_name="$2" source_path="$REPO_ROOT/$1" target="$HOME/.local/bin/$2"
  [[ -f "$source_path" ]] || die "falta el helper: $source"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar $target"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if [[ -f "$target" ]] && cmp -s "$source_path" "$target"; then
    return 0
  fi
  backup_file "$target"
  install -m 0755 "$source_path" "$target"
}

install_openbox_themes() {
  local theme source target
  local source_root="$HOME/.config/rafex/themes"
  local theme_root="$HOME/.themes"
  for theme in paper nord everforest dracula; do
    source="$source_root/$theme/openbox.themerc"
    target="$theme_root/Rafex-${theme^}/openbox-3/themerc"
    [[ -f "$source" ]] || { warn "falta plantilla Openbox: $source"; continue; }
    if [[ "$ACTION" == plan ]]; then
      info "[plan] instalar tema Openbox $theme en $target"
      continue
    fi
    if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
      continue
    fi
    mkdir -p "$(dirname "$target")"
    backup_file "$target"
    install -m 0644 "$source" "$target"
  done
}

install_profile() {
  if [[ "$ACTION" == plan ]]; then
    info "[plan] ejecutar dotfiles/install.sh --profile $PROFILE --dry-run"
    info "[plan] respaldar configuraciones de usuario antes de copiarlas"
    return 0
  fi
  bash "$REPO_ROOT/dotfiles/install.sh" --profile "$PROFILE"
}

install_packages() {
  local packages=(openbox tint2)
  info "Paquetes nuevos del entorno: ${packages[*]}"
  if [[ "$ACTION" == plan ]]; then
    info "[plan] sudo apt-get update"
    info "[plan] sudo apt-get install -y ${packages[*]}"
    return 0
  fi
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

check_profile() {
  local path
  echo '═══ Perfil Openbox ThinkPad ═══'
  printf 'profile=%s\n' "$PROFILE_ROOT"
  show_packages
  for path in "$PROFILE_ROOT/config/openbox/rc.xml" "$PROFILE_ROOT/config/openbox/menu.xml" \
      "$PROFILE_ROOT/config/openbox/autostart" "$PROFILE_ROOT/config/tint2/tint2rc"; do
    if [[ -f "$path" ]]; then
      printf 'source=%s:present\n' "$path"
    else
      printf 'source=%s:missing\n' "$path"
    fi
  done
  if [[ -f "$HOME/.config/openbox/rc.xml" && -f "$HOME/.config/tint2/tint2rc" ]]; then
    ok "configuración Openbox/tint2 instalada"
  else
    warn "configuración Openbox/tint2 aún no está instalada"
  fi
  info 'i3 no se modifica y seguirá siendo la sesión predeterminada de recuperación'
}

main() {
  parse_args "$@"
  require_linux
  case "$ACTION" in
    check)
      check_profile
      ;;
    plan)
      echo '═══ Plan perfil Openbox ThinkPad ═══'
      install_packages
      install_profile
      install_openbox_themes
      ;;
    apply)
      echo '═══ Instalación perfil Openbox ThinkPad ═══'
      install_packages
      install_profile
      local helper
      while IFS=: read -r helper target_name; do
        install_helper "$helper" "$target_name"
      done <<'EOF'
scripts/system/theme_toggle_linux.sh:theme-toggle.sh
scripts/system/dunst_smart_start_linux.sh:dunst-smart.sh
scripts/system/desktop_settings_menu_linux.sh:desktop-settings-menu.sh
scripts/system/rofi_search_linux.sh:rofi-search.sh
scripts/system/picom_toggle_linux.sh:picom-toggle.sh
scripts/system/tint2_status_linux.sh:tint2-status.sh
scripts/hardware/notify_volume_linux.sh:volume-notify.sh
scripts/hardware/notify_microphone_linux.sh:microphone-notify.sh
scripts/hardware/notify_brightness_linux.sh:brightness-notify.sh
scripts/hardware/notify_kbd_brightness_linux.sh:kbd-brightness-notify.sh
scripts/network/wifi_toggle_linux.sh:wifi-toggle.sh
scripts/network/flight_mode_toggle_linux.sh:flight-mode-toggle.sh
scripts/display/screen_projector_linux.sh:screen-projector.sh
scripts/hardware/autorotate_x1_yoga_linux.sh:autorotate-x1-yoga.sh
scripts/hardware/test_wacom_pen_linux.sh:test-wacom-pen.sh
EOF
      install_openbox_themes
      ok 'perfil Openbox instalado; selecciona Openbox manualmente en LightDM'
      ;;
  esac
}

main "$@"
