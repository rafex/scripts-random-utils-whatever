#!/usr/bin/env bash
# install_thinkpad_audio_profile_linux.sh v1.0.0
# Instala EasyEffects y un perfil reversible de claridad vocal para la ThinkPad.
set -Eeuo pipefail
umask 077
export PATH="${PATH:-}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ACTION=check
PACKAGE=easyeffects
PRESET_NAME='ThinkPad X1 Yoga - Voces claras'
DEVICE_NAME="${EASYEFFECTS_DEVICE:-alsa_output.pci-0000_00_1f.3.analog-stereo}"
DEVICE_DESCRIPTION="${EASYEFFECTS_DEVICE_DESCRIPTION:-Audio Interno Estéreo analógico}"
SPEAKER_ROUTE="${EASYEFFECTS_SPEAKER_ROUTE:-}"
HEADPHONE_ROUTE="${EASYEFFECTS_HEADPHONE_ROUTE:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PRESET_SOURCE="$REPO_ROOT/assets/audio/thinkpad_x1_yoga_voice_clarity.json"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PRESET_TARGET="$DATA_HOME/easyeffects/output/$PRESET_NAME.json"
AUTOLOAD_DIR="$DATA_HOME/easyeffects/autoload/output"
AUTOSTART_TARGET="$CONFIG_HOME/autostart/com.github.wwmm.easyeffects.desktop"
STATE_DIR="$STATE_HOME/rafex/thinkpad-audio-profile"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_thinkpad_audio_profile_linux.sh --check|--plan|--apply|--status|--rollback

Instala EasyEffects, guarda un preset de voces claras, lo asocia a los puertos
Altavoces/Auriculares del dispositivo analógico y activa EasyEffects al iniciar
sesión. No modifica volumen ni micrófono.

Variables opcionales:
  EASYEFFECTS_DEVICE, EASYEFFECTS_DEVICE_DESCRIPTION
  EASYEFFECTS_SPEAKER_ROUTE, EASYEFFECTS_HEADPHONE_ROUTE
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

detect_routes() {
  if [[ -z "$SPEAKER_ROUTE" || -z "$HEADPHONE_ROUTE" ]]; then
    command -v pactl >/dev/null 2>&1 || die 'falta pactl; inicia PipeWire antes de configurar el perfil.'
    local routes
    routes="$(pactl --format=json list sinks 2>/dev/null | python3 -c '
import json, sys
device = sys.argv[1]
sinks = json.load(sys.stdin)
sink = next((item for item in sinks if item.get("name") == device), None)
if sink is None:
    raise SystemExit("No se encontró el sink " + device)
ports = {p.get("name"): p.get("description", p.get("name", "")) for p in sink.get("ports", [])}
for name in ("analog-output-speaker", "analog-output-headphones"):
    print(ports.get(name, ""))
' "$DEVICE_NAME")" || die 'no se pudieron leer las rutas de altavoz y auriculares con pactl.'
    [[ -n "$SPEAKER_ROUTE" ]] || SPEAKER_ROUTE="$(sed -n '1p' <<<"$routes")"
    [[ -n "$HEADPHONE_ROUTE" ]] || HEADPHONE_ROUTE="$(sed -n '2p' <<<"$routes")"
  fi
  [[ -n "$SPEAKER_ROUTE" && -n "$HEADPHONE_ROUTE" ]] ||
    die 'no se detectaron ambas rutas; define EASYEFFECTS_SPEAKER_ROUTE y EASYEFFECTS_HEADPHONE_ROUTE.'
}

autoload_target() {
  local route="$1"
  route="${route//\//_}"
  printf '%s/%s:%s.json' "$AUTOLOAD_DIR" "${DEVICE_NAME//\//_}" "$route"
}

require_environment() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux.'
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente.'
  [[ -f "$PRESET_SOURCE" ]] || die "no se encontró el preset: $PRESET_SOURCE"
  command -v python3 >/dev/null 2>&1 || die 'falta python3.'
  command -v dpkg-query >/dev/null 2>&1 || die 'se requiere Debian/Ubuntu (dpkg-query).'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get.'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para instalar EasyEffects.'
    command -v pactl >/dev/null 2>&1 || die 'falta pactl; PipeWire no está disponible.'
  fi
}

package_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null || true)" == 'install ok installed' ]]
}

