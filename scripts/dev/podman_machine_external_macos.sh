#!/usr/bin/env bash
# shellcheck shell=bash
# Administra una máquina Podman local con sus archivos en un volumen APFS externo.
set -Eeuo pipefail
umask 077

readonly VOLUME_NAME="apfs_ext_1tb"
readonly MOUNT_POINT="/Volumes/${VOLUME_NAME}"
readonly MACHINE_NAME="podman-apfs-ext-1tb"
readonly DISK_SIZE_GIB=168
readonly CPUS=6
readonly MEMORY_MIB=8192

XDG_CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}"
XDG_DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}"
PODMAN_ROOT="${MOUNT_POINT}/podman"
CONFIG_SOURCE="${XDG_CONFIG_ROOT}/containers/podman/machine"
DATA_SOURCE="${XDG_DATA_ROOT}/containers/podman/machine"
CONFIG_DEST="${PODMAN_ROOT}/config/machine"
DATA_DEST="${PODMAN_ROOT}/data/machine"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf 'INFO: %s\n' "$*"; }
ok() { printf 'OK: %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso:
  podman_machine_external_macos.sh setup
  podman_machine_external_macos.sh start
  podman_machine_external_macos.sh stop
  podman_machine_external_macos.sh status
  podman_machine_external_macos.sh --help

Administra la máquina podman-apfs-ext-1tb. La máquina y el almacenamiento
de imágenes/contenedores quedan en /Volumes/apfs_ext_1tb/podman.
EOF
}

require_macos() {
  [[ "$(uname -s)" == Darwin ]] || die 'este script solo funciona en macOS'
}

require_podman() {
  command -v podman >/dev/null 2>&1 || die 'no se encontró podman en PATH'
}

volume_info() {
  diskutil info "$MOUNT_POINT" 2>/dev/null || die "no se encontró el volumen montado en $MOUNT_POINT"
}

field_value() {
  local info_text="$1" field="$2"
  awk -F ': ' -v key="$field" '$1 ~ "^[[:space:]]*" key "$" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' <<<"$info_text"
}

validate_volume() {
  local info_text volume mounted personality volume_readonly
  [[ -d "$MOUNT_POINT" ]] || die "el volumen $VOLUME_NAME no está montado en $MOUNT_POINT"
  info_text="$(volume_info)"
  volume="$(field_value "$info_text" 'Volume Name')"
  mounted="$(field_value "$info_text" 'Mounted')"
  personality="$(field_value "$info_text" 'File System Personality')"
  volume_readonly="$(field_value "$info_text" 'Volume Read-Only')"

  [[ "$volume" == "$VOLUME_NAME" ]] || die "el volumen en $MOUNT_POINT se llama '$volume', se esperaba '$VOLUME_NAME'"
  [[ "$mounted" == Yes ]] || die "el volumen $VOLUME_NAME no está montado"
  [[ "$personality" == *APFS* ]] || die "el volumen debe usar APFS (detectado: ${personality:-desconocido})"
  [[ "$volume_readonly" == No && -w "$MOUNT_POINT" ]] || die "el volumen $VOLUME_NAME no permite escritura"
}

ensure_external_writable() {
  local probe
  mkdir -p "$PODMAN_ROOT"
  probe="${PODMAN_ROOT}/.podman-write-check-$$"
  : >"$probe" || die "no se puede escribir en $PODMAN_ROOT"
  rm -f -- "$probe"
}

machine_names() {
  podman machine list --quiet | sed 's/\*$//'
}

machine_exists() {
  local name
  while IFS= read -r name; do
    [[ "$name" == "$MACHINE_NAME" ]] && return 0
  done < <(machine_names)
  return 1
}

machine_state() {
  podman machine inspect --format '{{.State}}' "$MACHINE_NAME" 2>/dev/null
}

run_start_command() {
  local start_pid elapsed=0 rc
  podman machine start "$MACHINE_NAME" &
  start_pid=$!

  while kill -0 "$start_pid" 2>/dev/null; do
    if (( elapsed >= 60 )); then
      kill -TERM "$start_pid" 2>/dev/null || true
      wait "$start_pid" 2>/dev/null || true
      die "podman machine start excedió 60 segundos para $MACHINE_NAME"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if wait "$start_pid"; then
    return 0
  else
    rc=$?
    return "$rc"
  fi
}

verify_engine() {
  podman --connection "$MACHINE_NAME" info >/dev/null 2>&1 || die "la máquina $MACHINE_NAME no quedó disponible para Podman; revisa el log de la VM en ${TMPDIR:-/tmp}/podman/${MACHINE_NAME}.log"
}

