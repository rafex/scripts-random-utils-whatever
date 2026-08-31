#!/usr/bin/env bash
# install_thinkpad_backgrounds_linux.sh v1.0.0
# Aplica los fondos del perfil ThinkPad a i3, GRUB y LightDM.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

readonly VERSION="v1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly PROFILE_ROOT="${REPO_ROOT}/dotfiles/profiles/thinkpad-x1-yoga-1st"
readonly SOURCE_ROOT="${PROFILE_ROOT}/assets/backgrounds"
readonly USER_ROOT="${HOME}/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds"
readonly USER_BACKUP_ROOT="${HOME}/.local/state/rafex/backups/thinkpad-backgrounds"
readonly I3_CONFIG="${HOME}/.config/i3/config"
readonly GRUB_CONFIG="/etc/default/grub"
readonly GRUB_ASSET="/boot/grub/rafex-thinkpad-boot.png"
readonly LIGHTDM_ASSET="/usr/local/share/backgrounds/rafex/rafex-thinkpad-login.png"
readonly LIGHTDM_CONFIG="/etc/lightdm/lightdm-gtk-greeter.conf"
readonly SYSTEM_BACKUP_ROOT="/var/backups/rafex-thinkpad-backgrounds"
readonly I3_START="# BEGIN rafex thinkpad backgrounds"
readonly I3_END="# END rafex thinkpad backgrounds"
readonly GRUB_START="# BEGIN rafex thinkpad grub background"
readonly GRUB_END="# END rafex thinkpad grub background"
readonly LIGHTDM_START="# BEGIN rafex thinkpad lightdm background"
readonly LIGHTDM_END="# END rafex thinkpad lightdm background"

ACTION="check"
STAGE="desktop"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
TEMP_FILES=()
USER_BACKUP_DIR="${USER_BACKUP_ROOT}/${TIMESTAMP}"

info() { printf '→ %s\n' "$*"; }
success() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local item
  if ((${#TEMP_FILES[@]} > 0)); then
    for item in "${TEMP_FILES[@]}"; do
      [[ -e "${item}" ]] && rm -rf -- "${item}"
    done
  fi
}
trap cleanup EXIT

register_temp() {
  TEMP_FILES+=("$1")
}

usage() {
  cat <<'EOF'
Uso: install_thinkpad_backgrounds_linux.sh [--check|--plan|--apply|--status]
       [--stage desktop|grub|login|all]

Etapas:
  desktop  Copia los cinco fondos al usuario y configura el fondo de i3.
  grub     Instala el fondo en GRUB y ejecuta update-grub.
  login    Instala el fondo para lightdm-gtk-greeter sin reiniciar LightDM.
  all      Ejecuta desktop, grub y login.

--dry-run es alias de --plan.
EOF
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "este instalador solo funciona en Linux"
}

require_user() {
  (( EUID != 0 )) || die "ejecuta el instalador como usuario normal; sudo se solicita solo cuando corresponde"
}

validate_stage() {
  case "$STAGE" in
    desktop|grub|login|all) ;;
    *) die "etapa no válida: ${STAGE}; usa desktop, grub, login o all" ;;
  esac
}

stage_has() {
  local requested="$1"
  local selected="$2"
  [[ "$selected" == "all" || "$selected" == "$requested" ]]
}

validate_sources() {
  local names=(
    rafex-thinkpad-boot.png
    rafex-thinkpad-desktop.png
    rafex-thinkpad-login.png
    rafex-thinkpad-projector.png
    rafex-thinkpad-tablet.png
  )
  local name
  local failures=0

  for name in "${names[@]}"; do
    if [[ ! -s "${SOURCE_ROOT}/${name}" ]]; then
      warn "falta el fondo del perfil: ${SOURCE_ROOT}/${name}"
      failures=$((failures + 1))
    fi
  done
  (( failures == 0 ))
}

backup_user_file() {
  local file="$1"
  local label
  label="$(basename -- "$file")"
  [[ -f "$file" ]] || return 0
  mkdir -p -- "$USER_BACKUP_DIR"
  cp -p -- "$file" "${USER_BACKUP_DIR}/${label}.bak"
  info "respaldo de usuario: ${USER_BACKUP_DIR}/${label}.bak"
}

