#!/usr/bin/env bash
set -euo pipefail

# Los comandos polkit/udev suelen vivir en /usr/sbin o /sbin y no siempre
# aparecen en el PATH de una sesión SSH no interactiva.
SYSTEM_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH="$SYSTEM_PATH${PATH:+:$PATH}"

# ─────────────────────────────────────────────────────────────────────────────
# usb_mount_perms_linux.sh
# Diagnostica y corrige permisos para montar/desmontar USB sin sudo en Linux.
# Soporta polkit (>= 0.106, reglas JS), udev y udiskie (auto-montaje en i3).
# ─────────────────────────────────────────────────────────────────────────────

MODE="check"
DRY_RUN=0
LEGACY_UDEV=0
AUTO_CONFIRM=0
USB_PERMS_GROUP="${USB_PERMS_GROUP:-plugdev}"
I3_CONFIG="${I3_CONFIG:-$HOME/.config/i3/config}"
UDISKIE_CONFIG="$HOME/.config/udiskie/config.yml"
POLKIT_RULE="/etc/polkit-1/rules.d/10-udisks2-mount.rules"
UDEV_RULE="/etc/udev/rules.d/99-usb-storage.rules"
TARGET_USER="${SUDO_USER:-${USER:-}}"

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗${RESET} $*"; }
fatal()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}Uso:${RESET}"
  echo "  $0 [opciones]"
  echo
  echo -e "${BOLD}Opciones:${RESET}"
  echo -e "  ${CYAN}--check${RESET}       Diagnostica permisos USB (sin modificar nada, default)"
  echo -e "  ${CYAN}--fix${RESET}         Aplica correcciones (requiere sudo)"
  echo -e "  ${CYAN}--dry-run${RESET}     Muestra los cambios sin aplicarlos"
  echo -e "  ${CYAN}--legacy-udev${RESET} Instala regla udev para acceso directo a bloques USB"
  echo -e "  ${CYAN}--no-legacy-udev${RESET} No instala la regla udev (default)"
  echo -e "  ${CYAN}--yes${RESET}         No solicita confirmación adicional"
  echo -e "  ${CYAN}-h, --help${RESET}   Mostrar esta ayuda"
  echo
  echo -e "${BOLD}Variables de entorno:${RESET}"
  echo -e "  ${CYAN}USB_PERMS_GROUP${RESET}   Grupo para permisos de montaje (default: plugdev)"
  echo -e "  ${CYAN}I3_CONFIG${RESET}         Ruta al config de i3 (default: ~/.config/i3/config)"
  echo
  echo -e "${BOLD}Ejemplo:${RESET}"
  echo "  $0 --check"
  echo "  $0 --fix"
  echo "  $0 --dry-run --fix"
  echo "  USB_PERMS_GROUP=plugdev $0 --fix"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)  MODE="check"; shift ;;
    --fix)    MODE="fix"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --legacy-udev) LEGACY_UDEV=1; shift ;;
    --no-legacy-udev) LEGACY_UDEV=0; shift ;;
    --yes) AUTO_CONFIRM=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "argumento desconocido: $1"; echo; usage; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Helpers para modo dry-run
# ─────────────────────────────────────────────────────────────────────────────
run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] $*"
    return 0
  fi
  "$@"
}

sudo_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] sudo $*"
    return 0
  fi
  sudo "$@"
}

write_file_dry() {
  local dest="$1" content="$2" desc="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] escribir $desc → ${BOLD}$dest${RESET}"
    echo "$content"
    echo
    return 0
  fi
  if [[ -w "$(dirname "$dest")" ]]; then
    echo "$content" > "$dest"
  else
    echo "$content" | sudo tee "$dest" > /dev/null
  fi
}

backup_user_file() {
  local file="$1"
  local destination

  [[ -f "$file" ]] || return 0
  destination="${file}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -a "$file" "$destination"
  info "Respaldo de configuración: ${BOLD}$destination${RESET}"
}