link_machine_directory() {
  local source="$1" destination="$2" current_target
  mkdir -p "$(dirname "$source")" "$(dirname "$destination")"

  if [[ -L "$source" ]]; then
    current_target="$(readlink "$source")"
    [[ "$current_target" == "$destination" ]] || die "el enlace $source apunta a $current_target; no se cambiará automáticamente"
    [[ -d "$destination" ]] || die "el destino del enlace no existe: $destination"
    return
  fi

  if [[ -e "$source" ]]; then
    [[ ! -e "$destination" ]] || die "existen tanto $source como $destination; revisa ambos directorios antes de continuar"
    mv "$source" "$destination"
    info "directorio existente conservado en $destination"
  else
    mkdir -p "$destination"
  fi

  ln -s "$destination" "$source"
}

prepare_external_storage() {
  local existing_machines=""
  validate_volume
  ensure_external_writable

  if [[ ! -L "$CONFIG_SOURCE" || ! -L "$DATA_SOURCE" ]]; then
    existing_machines="$(machine_names)" || die 'no se pudo consultar la lista de máquinas Podman'
    [[ -z "$existing_machines" ]] || die "hay máquinas Podman registradas; no moveré sus archivos automáticamente. Deténlas y revísalas antes de configurar este volumen."
  fi

  link_machine_directory "$CONFIG_SOURCE" "$CONFIG_DEST"
  link_machine_directory "$DATA_SOURCE" "$DATA_DEST"
  ensure_external_writable
}

select_local_connection() {
  podman system connection default "$MACHINE_NAME" || die "no se pudo seleccionar la conexión $MACHINE_NAME"
}

start_machine() {
  validate_volume
  ensure_external_writable
  [[ -L "$CONFIG_SOURCE" && -L "$DATA_SOURCE" ]] || die 'la máquina aún no está vinculada al almacenamiento externo; ejecuta setup'
  [[ "$(readlink "$CONFIG_SOURCE")" == "$CONFIG_DEST" ]] || die "la configuración de Podman no apunta a $CONFIG_DEST"
  [[ "$(readlink "$DATA_SOURCE")" == "$DATA_DEST" ]] || die "los datos de Podman no apuntan a $DATA_DEST"
  machine_exists || die "no existe la máquina $MACHINE_NAME; ejecuta setup"

  if [[ "$(machine_state)" != running ]]; then
    run_start_command || die "no se pudo iniciar $MACHINE_NAME"
  fi
  verify_engine
  select_local_connection
  ok "máquina $MACHINE_NAME activa; conexión local predeterminada"
}

setup_machine() {
  local machines state
  require_podman
  prepare_external_storage
  machines="$(machine_names)" || die 'no se pudo consultar la lista de máquinas Podman'

  if machine_exists; then
    state="$(machine_state)"
    info "la máquina $MACHINE_NAME ya existe (estado: ${state:-desconocido})"
  else
    [[ -z "$machines" ]] || die "hay otra máquina Podman registrada ($machines); no se creará una máquina sin revisar primero el almacenamiento compartido"
    podman machine init \
      --provider applehv \
      --cpus "$CPUS" \
      --memory "$MEMORY_MIB" \
      --disk-size "$DISK_SIZE_GIB" \
      "$MACHINE_NAME"
  fi

  if [[ "$(machine_state)" != running ]]; then
    run_start_command || die "no se pudo iniciar $MACHINE_NAME"
  fi
  verify_engine
  select_local_connection
  ok "máquina $MACHINE_NAME lista en $MOUNT_POINT"
  info "disco virtual: ${DISK_SIZE_GIB} GiB; recursos: ${CPUS} CPU, $((MEMORY_MIB / 1024)) GiB RAM"
}

stop_machine() {
  validate_volume
  require_podman
  [[ -L "$CONFIG_SOURCE" && -L "$DATA_SOURCE" ]] || die 'la máquina aún no está vinculada al almacenamiento externo; ejecuta setup'
  machine_exists || die "no existe la máquina $MACHINE_NAME"

  if [[ "$(machine_state)" == running ]]; then
    podman machine stop "$MACHINE_NAME"
    ok "máquina $MACHINE_NAME detenida"
  else
    info "la máquina $MACHINE_NAME ya estaba detenida"
  fi
}

show_status() {
  require_podman
  validate_volume

  printf 'Volumen: %s\n' "$MOUNT_POINT"
  printf 'Máquina: %s\n' "$MACHINE_NAME"
  printf 'Archivos de configuración: %s -> %s\n' "$CONFIG_SOURCE" "$(readlink "$CONFIG_SOURCE" 2>/dev/null || printf 'sin enlace')"
  printf 'Archivos de máquina: %s -> %s\n' "$DATA_SOURCE" "$(readlink "$DATA_SOURCE" 2>/dev/null || printf 'sin enlace')"
  podman machine list
  printf '\nConexiones Podman:\n'
  podman system connection list
}

main() {
  require_macos
  local action="${1:-}"
  [[ $# -eq 1 ]] || { usage >&2; exit 2; }

  case "$action" in
    setup) setup_machine ;;
    start) require_podman; start_machine ;;
    stop) stop_machine ;;
    status) show_status ;;
    --help|-h|help) usage ;;
    *) usage >&2; die "acción desconocida: $action" ;;
  esac
}

main "$@"