backup_system_file() {
  local file="$1"
  local label
  label="$(basename -- "$file")"
  sudo install -d -m 0700 -- "$SYSTEM_BACKUP_ROOT"
  if sudo test -e "$file"; then
    sudo cp -p -- "$file" "${SYSTEM_BACKUP_ROOT}/${label}.${TIMESTAMP}.bak"
    printf '%s\n' "${SYSTEM_BACKUP_ROOT}/${label}.${TIMESTAMP}.bak"
  fi
}

strip_managed_block() {
  local file="$1"
  local start="$2"
  local end="$3"

  if [[ -f "$file" ]]; then
    awk -v start="$start" -v end="$end" '
      $0 == start { inside = 1; next }
      $0 == end { inside = 0; next }
      !inside { print }
    ' "$file"
  fi
}

copy_user_assets() {
  local names=(
    rafex-thinkpad-boot.png
    rafex-thinkpad-desktop.png
    rafex-thinkpad-login.png
    rafex-thinkpad-projector.png
    rafex-thinkpad-tablet.png
  )
  local name source target temporary

  mkdir -p -- "$USER_ROOT"
  mkdir -p -- "$USER_BACKUP_DIR"
  info "instalando fondos del perfil en ${USER_ROOT}"

  for name in "${names[@]}"; do
    source="${SOURCE_ROOT}/${name}"
    target="${USER_ROOT}/${name}"
    if [[ -e "$target" || -L "$target" ]]; then
      cp -p -- "$target" "${USER_BACKUP_DIR}/${name}.bak"
    fi
    temporary="$(mktemp "${USER_ROOT}/.${name}.XXXXXX")"
    register_temp "$temporary"
    install -m 0644 -- "$source" "$temporary"
    mv -f -- "$temporary" "$target"
    success "fondo disponible: ${target}"
  done
}

configure_i3_background() {
  local temporary
  [[ -f "$I3_CONFIG" ]] || {
    warn "no existe ${I3_CONFIG}; copia primero el perfil i3"
    return 0
  }

  backup_user_file "$I3_CONFIG"
  temporary="$(mktemp "${I3_CONFIG}.XXXXXX")"
  register_temp "$temporary"
  strip_managed_block "$I3_CONFIG" "$I3_START" "$I3_END" > "$temporary"
  cat >> "$temporary" <<'EOF'

# BEGIN rafex thinkpad backgrounds
exec_always --no-startup-id sh -c 'if command -v feh >/dev/null 2>&1 && [ -f "$HOME/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/rafex-thinkpad-desktop.png" ]; then feh --no-fehbg --bg-scale "$HOME/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/rafex-thinkpad-desktop.png"; fi'
# END rafex thinkpad backgrounds
EOF
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$I3_CONFIG"
  success "bloque de fondo administrado instalado en ${I3_CONFIG}"
}

reload_i3_if_local() {
  if [[ -n "${DISPLAY:-}" ]] && command -v i3-msg >/dev/null 2>&1; then
    if i3-msg reload >/dev/null 2>&1; then
      success "i3 recargado"
    else
      warn "no se pudo recargar i3; ejecuta: i3-msg reload"
    fi
  else
    info "sesión gráfica no disponible; ejecuta manualmente: i3-msg reload"
  fi
}

install_system_asset() {
  local source="$1"
  local target="$2"
  local parent
  parent="$(dirname -- "$target")"
  backup_system_file "$target" >/dev/null
  sudo install -d -m 0755 -- "$parent"
  sudo install -m 0644 -- "$source" "$target"
  success "fondo de sistema instalado: ${target}"
}

configure_grub_background() {
  local temporary cleaned backup
  [[ -f "$GRUB_CONFIG" ]] || die "no existe ${GRUB_CONFIG}"
  command -v update-grub >/dev/null 2>&1 || die "no se encontró update-grub"

  backup="$(backup_system_file "$GRUB_CONFIG")"
  temporary="$(mktemp)"
  cleaned="$(mktemp)"
  register_temp "$temporary"
  register_temp "$cleaned"

  sudo cat -- "$GRUB_CONFIG" | tee "$temporary" >/dev/null
  strip_managed_block "$temporary" "$GRUB_START" "$GRUB_END" > "$cleaned"

  if grep -Eq '^[[:space:]]*GRUB_BACKGROUND=' "$cleaned"; then
    die "GRUB_BACKGROUND no administrado ya existe; revísalo antes de reemplazarlo"
  fi

  cat >> "$cleaned" <<EOF

${GRUB_START}
GRUB_BACKGROUND="${GRUB_ASSET}"
${GRUB_END}
EOF
  install_system_asset "${SOURCE_ROOT}/rafex-thinkpad-boot.png" "$GRUB_ASSET"
  sudo install -m 0644 -- "$cleaned" "$GRUB_CONFIG"

  if ! sudo update-grub; then
    warn "update-grub falló; restaurando ${GRUB_CONFIG}"
    [[ -n "$backup" ]] && sudo install -m 0644 -- "$backup" "$GRUB_CONFIG"
    die "no se pudo actualizar GRUB"
  fi
  success "GRUB actualizado con el fondo ThinkPad"
}

