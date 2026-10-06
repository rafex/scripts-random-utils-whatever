#!/usr/bin/env bash
# install_thinkpad_microphone_profile_linux.sh v1.0.0
# Activa una cadena moderada de reducción de ruido y dinámica para el micrófono interno.
set -Eeuo pipefail
umask 077
export PATH="${PATH:-}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ACTION=check
PACKAGE=easyeffects
PRESET_NAME='ThinkPad X1 Yoga - Micrófono interno'
MIC_SOURCE="${EASYEFFECTS_MIC_SOURCE:-alsa_input.pci-0000_00_1f.3.analog-stereo}"
MIC_ROUTE="${EASYEFFECTS_MIC_ROUTE:-analog-input-internal-mic}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PRESET_SOURCE="$REPO_ROOT/assets/audio/thinkpad_x1_yoga_internal_mic.json"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PRESET_TARGET="$DATA_HOME/easyeffects/input/$PRESET_NAME.json"
AUTOLOAD_DIR="$DATA_HOME/easyeffects/autoload/input"
AUTOSTART_TARGET="$CONFIG_HOME/autostart/rafex-easyeffects-microphone.desktop"
HELPER_TARGET="${XDG_BIN_HOME:-$HOME/.local/bin}/rafex-easyeffects-mic-start"
STATE_DIR="$STATE_HOME/rafex/thinkpad-microphone-profile"
VIRTUAL_SOURCE='easyeffects_source'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_thinkpad_microphone_profile_linux.sh --check|--plan|--apply|--status|--rollback

Instala un preset de EasyEffects para el micrófono interno, configura su
autocarga, inicia EasyEffects al entrar en la sesión y selecciona
easyeffects_source como entrada predeterminada del sistema.

Variables:
  EASYEFFECTS_MIC_SOURCE  Origen PipeWire (default: entrada analógica ThinkPad)
  EASYEFFECTS_MIC_ROUTE   Puerto del micrófono (default: analog-input-internal-mic)
  XDG_BIN_HOME            Directorio del helper (default: ~/.local/bin)

--rollback restaura los archivos previos y la fuente predeterminada anterior.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --rollback) ACTION=rollback ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_environment() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux.'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa solo para APT.'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución.'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}."
  command -v python3 >/dev/null 2>&1 || die 'falta python3.'
  command -v dpkg-query >/dev/null 2>&1 || die 'se requiere dpkg-query.'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get.'
  command -v pactl >/dev/null 2>&1 || die 'falta pactl; PipeWire/PulseAudio no está disponible.'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para instalar EasyEffects.'
  fi
  [[ -f "$PRESET_SOURCE" ]] || die "no se encontró el preset: $PRESET_SOURCE"
}

package_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null || true)" == 'install ok installed' ]]
}

input_autoload_target() {
  local source_name="$1" route="$2"
  source_name="${source_name//\//_}"
  route="${route//\//_}"
  printf '%s/%s:%s.json' "$AUTOLOAD_DIR" "$source_name" "$route"
}

detect_microphone() {
  local source_json
  source_json="$(pactl --format=json list sources 2>/dev/null)" ||
    die 'no se pudieron listar los orígenes de audio con pactl.'
  python3 -c '
import json, sys
name, route = sys.argv[1:]
sources = json.load(sys.stdin)
source = next((item for item in sources if item.get("name") == name), None)
if source is None:
    raise SystemExit(f"No se encontró el origen {name}")
ports = {port.get("name") for port in source.get("ports", [])}
if route not in ports:
    raise SystemExit(f"No se encontró el puerto {route} en {name}")
' "$MIC_SOURCE" "$MIC_ROUTE" <<<"$source_json"
}

install_package() {
  if package_installed && command -v easyeffects >/dev/null 2>&1; then
    ok 'EasyEffects ya está instalado.'
    return 0
  fi
  if [[ "$ACTION" == plan ]]; then
    info '[plan] sudo apt-get update && sudo apt-get install -y easyeffects'
    return 0
  fi
  [[ "$ACTION" == apply ]] || return 0
  sudo -v
  sudo apt-get update
  sudo apt-get install -y easyeffects
  command -v easyeffects >/dev/null 2>&1 || die 'APT terminó pero no se encuentra easyeffects.'
}