backup_root_file() {
  local file="$1"
  local backup

  [[ -e "$file" ]] || return 0
  backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
  sudo cp -a -- "$file" "$backup"
  info "Respaldo de configuración del sistema: ${BOLD}$backup${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar OS (solo Linux)
# ─────────────────────────────────────────────────────────────────────────────
check_os() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    fatal "este script solo funciona en Linux."
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar grupo
# ─────────────────────────────────────────────────────────────────────────────
check_groups() {
  echo -e "\n${BOLD}${CYAN}═══ Grupos del usuario ═══${RESET}"
  if command -v id &>/dev/null && id | grep -qw "$USB_PERMS_GROUP"; then
    success "Usuario en grupo ${BOLD}$USB_PERMS_GROUP${RESET}"
  else
    error "Usuario NO está en ${BOLD}$USB_PERMS_GROUP${RESET}"
    GROUP_FIX_NEEDED=1
  fi

  if getent group "$USB_PERMS_GROUP" >/dev/null 2>&1; then
    info "Grupo ${BOLD}$USB_PERMS_GROUP${RESET} existe: $(getent group "$USB_PERMS_GROUP" | cut -d: -f4)"
  else
    error "Grupo ${BOLD}$USB_PERMS_GROUP${RESET} no existe"
    GROUP_FIX_NEEDED=1
  fi
}

fix_groups() {
  if [[ "${GROUP_FIX_NEEDED:-0}" -eq 0 ]]; then
    info "Grupo ${BOLD}$USB_PERMS_GROUP${RESET}: ya correcto, omitiendo."
    return
  fi
  info "Agregando usuario ${BOLD}$TARGET_USER${RESET} al grupo ${BOLD}$USB_PERMS_GROUP${RESET}..."
  sudo_cmd usermod -aG "$USB_PERMS_GROUP" "$TARGET_USER"
  success "Usuario agregado a ${BOLD}$USB_PERMS_GROUP${RESET}. Requiere cerrar sesión y volver a entrar."
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar udisks2 / udiskie
# ─────────────────────────────────────────────────────────────────────────────
check_udisks2() {
  echo -e "\n${BOLD}${CYAN}═══ Herramientas de montaje ═══${RESET}"
  if command -v udisksctl &>/dev/null; then
    success "udisksctl disponible (udisks2)"
  else
    error "udisksctl NO disponible. Instala: sudo apt install udisks2"
    UDISKS2_MISSING=1
  fi

  if command -v udiskie &>/dev/null; then
    success "udiskie disponible"
  else
    warn "udiskie NO disponible. Auto-montaje no funcionará. Instala: sudo apt install udiskie"
    UDISKIE_MISSING=1
  fi

  if command -v pmount &>/dev/null; then
    info "pmount disponible (alternativa sin polkit)"
  fi

  if command -v udevil &>/dev/null; then
    info "udevil disponible (alternativa sin polkit)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar polkit
# ─────────────────────────────────────────────────────────────────────────────
check_polkit() {
  echo -e "\n${BOLD}${CYAN}═══ Polkit ═══${RESET}"

  if command -v pkaction &>/dev/null; then
    local ver
    ver="$(pkaction --version 2>/dev/null | awk '{print $NF}')"
    info "polkit versión: ${BOLD}$ver${RESET}"

    if [[ "$ver" -ge 106 ]]; then
      success "polkit >= 0.106 (usa reglas JS en rules.d)"
    else
      warn "polkit < 0.106 (usa archivos .pkla). Las reglas JS pueden no funcionar."
    fi
  else
    error "pkaction no encontrado. polkit no está instalado."
    POLKIT_MISSING=1
  fi

  local agent_found=0
  if pgrep -x polkitd >/dev/null 2>&1; then
    success "polkitd corriendo"
  else
    error "polkitd NO está corriendo"
  fi

  for agent in polkit-gnome-authentication-agent-1 \
              polkit-kde-authentication-agent-1 \
              polkit-ukui-authentication-agent-1 \
              lxpolkit \
              mate-polkit \
              xfce-polkit; do
    if pgrep -f "$agent" >/dev/null 2>&1; then
      success "Agente de autenticación corriendo: ${BOLD}$agent${RESET}"
      agent_found=1
    fi
  done

  if [[ "$agent_found" -eq 0 ]]; then
    warn "No se detectó agente de polkit. Sin él, los prompts de auth fallarán o serán en terminal."
  fi

  if [[ -f "$POLKIT_RULE" ]]; then
    success "Regla polkit udisks2 presente: ${BOLD}$POLKIT_RULE${RESET}"
  else
    error "Regla polkit udisks2 NO existe: ${BOLD}$POLKIT_RULE${RESET}"
    POLKIT_RULE_NEEDED=1
  fi
}

fix_polkit_rule() {
  if [[ "${POLKIT_RULE_NEEDED:-0}" -eq 0 ]]; then
    info "Regla polkit udisks2: ya existe, omitiendo."
    return
  fi

  local content
  content='polkit.addRule(function(action, subject) {
    var allowed = [
        "org.freedesktop.udisks2.filesystem-mount",
        "org.freedesktop.udisks2.filesystem-unmount-others",
        "org.freedesktop.udisks2.eject-media",
        "org.freedesktop.udisks2.power-off-drive"
    ];
    if (subject.local && subject.active && subject.isInGroup("'"$USB_PERMS_GROUP"'") &&
        allowed.indexOf(action.id) >= 0) {
        return polkit.Result.YES;
    }
});'

  info "Creando regla polkit: ${BOLD}$POLKIT_RULE${RESET}"
  [[ "$DRY_RUN" -eq 1 ]] || backup_root_file "$POLKIT_RULE"
  write_file_dry "$POLKIT_RULE" "$content" "regla polkit"
  sudo_cmd chmod 644 "$POLKIT_RULE"
  success "Regla polkit creada."

  if [[ "$DRY_RUN" -eq 0 ]]; then
    info "Reiniciando polkitd..."
    sudo_cmd systemctl restart polkit 2>/dev/null || sudo_cmd systemctl reload polkit 2>/dev/null || true
    success "polkitd reiniciado."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar udev
# ─────────────────────────────────────────────────────────────────────────────
check_udev() {
  local -a block_devices rules_file

  echo -e "\n${BOLD}${CYAN}═══ Reglas udev para USB ═══${RESET}"

  if [[ -f "$UDEV_RULE" ]]; then
    success "Regla udev USB presente: ${BOLD}$UDEV_RULE${RESET}"
  else
    warn "Regla udev USB NO existe: ${BOLD}$UDEV_RULE${RESET}"
    UDEV_RULE_NEEDED=1
  fi

  echo
  info "Permisos de nodos de dispositivo (discos USB):"
  shopt -s nullglob
  block_devices=(/dev/sd?)
  if ((${#block_devices[@]} > 0)); then
    for dev in "${block_devices[@]}"; do
      local perms owner group
      read -r perms owner group _ < <(stat -c '%A %U %G %n' "$dev")
      if [[ "$group" == "$USB_PERMS_GROUP" ]]; then
        info "  ${BOLD}$dev${RESET}  $perms  $owner:${BOLD}$group${RESET}"
      else
        warn "  ${BOLD}$dev${RESET}  $perms  $owner:$group ${YELLOW}(grupo esperado: $USB_PERMS_GROUP)${RESET}"
      fi
    done
  else
    info "  No se detectaron discos /dev/sd? (puede ser normal sin USB conectado)"
  fi

  echo
  info "Reglas en /etc/udev/rules.d/:"
  rules_file=(/etc/udev/rules.d/*.rules)
  if ((${#rules_file[@]} > 0)); then
    for f in "${rules_file[@]}"; do
      info "  - $(basename "$f")"
    done
  else
    info "  (vacío)"
  fi
}

fix_udev_rule() {
  if [[ "$LEGACY_UDEV" -eq 0 ]]; then
    info "Regla udev legacy omitida; udisks2/polkit gestionan el montaje."
    return
  fi
  if [[ "${UDEV_RULE_NEEDED:-0}" -eq 0 ]]; then
    info "Regla udev USB: ya existe, omitiendo."
    return
  fi

  local content
  content='# Otorga permisos de lectura/escritura a dispositivos de bloque USB
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", GROUP="'"$USB_PERMS_GROUP"'", MODE="0660"
'

  info "Creando regla udev: ${BOLD}$UDEV_RULE${RESET}"
  [[ "$DRY_RUN" -eq 1 ]] || backup_root_file "$UDEV_RULE"
  write_file_dry "$UDEV_RULE" "$content" "regla udev"
  sudo_cmd chmod 644 "$UDEV_RULE"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    info "Recargando reglas udev..."
    sudo_cmd udevadm control --reload-rules
    info "Aplicando reglas a dispositivos existentes..."
    sudo_cmd udevadm trigger --subsystem-match=block --attr-match=id_bus=usb 2>/dev/null || true
    success "Reglas udev recargadas."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar fstab
# ─────────────────────────────────────────────────────────────────────────────
check_fstab() {
  echo -e "\n${BOLD}${CYAN}═══ fstab ═══${RESET}"
  local entries
  entries="$(grep -v '^#' /etc/fstab 2>/dev/null | grep -v '^$' || true)"
  if [[ -z "$entries" ]]; then
    info "fstab sin entradas relevantes."
    return
  fi
  echo "$entries" | while read -r line; do
    info "  $line"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar sesión (logind / XDG)
# ─────────────────────────────────────────────────────────────────────────────
check_session() {
  echo -e "\n${BOLD}${CYAN}═══ Sesión y logind ═══${RESET}"

  if command -v loginctl &>/dev/null; then
    local sid="${XDG_SESSION_ID:-}"
    if [[ -n "$sid" ]]; then
      local seat remote active
      seat="$(loginctl show-session "$sid" -p Seat 2>/dev/null | cut -d= -f2)"
      remote="$(loginctl show-session "$sid" -p Remote 2>/dev/null | cut -d= -f2)"
      active="$(loginctl show-session "$sid" -p Active 2>/dev/null | cut -d= -f2)"
      if [[ "$active" == "yes" && "$remote" == "no" ]]; then
        success "Sesión activa y local (seat=$seat). polkit reconocerá la sesión."
      elif [[ "$remote" == "yes" ]]; then
        warn "Sesión remota (SSH). polkit requiere sesión local activa."
      else
        warn "Sesión: Active=$active, Remote=$remote — puede que polkit no reconozca la sesión."
      fi
    fi

    echo
    info "Sesiones de logind:"
    loginctl list-sessions --no-legend 2>/dev/null | while read -r line; do
      info "  $line"
    done
  fi

  echo
  if [[ -z "${XDG_CURRENT_DESKTOP:-}" ]]; then
    warn "XDG_CURRENT_DESKTOP no está definido."
  else
    info "XDG_CURRENT_DESKTOP=${BOLD}${XDG_CURRENT_DESKTOP}${RESET}"
  fi
  if [[ -z "${XDG_SESSION_DESKTOP:-}" ]]; then
    warn "XDG_SESSION_DESKTOP no está definido."
  else
    info "XDG_SESSION_DESKTOP=${BOLD}${XDG_SESSION_DESKTOP}${RESET}"
  fi
  if [[ -z "${XDG_SESSION_TYPE:-}" ]]; then
    warn "XDG_SESSION_TYPE no está definido."
  else
    info "XDG_SESSION_TYPE=${BOLD}${XDG_SESSION_TYPE}${RESET}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar udiskie en ejecución y config
# ─────────────────────────────────────────────────────────────────────────────
check_udiskie() {
  echo -e "\n${BOLD}${CYAN}═══ udiskie (auto-montaje) ═══${RESET}"

  if pgrep -x udiskie >/dev/null 2>&1; then
    success "udiskie está corriendo (auto-montaje activo)"
  else
    error "udiskie NO está corriendo (no hay auto-montaje)"
    UDISKIE_NOT_RUNNING=1
  fi

  if [[ -f "$UDISKIE_CONFIG" ]]; then
    if grep -qE '^[[:space:]]*-[[:space:]]*all[[:space:]]*:' "$UDISKIE_CONFIG"; then
      warn "Config de udiskie contiene la opción obsoleta 'all'"
      UDISKIE_CONFIG_NEEDED=1
      UDISKIE_CONFIG_INVALID=1
    else
      success "Config de udiskie presente: ${BOLD}$UDISKIE_CONFIG${RESET}"
    fi
  else
    warn "No hay config de udiskie en ${BOLD}$UDISKIE_CONFIG${RESET}"
    UDISKIE_CONFIG_NEEDED=1
  fi

  if [[ -f "$I3_CONFIG" ]]; then
    if grep -q "^[^#]*exec.*udiskie" "$I3_CONFIG" 2>/dev/null; then
      success "udiskie configurado en i3 (auto-inicio activo)"
    else
      # Check if it's there but commented
      if grep -q "#exec.*udiskie" "$I3_CONFIG" 2>/dev/null; then
        warn "Línea de udiskie en i3 está COMENTADA"
        UDISKIE_I3_COMMENTED=1
      else
        warn "udiskie NO configurado en i3 (no hay auto-inicio)"
        UDISKIE_I3_MISSING=1
      fi
    fi
  else
    info "No se encontró ${BOLD}$I3_CONFIG${RESET} (¿usas i3?)"
    NO_I3=1
  fi
}

fix_udiskie() {
  if [[ "${NO_I3:-0}" -eq 1 ]]; then
    info "Sin config de i3 detectado. Si usas otro WM, configura udiskie manualmente:"
    info "  Añade 'udiskie --tray &' a tu gestor de ventanas."
    return
  fi

  if [[ "${UDISKIE_NOT_RUNNING:-0}${UDISKIE_I3_COMMENTED:-0}${UDISKIE_I3_MISSING:-0}" == "000" ]]; then
    info "udiskie en i3: ya configurado, omitiendo."
  else
    local udiskie_line="exec --no-startup-id udiskie --tray"
    if grep -qE '^[[:space:]]*exec(_always)?[^#]*udiskie[^#]*--tray' "$I3_CONFIG" 2>/dev/null; then
      info "Línea de udiskie ya presente en i3 config."
      if [[ "${UDISKIE_I3_COMMENTED:-0}" -eq 1 ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          info "[dry-run] Descomentar línea de udiskie en ${BOLD}$I3_CONFIG${RESET}"
        else
          sed -i "s|^#exec --no-startup-id udiskie|exec --no-startup-id udiskie|" "$I3_CONFIG"
          success "Línea de udiskie descomentada en i3 config."
        fi
      fi
    else
      info "Añadiendo udiskie al i3 config..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] Añadir '$udiskie_line' a ${BOLD}$I3_CONFIG${RESET}"
      else
        echo "$udiskie_line" >> "$I3_CONFIG"
        success "udiskie añadido a i3 config."
      fi
      # Also uncomment the dbus-update-activation-environment line for proper session registration
      if grep -q "#exec.*dbus-update-activation-environment.*XDG_CURRENT_DESKTOP" "$I3_CONFIG" 2>/dev/null; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          info "[dry-run] Descomentar línea dbus-update-activation-environment en i3 config"
        else
          sed -i 's|^#exec --no-startup-id sh.*dbus-update-activation-environment.*|exec --no-startup-id sh -c '"'"'export XDG_CURRENT_DESKTOP=i3; export XDG_SESSION_DESKTOP=i3; export DESKTOP_SESSION=i3; dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION'"'"'|' "$I3_CONFIG"
          success "Línea dbus-update-activation-environment descomentada en i3 config."
        fi
      fi
    fi
  fi

  if [[ "${UDISKIE_CONFIG_NEEDED:-0}" -eq 1 ]]; then
    local config_content
    config_content='# Configuración de udiskie para auto-montaje de USB
program_options:
  tray: auto           # auto: solo muestra icono si hay dispositivos
  automount: true      # auto-montar al insertar
  notify: true         # notificaciones de montaje/desmontaje

device_config:
  - device_file: /dev/sda*
    ignore: true       # ignorar disco de sistema
  - device_file: /dev/nvme*
    ignore: true       # ignorar NVMe del sistema
  - device_file: /dev/mmcblk*
    ignore: true       # ignorar SD interna si aplica

'
    info "Creando config de udiskie: ${BOLD}$UDISKIE_CONFIG${RESET}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "[dry-run] Escribir config en $UDISKIE_CONFIG"
      echo "$config_content"
    else
      mkdir -p "$(dirname "$UDISKIE_CONFIG")"
      backup_user_file "$UDISKIE_CONFIG"
      printf '%s\n' "$config_content" > "$UDISKIE_CONFIG"
      if [[ "${UDISKIE_CONFIG_INVALID:-0}" -eq 1 ]]; then
        success "Config de udiskie reparada."
      else
        success "Config de udiskie creada."
      fi
    fi
  else
    info "Config de udiskie: ya existe, omitiendo."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar acciones polkit disponibles
# ─────────────────────────────────────────────────────────────────────────────
check_polkit_actions() {
  echo -e "\n${BOLD}${CYAN}═══ Acciones polkit de udisks2 ═══${RESET}"

  if ! command -v pkaction &>/dev/null; then
    warn "pkaction no disponible. Saltando verificación de acciones."
    return
  fi

  local actions
  actions="org.freedesktop.udisks2.filesystem-mount
org.freedesktop.udisks2.filesystem-mount-system
org.freedesktop.udisks2.filesystem-mount-other-seat
org.freedesktop.udisks2.filesystem-unmount-others
org.freedesktop.udisks2.encrypted-unlock
org.freedesktop.udisks2.eject-media
org.freedesktop.udisks2.power-off-drive"

  for action in $actions; do
    if ! pkaction --action-id "$action" >/dev/null 2>&1; then
      continue
    fi
    local implicit
    implicit="$(pkaction --verbose --action-id "$action" 2>/dev/null | grep "implicit active:" | awk '{print $NF}')"
    case "$implicit" in
      yes)     success "  $action → active: ${GREEN}yes${RESET} (sin auth)" ;;
      auth_self|auth_admin|auth_admin_keep) error "  $action → active: ${RED}$implicit${RESET} (pide auth)" ;;
      *)       info "  $action → active: $implicit" ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar USB conectados
# ─────────────────────────────────────────────────────────────────────────────
check_usb_devices() {
  echo -e "\n${BOLD}${CYAN}═══ Dispositivos USB conectados ═══${RESET}"

  if command -v lsblk &>/dev/null; then
    info "Dispositivos de bloque:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,TRAN,RM 2>/dev/null | while read -r line; do
      if echo "$line" | grep -qE "usb|RM.*1"; then
        echo -e "  ${BOLD}$line${RESET}"
      else
        info "  $line"
      fi
    done
  else
    info "lsblk no disponible."
  fi

  if command -v udisksctl &>/dev/null; then
    echo
    info "Dispositivos vía udisksctl:"
    local dump line count=0
    dump="$(udisksctl dump 2>/dev/null | grep -E "Device:|IdLabel:|IdType:|Size:|HintAuto:|HintSystem:|HintIgnore:|ConnectionBus:" || true)"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      info "  $line"
      count=$((count + 1))
      ((count >= 40)) && break
    done <<< "$dump"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Resumen final
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
  echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  Resumen del diagnóstico${RESET}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

  local issues=0
  if [[ "${GROUP_FIX_NEEDED:-0}" -eq 1 ]]; then
    error "Grupo $USB_PERMS_GROUP necesita corrección"; issues=$((issues+1))
  fi
  if [[ "${UDISKS2_MISSING:-0}" -eq 1 ]]; then
    error "udisks2 no instalado"; issues=$((issues+1))
  fi
  if [[ "${POLKIT_MISSING:-0}" -eq 1 ]]; then
    error "polkit no instalado"; issues=$((issues+1))
  fi
  if [[ "${UDISKIE_MISSING:-0}" -eq 1 ]]; then
    warn "udiskie no instalado (auto-montaje no funcionará)"
  fi
  if [[ "${POLKIT_RULE_NEEDED:-0}" -eq 1 ]]; then
    error "Regla polkit udisks2 no encontrada"; issues=$((issues+1))
  fi
  if [[ "${UDEV_RULE_NEEDED:-0}" -eq 1 ]]; then
    warn "Regla udev USB no encontrada (mejora opcional)"
  fi
  if [[ "${UDISKIE_NOT_RUNNING:-0}" -eq 1 ]]; then
    warn "udiskie no está corriendo (no hay auto-montaje)"
  fi
  if [[ "${UDISKIE_CONFIG_NEEDED:-0}" -eq 1 ]]; then
    warn "Config de udiskie no encontrada"
  fi

  echo
  if [[ "$issues" -eq 0 ]]; then
    success "No se encontraron problemas críticos."
  else
    warn "Se encontraron ${BOLD}$issues${RESET} problema(s) que requieren corrección."
    echo
    echo -e "  Ejecuta ${CYAN}${BOLD}$0 --fix${RESET} para aplicar las correcciones."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Función principal
# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  USB Mount Permissions — Diagnóstico Linux${RESET}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
  echo -e "  Modo:     ${BOLD}$MODE${RESET}"
  echo -e "  Grupo:    ${BOLD}$USB_PERMS_GROUP${RESET}"
  [[ "$DRY_RUN" -eq 1 ]] && echo -e "  ${YELLOW}Simulación activa (--dry-run)${RESET}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

  check_os

  if [[ "$MODE" == "check" ]]; then
    check_groups
    check_udisks2
    check_polkit
    check_udev
    check_fstab
    check_session
    check_udiskie
    check_polkit_actions
    check_usb_devices
    print_summary
  elif [[ "$MODE" == "fix" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo -e "\n${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
      echo -e "${YELLOW}${BOLD}│  DRY-RUN: no se aplicarán cambios reales          │${RESET}"
      echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
    else
      echo -e "\n${YELLOW}${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
      echo -e "${YELLOW}${BOLD}│  Se aplicarán cambios al sistema.                  │${RESET}"
      echo -e "${YELLOW}${BOLD}│  Se requiere sudo para polkit, udev y systemctl.   │${RESET}"
      echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
      echo
      if [[ "$AUTO_CONFIRM" -eq 0 ]]; then
        read -rp "$(echo -e "${YELLOW}${BOLD}Presiona Enter para continuar o Ctrl+C para cancelar...${RESET}")"
      fi
      if ! sudo -v; then
        fatal "no se pudo validar sudo"
        exit 1
      fi
    fi

    # Ejecutar diagnósticos primero (las check_* setean las variables FIX_NEEDED)
    check_groups
    check_udisks2
    check_polkit
    check_udev
    check_fstab
    check_session
    check_udiskie
    check_polkit_actions
    check_usb_devices

    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Aplicando correcciones...${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    fix_groups
    fix_polkit_rule
    fix_udev_rule
    fix_udiskie

    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Correcciones aplicadas${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      warn "Modo dry-run: no se aplicaron cambios reales."
      warn "Ejecuta ${BOLD}$0 --fix${RESET} sin --dry-run para aplicar."
    else
      success "Polkit: regla udisks2 activa (sin auth para plugdev)."
      if [[ "$LEGACY_UDEV" -eq 1 ]]; then
        success "udev: regla USB activa (permisos de nodos)."
      else
        info "udev legacy: omitido; no se amplió acceso directo a dispositivos de bloque."
      fi
      success "udiskie: configurado en i3 y con archivo de configuración."
      echo
      warn "${BOLD}IMPORTANTE:${RESET} cierra sesión y vuelve a entrar para que los cambios surtan efecto."
      echo "  O bien ejecuta en esta sesión:"
      echo "    $ udiskie --tray &"
      echo "    $ udisksctl mount -b /dev/sdXY   # probar montaje"
    fi
  fi
}

main
