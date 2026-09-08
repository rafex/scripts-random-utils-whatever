#!/usr/bin/env bash
# install_picom_user_service_linux.sh v1.0.0
# Instala la unidad de usuario de Picom y la integración idempotente con i3.
# shellcheck shell=bash
set -Eeuo pipefail
umask 077

ACTION=check
REPLACE_UNMANAGED=false
CHOSEN=false
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
export RAFEX_THINKPAD_OWNERSHIP_REGISTRY="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/thinkpad-ownership.tsv"
# shellcheck disable=SC1091 # ruta absoluta calculada desde el checkout.
source "$REPO_ROOT/scripts/lib/thinkpad_config_guard_linux.sh"
PROFILE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
UNIT_SOURCE="$PROFILE_ROOT/config/systemd/user/rafex-picom.service"
RUNNER_SOURCE="$REPO_ROOT/scripts/system/rafex_picom_runner_linux.sh"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
UNIT_TARGET="$CONFIG_HOME/systemd/user/rafex-picom.service"
RUNNER_TARGET="$HOME/.local/bin/rafex-picom-runner.sh"
AUTOSTART_TARGET="$CONFIG_HOME/autostart/picom.desktop"
I3_CONFIG="${I3_SERVICE_CONFIG:-$CONFIG_HOME/i3/config}"
STATE_FILE="$CONFIG_HOME/rafex/picom-autostart-enabled"
LEGACY_STATE_FILE="$CONFIG_HOME/rafex/openbox-picom-enabled"
BEGIN_MARKER='# >>> rafex-picom-service managed >>>'
END_MARKER='# <<< rafex-picom-service managed <<<'
AUTOSTART_MARKER='# Managed by rafex install_picom_user_service_linux.sh'
SERVICE_MARKER='# Managed by rafex install_picom_user_service_linux.sh'
RUNNER_MARKER='# Managed by rafex install_picom_user_service_linux.sh'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_picom_user_service_linux.sh --check
  install_picom_user_service_linux.sh --plan
  install_picom_user_service_linux.sh --apply [--replace-unmanaged]
  install_picom_user_service_linux.sh --status

Instala rafex-picom.service como unidad de usuario. i3 la inicia cuando X11
está listo; la unidad no se habilita globalmente ni usa sudo.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--apply|--status)
        [[ "$CHOSEN" == false ]] || die 'selecciona una sola acción'
        ACTION="${1#--}"
        CHOSEN=true
        ;;
      --replace-unmanaged) REPLACE_UNMANAGED=true ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_base() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
  [[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
  command -v systemctl >/dev/null 2>&1 || die 'falta systemctl'
  [[ -f "$UNIT_SOURCE" ]] || die "falta la unidad versionada: $UNIT_SOURCE"
  [[ -f "$RUNNER_SOURCE" ]] || die "falta el runner versionado: $RUNNER_SOURCE"
  if [[ "$ACTION" == check || "$ACTION" == status ]]; then
    command -v picom >/dev/null 2>&1 || warn 'Picom no está en PATH; se validará al iniciar el servicio'
  fi
}

managed_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  grep -Fq "$AUTOSTART_MARKER" "$path" && return 0
  grep -Fq "$BEGIN_MARKER" "$path" && return 0
  grep -Fq "$SERVICE_MARKER" "$path" && return 0
  grep -Fq "$RUNNER_MARKER" "$path" && return 0
  return 1
}

allow_target() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -f "$path" && ! -L "$path" ]] || die "el destino no es un archivo regular: $path"
  managed_file "$path" && return 0
  [[ "$REPLACE_UNMANAGED" == true ]] && return 0
  die "se rehúsa sobrescribir un archivo no administrado: $path (usa --replace-unmanaged tras revisar el respaldo)"
}

atomic_copy() {
  local source="$1" target="$2" mode="$3" temporary
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  allow_target "$target"
  mkdir -p -- "$(dirname -- "$target")"
  if [[ -e "$target" ]]; then
    cp -p -- "$target" "$target.bak.$STAMP"
    info "respaldo: $target.bak.$STAMP"
  fi
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  install -m "$mode" -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

write_autostart_source() {
  local path="$1"
  cat > "$path" <<EOF
$AUTOSTART_MARKER
[Desktop Entry]
Type=Application
Name=Picom (Rafex, gestionado por i3)
Comment=El autostart genérico queda desactivado; i3 inicia rafex-picom.service
NoDisplay=true
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
}

install_autostart_override() {
  local source
  allow_target "$AUTOSTART_TARGET"
  mkdir -p -- "$(dirname -- "$AUTOSTART_TARGET")"
  source="$(mktemp "${AUTOSTART_TARGET}.tmp.XXXXXX")"
  write_autostart_source "$source"
  if [[ -f "$AUTOSTART_TARGET" ]] && cmp -s "$source" "$AUTOSTART_TARGET"; then
    rm -f -- "$source"
    return 0
  fi
  if [[ -e "$AUTOSTART_TARGET" ]]; then
    cp -p -- "$AUTOSTART_TARGET" "$AUTOSTART_TARGET.bak.$STAMP"
    info "respaldo: $AUTOSTART_TARGET.bak.$STAMP"
  fi
  install -m 0644 -- "$source" "$AUTOSTART_TARGET"
  rm -f -- "$source"
}

write_i3_block() {
  local block_file cleaned
  [[ -f "$I3_CONFIG" ]] || die "falta la configuración de i3: $I3_CONFIG"
  if grep -Fq 'systemctl --user start rafex-picom.service' "$I3_CONFIG" \
    && ! grep -Fq "$BEGIN_MARKER" "$I3_CONFIG"; then
    die 'i3 ya contiene un inicio de rafex-picom fuera del bloque administrado'
  fi
  block_file="$(mktemp)"
  cat > "$block_file" <<'EOF'
# >>> rafex-picom-service managed >>>
exec_always --no-startup-id sh -c 'if [ -f "$HOME/.config/rafex/picom-autostart-enabled" ] || [ -f "$HOME/.config/rafex/openbox-picom-enabled" ]; then systemctl --user import-environment DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1; systemctl --user start rafex-picom.service >/dev/null 2>&1; fi'
# <<< rafex-picom-service managed <<<
EOF
  cleaned="$(mktemp "${I3_CONFIG}.tmp.XXXXXX")"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block_file="$block_file" '
    function emit(  line) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }
    $0 == begin {
      if (!done) { emit(); done=1 }
      skip=1
      next
    }
    skip && $0 == end { skip=0; next }
    !skip { print }
    END {
      if (!done) { print ""; emit() }
    }
  ' "$I3_CONFIG" > "$cleaned"
  if cmp -s "$cleaned" "$I3_CONFIG"; then
    rm -f -- "$cleaned" "$block_file"
    return 0
  fi
  cp -p -- "$I3_CONFIG" "$I3_CONFIG.bak.$STAMP"
  info "respaldo: $I3_CONFIG.bak.$STAMP"
  mv -f -- "$cleaned" "$I3_CONFIG"
  rm -f -- "$block_file"
}