record_original() {
  local target="$1" key="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ ! -e "$STATE_DIR/$key.present" && ! -e "$STATE_DIR/$key.absent" ]]; then
      cp -a -- "$target" "$STATE_DIR/$key.backup"
      : > "$STATE_DIR/$key.present"
    fi
  elif [[ ! -e "$STATE_DIR/$key.present" && ! -e "$STATE_DIR/$key.absent" ]]; then
    : > "$STATE_DIR/$key.absent"
  fi
}

atomic_copy() {
  local source="$1" target="$2" mode="${3:-0644}" directory temporary
  directory="$(dirname -- "$target")"
  mkdir -p -- "$directory"
  temporary="$(mktemp "$directory/.rafex-mic.XXXXXX")"
  install -m "$mode" -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

write_autoload() {
  local target="$1" temporary
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-mic-autoload.XXXXXX")"
  python3 - "$MIC_SOURCE" "$MIC_ROUTE" "$PRESET_NAME" > "$temporary" <<'PY'
import json
import sys

source, route, preset = sys.argv[1:]
json.dump({"device": source, "device-description": "Micrófono interno ThinkPad",
           "device-profile": route, "preset-name": preset}, sys.stdout,
          ensure_ascii=False, indent=4)
print()
PY
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$target"
}

desktop_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value// /\\s}"
  printf '%s' "$value"
}

write_helper() {
  local temporary
  mkdir -p -- "$(dirname -- "$HELPER_TARGET")"
  temporary="$(mktemp "$(dirname -- "$HELPER_TARGET")/.rafex-mic-start.XXXXXX")"
  cat > "$temporary" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="${PATH:-}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

command -v easyeffects >/dev/null 2>&1 || exit 1
command -v pactl >/dev/null 2>&1 || exit 1
easyeffects --hide-window --service-mode >/dev/null 2>&1 &
for _ in {1..30}; do
  if pactl list short sources 2>/dev/null | awk -v source='easyeffects_source' '$2 == source { found = 1 } END { exit !found }'; then
    pactl set-default-source easyeffects_source
    exit
  fi
  sleep 1
done
printf '%s\n' 'EasyEffects Source no apareció después de iniciar EasyEffects.' >&2
exit 1
EOF
  chmod 0755 "$temporary"
  mv -f -- "$temporary" "$HELPER_TARGET"
}

write_autostart() {
  local temporary escaped_helper
  escaped_helper="$(desktop_escape "$HELPER_TARGET")"
  mkdir -p -- "$(dirname -- "$AUTOSTART_TARGET")"
  temporary="$(mktemp "$(dirname -- "$AUTOSTART_TARGET")/.rafex-mic-start.XXXXXX")"
  cat > "$temporary" <<EOF
[Desktop Entry]
Type=Application
Name=Rafex EasyEffects microphone input
Comment=Start EasyEffects and select its processed microphone input
Exec=$escaped_helper
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$AUTOSTART_TARGET"
}

apply_profile() {
  local autoload_target old_source
  autoload_target="$(input_autoload_target "$MIC_SOURCE" "$MIC_ROUTE")"
  mkdir -p -- "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  record_original "$PRESET_TARGET" preset
  record_original "$autoload_target" input-autoload
  record_original "$HELPER_TARGET" helper
  record_original "$AUTOSTART_TARGET" autostart
  if [[ ! -e "$STATE_DIR/default-source.saved" ]]; then
    old_source="$(pactl get-default-source 2>/dev/null)" || die 'no se pudo guardar la entrada de audio predeterminada actual.'
    printf '%s\n' "$old_source" > "$STATE_DIR/default-source"
    : > "$STATE_DIR/default-source.saved"
  fi
  atomic_copy "$PRESET_SOURCE" "$PRESET_TARGET"
  write_autoload "$autoload_target"
  write_helper
  write_autostart
  printf '%s\n' "$MIC_SOURCE" > "$STATE_DIR/mic-source"
  printf '%s\n' "$MIC_ROUTE" > "$STATE_DIR/mic-route"
  printf '%s\n' "$PRESET_TARGET" > "$STATE_DIR/preset-target"
  printf '%s\n' "$autoload_target" > "$STATE_DIR/autoload-target"
  printf '%s\n' "$HELPER_TARGET" > "$STATE_DIR/helper-target"
  printf '%s\n' "$AUTOSTART_TARGET" > "$STATE_DIR/autostart-target"
  "$HELPER_TARGET" || die 'EasyEffects no pudo iniciar la entrada virtual easyeffects_source.'
  ok "preset activado para $MIC_SOURCE ($MIC_ROUTE)."
  ok "entrada predeterminada cambiada a $VIRTUAL_SOURCE y persistida al iniciar sesión."
}