install_package() {
  if package_installed && command -v easyeffects >/dev/null 2>&1; then
    ok 'EasyEffects ya está instalado.'
    return 0
  fi
  if [[ "$ACTION" == plan ]]; then
    info '[plan] sudo apt-get update'
    info '[plan] sudo apt-get install -y easyeffects (incluye complementos recomendados)'
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
  temporary="$(mktemp "$directory/.rafex-audio.XXXXXX")"
  install -m "$mode" -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

write_autoload() {
  local route="$1" target="$2" temporary
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-autoload.XXXXXX")"
  python3 - "$DEVICE_NAME" "$DEVICE_DESCRIPTION" "$route" "$PRESET_NAME" > "$temporary" <<'PY'
import json, sys
device, description, route, preset = sys.argv[1:]
json.dump({"device": device, "device-description": description,
           "device-profile": route, "preset-name": preset}, sys.stdout,
          ensure_ascii=False, indent=4)
print()
PY
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$target"
}

write_autostart() {
  local temporary
  mkdir -p -- "$(dirname -- "$AUTOSTART_TARGET")"
  temporary="$(mktemp "$(dirname -- "$AUTOSTART_TARGET")/.rafex-audio-autostart.XXXXXX")"
  cat > "$temporary" <<'EOF'
[Desktop Entry]
Name=EasyEffects
Comment=EasyEffects audio effects service
Exec=easyeffects --hide-window --service-mode
Icon=com.github.wwmm.easyeffects
StartupNotify=false
Terminal=false
Type=Application
X-GNOME-Autostart-Phase=Application
X-KDE-autostart-phase=2
EOF
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$AUTOSTART_TARGET"
}

apply_profile() {
  local speaker_autoload headphone_autoload
  speaker_autoload="$(autoload_target "$SPEAKER_ROUTE")"
  headphone_autoload="$(autoload_target "$HEADPHONE_ROUTE")"
  mkdir -p -- "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  record_original "$PRESET_TARGET" preset
  record_original "$speaker_autoload" speaker-autoload
  record_original "$headphone_autoload" headphone-autoload
  record_original "$AUTOSTART_TARGET" autostart
  atomic_copy "$PRESET_SOURCE" "$PRESET_TARGET"
  write_autoload "$SPEAKER_ROUTE" "$speaker_autoload"
  write_autoload "$HEADPHONE_ROUTE" "$headphone_autoload"
  write_autostart
  printf '%s\n' "$DEVICE_NAME" > "$STATE_DIR/device-name"
  printf '%s\n' "$SPEAKER_ROUTE" > "$STATE_DIR/speaker-route"
  printf '%s\n' "$HEADPHONE_ROUTE" > "$STATE_DIR/headphone-route"
  printf '%s\n' "$PRESET_TARGET" > "$STATE_DIR/preset-target"
  printf '%s\n' "$speaker_autoload" > "$STATE_DIR/speaker-autoload-target"
  printf '%s\n' "$headphone_autoload" > "$STATE_DIR/headphone-autoload-target"
  printf '%s\n' "$AUTOSTART_TARGET" > "$STATE_DIR/autostart-target"
  ok "preset instalado para $SPEAKER_ROUTE y $HEADPHONE_ROUTE."
  ok 'EasyEffects se iniciará al entrar en i3 y cargará el preset para el dispositivo analógico.'
}

restore_target() {
  local target="$1" key="$2" temporary
  if [[ -e "$STATE_DIR/$key.present" ]]; then
    [[ -e "$STATE_DIR/$key.backup" || -L "$STATE_DIR/$key.backup" ]] || die "falta el respaldo $key."
    mkdir -p -- "$(dirname -- "$target")"
    temporary="$(mktemp "$(dirname -- "$target")/.rafex-audio-restore.XXXXXX")"
    cp -a -- "$STATE_DIR/$key.backup" "$temporary"
    mv -f -- "$temporary" "$target"
  elif [[ -e "$STATE_DIR/$key.absent" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then rm -f -- "$target"; fi
  else
    die "no hay historial de instalación para $key."
  fi
}

rollback_profile() {
  [[ -d "$STATE_DIR" ]] || die 'no hay un perfil instalado para revertir.'
  restore_target "$(cat "$STATE_DIR/preset-target")" preset
  restore_target "$(cat "$STATE_DIR/speaker-autoload-target")" speaker-autoload
  restore_target "$(cat "$STATE_DIR/headphone-autoload-target")" headphone-autoload
  restore_target "$(cat "$STATE_DIR/autostart-target")" autostart
  ok 'configuración de audio restaurada; EasyEffects permanece instalado.'
}

main() {
  parse_args "$@"
  require_environment
  if [[ "$ACTION" == rollback ]]; then rollback_profile; return 0; fi
  if [[ "$ACTION" == apply || "$ACTION" == plan ]]; then detect_routes; fi
  if [[ "$ACTION" == check || "$ACTION" == status ]]; then
    if package_installed && command -v easyeffects >/dev/null 2>&1 && [[ -f "$PRESET_TARGET" ]]; then
      printf 'EasyEffects y el preset están instalados.\n'
    else
      printf 'Falta EasyEffects o el preset. Ejecuta: just install-thinkpad-audio-profile --apply\n'
      [[ "$ACTION" == status ]] || return 1
    fi
    return 0
  fi
  install_package
  if [[ "$ACTION" == plan ]]; then
    info "[plan] instalar el preset en $PRESET_TARGET"
    info "[plan] crear autoload para $SPEAKER_ROUTE y $HEADPHONE_ROUTE"
    info "[plan] habilitar inicio de EasyEffects en la sesión de usuario"
    return 0
  fi
  apply_profile
}

main "$@"
