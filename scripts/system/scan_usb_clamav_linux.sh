#!/usr/bin/env bash
# Escanea únicamente medios extraíbles montados en rutas de usuario.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

TARGET_USER="$(id -un)"
ACTION="manual"
REQUESTED_PATH=""
EVENT=""
LOCK_DIR="$HOME/.cache/rafex/clamav-usb-scan.lock"
LOG_DIR="$HOME/.local/state/rafex/clamav"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 2; }

usage() {
  cat <<'EOF'
Uso:
  scan_usb_clamav_linux.sh --path /run/media/$USER/NOMBRE_USB
  scan_usb_clamav_linux.sh --auto-event EVENTO

Escanea sin borrar ni poner en cuarentena. Retorna 0 si está limpio, 1 si
ClamAV encuentra una infección y 2 si hay un error de validación/lectura.
Solo acepta montajes bajo /run/media/$USER o /media/$USER y dispositivos
extraíbles; rechaza el sistema, HOME, NVMe y rutas arbitrarias.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --path)
        (($# >= 2)) || die '--path requiere una ruta'
        REQUESTED_PATH="$2"; shift
        ;;
      --auto-event)
        (($# >= 2)) || die '--auto-event requiere un evento'
        ACTION=auto; EVENT="$2"; shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$ACTION" == auto || -n "$REQUESTED_PATH" ]] || die 'usa --path o --auto-event'
}

require_tools() {
  command -v findmnt >/dev/null 2>&1 || die 'falta findmnt'
  command -v lsblk >/dev/null 2>&1 || die 'falta lsblk'
  command -v clamscan >/dev/null 2>&1 || die 'falta clamscan; instala ClamAV primero'
}

is_allowed_prefix() {
  local path="$1"
  [[ "$path" == "/run/media/$TARGET_USER/"* || "$path" == "/media/$TARGET_USER/"* ]]
}

is_removable_mount() {
  local path="$1" source parent removable type
  source="$(findmnt -n -o SOURCE --target "$path" 2>/dev/null || true)"
  [[ -n "$source" && "$source" == /dev/* ]] || return 1
  type="$(lsblk -no TYPE "$source" 2>/dev/null || true)"
  [[ "$type" == part || "$type" == disk ]] || return 1
  parent="$(lsblk -no PKNAME "$source" 2>/dev/null || true)"
  [[ -n "$parent" ]] || parent="$(basename "$source")"
  removable="$(cat "/sys/block/$parent/removable" 2>/dev/null || printf '0')"
  [[ "$removable" == 1 && "$parent" != nvme* ]]
}

canonical_mount() {
  local requested="$1" mountpoint canonical
  [[ -d "$requested" ]] || { warn "no existe el directorio: $requested"; return 1; }
  canonical="$(realpath -e -- "$requested" 2>/dev/null || true)"
  [[ -n "$canonical" ]] || { warn "no se pudo resolver: $requested"; return 1; }
  is_allowed_prefix "$canonical" || {
    warn "ruta rechazada; solo se permiten /run/media/$TARGET_USER/* o /media/$TARGET_USER/*"
    return 1
  }
  mountpoint="$(findmnt -n -o TARGET --target "$canonical" 2>/dev/null || true)"
  [[ -n "$mountpoint" && "$mountpoint" != / && "$mountpoint" != "$HOME" ]] || {
    warn 'la ruta no corresponde a un montaje de usuario seguro'
    return 1
  }
  is_removable_mount "$canonical" || {
    warn 'el montaje no pertenece a un dispositivo extraíble; se rechaza por seguridad'
    return 1
  }
  printf '%s\n' "$canonical"
}

discover_mounts() {
  local target
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    is_allowed_prefix "$target" || continue
    [[ "$target" != "/run/media/$TARGET_USER" && "$target" != "/media/$TARGET_USER" ]] || continue
    if canonical_mount "$target" >/dev/null 2>&1; then
      printf '%s\n' "$target"
    fi
  done < <(findmnt -rn -o TARGET 2>/dev/null)
}

scan_one() {
  local path="$1" log_path="$2" rc
  info "escaneando $path"
  if [[ -n "$log_path" ]]; then
    if clamscan --recursive --infected --no-summary --log="$log_path" -- "$path"; then
      rc=0
    else
      rc=$?
    fi
  elif clamscan --recursive --infected --no-summary -- "$path"; then
    rc=0
  else
    rc=$?
  fi
  case "$rc" in
    0) ok "sin infecciones: $path" ;;
    1) warn "ClamAV encontró una infección: $path" ;;
    *) warn "ClamAV no pudo completar la lectura de: $path (código $rc)"; rc=2 ;;
  esac
  return "$rc"
}

notify_result() {
  local code="$1" message="$2"
  command -v notify-send >/dev/null 2>&1 || return 0
  case "$code" in
    0) notify-send --app-name=ClamAV 'Escaneo USB' "$message: sin infecciones" ;;
    1) notify-send --app-name=ClamAV --urgency=critical 'Escaneo USB' "$message: infección encontrada" ;;
    *) notify-send --app-name=ClamAV --urgency=critical 'Escaneo USB' "$message: error de lectura" ;;
  esac
}

scan_paths() {
  local log_path='' path rc overall=0 scanned=0
  if ! mkdir -p "$LOCK_DIR" 2>/dev/null; then
    info 'ya hay un escaneo USB en curso; se omite este evento'
    return 0
  fi
  trap 'rmdir -- "$LOCK_DIR" 2>/dev/null || true' EXIT
  if [[ "$ACTION" == manual ]]; then
    path="$(canonical_mount "$REQUESTED_PATH")" || return 2
    scan_one "$path" '' || overall=$?
  else
    [[ "$EVENT" == *mount* || "$EVENT" == *attach* || "$EVENT" == device_added || "$EVENT" == device_changed ]] || return 0
    mkdir -p "$LOG_DIR"
    log_path="$LOG_DIR/usb-scan-$(date +%Y%m%d_%H%M%S).log"
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      if scan_one "$path" "$log_path"; then
        rc=0
      else
        rc=$?
      fi
      scanned=$((scanned + 1))
      ((rc == 1)) && overall=1
      ((rc > 1 && overall == 0)) && overall=2
    done < <(discover_mounts)
    [[ -s "$log_path" ]] && info "log automático: $log_path"
    if ((scanned == 0)); then
      info 'no había un montaje extraíble listo para escanear'
      if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name=ClamAV 'Escaneo USB' 'No había un USB montado listo para escanear' || true
      fi
    else
      notify_result "$overall" 'ClamAV terminó el escaneo automático'
    fi
  fi
  return "$overall"
}

parse_args "$@"
require_tools
scan_paths