restore_target() {
  local target="$1" key="$2" temporary
  if [[ -e "$STATE_DIR/$key.present" ]]; then
    [[ -e "$STATE_DIR/$key.backup" || -L "$STATE_DIR/$key.backup" ]] || die "falta el respaldo $key."
    mkdir -p -- "$(dirname -- "$target")"
    temporary="$(mktemp "$(dirname -- "$target")/.rafex-mic-restore.XXXXXX")"
    cp -a -- "$STATE_DIR/$key.backup" "$temporary"
    mv -f -- "$temporary" "$target"
  elif [[ -e "$STATE_DIR/$key.absent" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then rm -f -- "$target"; fi
  else
    die "no hay historial de instalación para $key."
  fi
}

rollback_profile() {
  local previous_source
  [[ -d "$STATE_DIR" ]] || die 'no hay un perfil de micrófono instalado para revertir.'
  restore_target "$(cat "$STATE_DIR/preset-target")" preset
  restore_target "$(cat "$STATE_DIR/autoload-target")" input-autoload
  restore_target "$(cat "$STATE_DIR/helper-target")" helper
  restore_target "$(cat "$STATE_DIR/autostart-target")" autostart
  previous_source="$(cat "$STATE_DIR/default-source")"
  pactl set-default-source "$previous_source" || die "no se pudo restaurar la entrada predeterminada anterior: $previous_source"
  ok "configuración restaurada; entrada predeterminada anterior: $previous_source."
}

show_status() {
  local autoload_target current_source
  autoload_target="$(input_autoload_target "$MIC_SOURCE" "$MIC_ROUTE")"
  current_source="$(pactl get-default-source 2>/dev/null || true)"
  printf 'mic_source=%s\nmic_route=%s\ndefault_source=%s\n' "$MIC_SOURCE" "$MIC_ROUTE" "${current_source:-desconocida}"
  if package_installed && command -v easyeffects >/dev/null 2>&1; then ok 'EasyEffects instalado.'; else warn 'EasyEffects no está instalado.'; fi
  if [[ -f "$PRESET_TARGET" ]]; then ok 'preset de entrada instalado.'; else warn 'falta el preset de entrada.'; fi
  if [[ -f "$autoload_target" ]]; then ok 'autocarga del micrófono configurada.'; else warn 'falta la regla de autocarga.'; fi
  if [[ -x "$HELPER_TARGET" && -f "$AUTOSTART_TARGET" ]]; then
    ok 'activación automática de sesión configurada.'
  else
    warn 'falta la activación automática de sesión.'
  fi
  [[ "$current_source" == "$VIRTUAL_SOURCE" ]] || warn "la entrada actual no es $VIRTUAL_SOURCE."
}

main() {
  parse_args "$@"
  require_environment
  if [[ "$ACTION" == rollback ]]; then rollback_profile; return 0; fi
  if [[ "$ACTION" == check || "$ACTION" == status ]]; then
    show_status
    if [[ "$ACTION" == check ]]; then
      package_installed || return 1
      [[ -f "$PRESET_TARGET" ]] || return 1
      [[ -f "$(input_autoload_target "$MIC_SOURCE" "$MIC_ROUTE")" ]] || return 1
      [[ -x "$HELPER_TARGET" && -f "$AUTOSTART_TARGET" ]] || return 1
      [[ "$(pactl get-default-source 2>/dev/null || true)" == "$VIRTUAL_SOURCE" ]] || return 1
    fi
    return 0
  fi
  detect_microphone || die "no se encontró el micrófono o el puerto solicitado: $MIC_SOURCE / $MIC_ROUTE."
  install_package
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar el preset $PRESET_NAME en $PRESET_TARGET"
    info "[plan] crear autocarga de entrada para $MIC_SOURCE ($MIC_ROUTE)"
    info "[plan] instalar helper de sesión y seleccionar $VIRTUAL_SOURCE como entrada predeterminada"
    info '[plan] guardar configuración anterior para --rollback'
    return 0
  fi
  apply_profile
}

main "$@"