migrate_autostart_state() {
  [[ -f "$STATE_FILE" ]] && return 0
  [[ -f "$LEGACY_STATE_FILE" ]] || return 0
  mkdir -p -- "$(dirname -- "$STATE_FILE")"
  printf '%s\n' enabled > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
  info "preferencia heredada migrada a $STATE_FILE"
}

show_state() {
  if [[ -f "$STATE_FILE" || -f "$LEGACY_STATE_FILE" ]]; then
    printf 'autostart-preference=enabled\n'
  else
    printf 'autostart-preference=disabled\n'
  fi
}

show_status() {
  printf '═══ Servicio de usuario Rafex Picom ═══\n'
  printf 'unidad: %s\n' "$UNIT_TARGET"
  printf 'runner: %s\n' "$RUNNER_TARGET"
  printf 'i3: %s\n' "$I3_CONFIG"
  show_state
  if [[ -f "$UNIT_TARGET" ]]; then ok 'unidad instalada'; else warn 'unidad ausente'; fi
  if [[ -x "$RUNNER_TARGET" ]]; then ok 'runner instalado'; else warn 'runner ausente'; fi
  if [[ -f "$AUTOSTART_TARGET" ]] && managed_file "$AUTOSTART_TARGET"; then
    ok 'autostart genérico de Picom desactivado mediante override de usuario'
  else
    warn 'no existe override administrado para el autostart genérico'
  fi
  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$BEGIN_MARKER" "$I3_CONFIG"; then
    ok 'inicio administrado presente en i3'
  else
    warn 'inicio administrado ausente en i3'
  fi
  if systemctl --user is-active --quiet rafex-picom.service 2>/dev/null; then
    ok 'servicio activo'
    systemctl --user --no-pager --full status rafex-picom.service 2>/dev/null | sed -n '1,12p' || true
  else
    info 'servicio detenido'
  fi
}

show_plan() {
  printf '═══ Plan de servicio de usuario Rafex Picom ═══\n'
  printf 'unidad: %s\n' "$UNIT_TARGET"
  printf 'runner: %s\n' "$RUNNER_TARGET"
  printf 'override autostart: %s\n' "$AUTOSTART_TARGET"
  printf 'integración i3: %s\n' "$I3_CONFIG"
  printf '%s\n' 'i3 importará DISPLAY/XAUTHORITY y ejecutará systemctl --user start rafex-picom.service.'
  printf '%s\n' 'systemd reiniciará Picom ante fallos; no se habilitará el servicio en default.target.'
  printf '%s\n' 'No usa sudo, no modifica /etc/xdg/autostart/picom.desktop y no inicia el servicio durante el plan.'
}

main() {
  parse_args "$@"
  require_base
  case "$ACTION" in
    check)
      show_plan
      [[ -f "$UNIT_TARGET" ]] || warn "unidad pendiente: $UNIT_TARGET"
      [[ -x "$RUNNER_TARGET" ]] || warn "runner pendiente: $RUNNER_TARGET"
      ;;
    plan) show_plan ;;
    status) show_status ;;
    apply)
      rafex_guard_require_owner 'picom.lifecycle' 'install-picom-user-service' || die 'propietario de Picom rechazado'
      rafex_guard_require_owner 'i3.picom-service' 'install-picom-user-service' || die 'propietario de i3 rechazado'
      local unit_before i3_before
      unit_before="$(rafex_guard_sha256 "$UNIT_TARGET")"
      i3_before="$(rafex_guard_sha256 "$I3_CONFIG")"
      atomic_copy "$RUNNER_SOURCE" "$RUNNER_TARGET" 0755
      atomic_copy "$UNIT_SOURCE" "$UNIT_TARGET" 0644
      install_autostart_override
      migrate_autostart_state
      write_i3_block
      systemctl --user daemon-reload
      rafex_guard_record_write 'install-picom-user-service' 'picom.lifecycle' "$UNIT_TARGET" "$unit_before" 'unidad de usuario Picom'
      rafex_guard_record_write 'install-picom-user-service' 'i3.picom-service' "$I3_CONFIG" "$i3_before" 'inicio de Picom desde i3'
      ok 'servicio de usuario e integración i3 instalados'
      info 'recarga i3 con Mod+Shift+r o inicia con: just picom-toggle --enable'
      ;;
  esac
}

main "$@"