lightdm_is_available() {
  [[ -d "/etc/lightdm" ]] || return 1
  command -v lightdm-gtk-greeter >/dev/null 2>&1 ||
    [[ -f "$LIGHTDM_CONFIG" ]]
}

render_lightdm_config() {
  local source="$1"
  local destination="$2"
  awk -v start="$LIGHTDM_START" -v end="$LIGHTDM_END" -v image="$LIGHTDM_ASSET" '
    $0 == start { managed = 1; next }
    $0 == end { managed = 0; next }
    managed { next }
    /^\[[^]]+\]/ {
      if (in_greeter && !written) {
        print start
        print "# Fondo administrado por el perfil ThinkPad."
        print "background=" image
        print end
        written = 1
      }
      in_greeter = ($0 == "[greeter]")
      print
      next
    }
    in_greeter && $0 ~ /^[[:space:]]*background[[:space:]]*=/ {
      if (!written) {
        print start
        print "# Fondo administrado por el perfil ThinkPad."
        print "background=" image
        print end
        written = 1
      }
      next
    }
    { print }
    END {
      if (in_greeter && !written) {
        print start
        print "# Fondo administrado por el perfil ThinkPad."
        print "background=" image
        print end
        written = 1
      }
      if (!written) {
        print ""
        print "[greeter]"
        print start
        print "# Fondo administrado por el perfil ThinkPad."
        print "background=" image
        print end
      }
    }
  ' "$source" > "$destination"
}

configure_login_background() {
  local temporary cleaned
  if ! lightdm_is_available; then
    warn "LightDM o lightdm-gtk-greeter no está instalado; se omite la etapa login"
    return 0
  fi

  install_system_asset "${SOURCE_ROOT}/rafex-thinkpad-login.png" "$LIGHTDM_ASSET"
  backup_system_file "$LIGHTDM_CONFIG" >/dev/null
  temporary="$(mktemp)"
  cleaned="$(mktemp)"
  register_temp "$temporary"
  register_temp "$cleaned"

  if sudo test -f "$LIGHTDM_CONFIG"; then
    sudo cat -- "$LIGHTDM_CONFIG" | tee "$temporary" >/dev/null
  else
    : > "$temporary"
  fi
  render_lightdm_config "$temporary" "$cleaned"
  sudo install -d -m 0755 -- "$(dirname -- "$LIGHTDM_CONFIG")"
  sudo install -m 0644 -- "$cleaned" "$LIGHTDM_CONFIG"
  success "LightDM preparado; no se reinició el gestor de sesiones"
}

show_check() {
  local failures=0
  local target
  validate_sources || failures=$((failures + 1))

  if stage_has desktop "$STAGE"; then
    for target in rafex-thinkpad-boot.png rafex-thinkpad-desktop.png rafex-thinkpad-login.png rafex-thinkpad-projector.png rafex-thinkpad-tablet.png; do
      if [[ -s "${USER_ROOT}/${target}" ]]; then
        success "fondo de usuario presente: ${target}"
      else
        warn "fondo de usuario ausente: ${USER_ROOT}/${target}"
        failures=$((failures + 1))
      fi
    done
    if [[ -f "$I3_CONFIG" ]] && grep -qF "$I3_START" "$I3_CONFIG"; then
      success "bloque de fondo i3 presente"
    else
      warn "bloque de fondo i3 ausente"
      failures=$((failures + 1))
    fi
  fi

  if stage_has grub "$STAGE"; then
    if [[ -f "$GRUB_ASSET" ]] && grep -qF 'GRUB_BACKGROUND="/boot/grub/rafex-thinkpad-boot.png"' "$GRUB_CONFIG" 2>/dev/null; then
      success "fondo GRUB y configuración presentes"
    else
      warn "fondo GRUB o GRUB_BACKGROUND ausente"
      failures=$((failures + 1))
    fi
  fi

  if stage_has login "$STAGE"; then
    if [[ -f "$LIGHTDM_ASSET" ]] && grep -qF 'background=/usr/local/share/backgrounds/rafex/rafex-thinkpad-login.png' "$LIGHTDM_CONFIG" 2>/dev/null; then
      success "fondo LightDM y configuración presentes"
    else
      warn "fondo LightDM o configuración ausente"
      failures=$((failures + 1))
    fi
  fi

  (( failures == 0 ))
}

show_plan() {
  validate_sources || die "faltan fondos en el perfil versionado"
  printf '═══ Plan de fondos ThinkPad (%s) ═══\n' "$STAGE"
  if stage_has desktop "$STAGE"; then
    info "[plan] copiar cinco fondos a ${USER_ROOT}"
    info "[plan] respaldar y actualizar el bloque administrado de ${I3_CONFIG}"
    info "[plan] recargar i3 solo si existe una sesión gráfica local"
  fi
  if stage_has grub "$STAGE"; then
    info "[plan] respaldar ${GRUB_CONFIG} y ${GRUB_ASSET} en ${SYSTEM_BACKUP_ROOT}"
    info "[plan] escribir GRUB_BACKGROUND y ejecutar sudo update-grub"
    info "[plan] no reiniciar automáticamente"
  fi
  if stage_has login "$STAGE"; then
    info "[plan] respaldar ${LIGHTDM_CONFIG} y el fondo de login"
    info "[plan] configurar lightdm-gtk-greeter sin reiniciar LightDM"
  fi
  warn "no se modificó ningún archivo"
}

show_status() {
  local name
  printf '═══ Estado de fondos ThinkPad ═══\n'
  printf 'perfil: %s\n' "$PROFILE_ROOT"
  printf 'destino usuario: %s\n' "$USER_ROOT"
  for name in rafex-thinkpad-boot.png rafex-thinkpad-desktop.png rafex-thinkpad-login.png rafex-thinkpad-projector.png rafex-thinkpad-tablet.png; do
    if [[ -s "${SOURCE_ROOT}/${name}" ]]; then
      printf 'origen %-33s presente\n' "$name"
    else
      printf 'origen %-33s AUSENTE\n' "$name"
    fi
    if [[ -s "${USER_ROOT}/${name}" ]]; then
      printf 'usuario %-32s presente\n' "$name"
    else
      printf 'usuario %-32s ausente\n' "$name"
    fi
  done
  if [[ -f "$I3_CONFIG" ]] && grep -qF "$I3_START" "$I3_CONFIG"; then
    printf 'i3: bloque administrado presente\n'
  else
    printf 'i3: bloque administrado ausente\n'
  fi
  if [[ -f "$GRUB_CONFIG" ]]; then
    grep -E '^(GRUB_BACKGROUND=|# BEGIN rafex thinkpad grub background|# END rafex thinkpad grub background)' "$GRUB_CONFIG" || true
  else
    printf "GRUB: %s no disponible\n" "$GRUB_CONFIG"
  fi
  if [[ -f "$LIGHTDM_CONFIG" ]]; then
    grep -E '^(background=|# BEGIN rafex thinkpad lightdm background|# END rafex thinkpad lightdm background)' "$LIGHTDM_CONFIG" || true
  else
    printf 'LightDM: configuración no disponible\n'
  fi
  info "status no usa sudo, no recarga i3 y no reinicia LightDM"
}

apply_stage() {
  validate_sources || die "faltan fondos en el perfil versionado"
  if stage_has grub "$STAGE" || stage_has login "$STAGE"; then
    command -v sudo >/dev/null 2>&1 || die "se necesita sudo para las etapas de sistema"
    sudo -v
  fi

  if stage_has desktop "$STAGE"; then
    copy_user_assets
    configure_i3_background
    reload_i3_if_local
  fi
  if stage_has grub "$STAGE"; then
    configure_grub_background
  fi
  if stage_has login "$STAGE"; then
    configure_login_background
  fi
  success "etapa aplicada: ${STAGE}"
}

parse_args() {
  local arg
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --stage)
        (($# >= 2)) || die "--stage requiere un valor"
        STAGE="$2"
        shift
        ;;
      --stage=*) STAGE="${arg#*=}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: ${arg}" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux
  require_user
  validate_stage

  case "$ACTION" in
    check)
      printf '═══ Fondos ThinkPad (%s) ═══\n' "$VERSION"
      show_check
      ;;
    plan) show_plan ;;
    apply) apply_stage ;;
    status) show_status ;;
    *) die "acción no válida: ${ACTION}" ;;
  esac
}

main "$@"
