#!/usr/bin/env bash
# connect_nas_linux.sh v1.1.0
# Monta el TNAS mediante CIFS y SMB 3.1.1 usando credenciales protegidas.
set -Eeuo pipefail

NAS_SMB="${NAS_SMB:-//192.168.3.56/rafex}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/tnas}"
NAS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/samba"
NAS_CREDENTIALS="${NAS_CREDENTIALS:-$NAS_CONFIG_DIR/tnas.credentials}"
NAS_SMB_VERSION="${NAS_SMB_VERSION:-3.1.1}"
NAS_UID="${NAS_UID:-$(id -u)}"
NAS_GID="${NAS_GID:-$(id -g)}"
NAS_FILE_MODE="${NAS_FILE_MODE:-0644}"
NAS_DIR_MODE="${NAS_DIR_MODE:-0755}"

notify() {
  local urgency="$1" title="$2" message="$3"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$urgency" "$title" "$message" || true
  fi
}

fail() {
  local message="$1"
  printf 'Error: %s\n' "$message" >&2
  notify critical 'TNAS' "$message"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "falta '$1'; ejecuta 'just install-nas-client --apply'."
}

validate_options() {
  [[ "$NAS_SMB" =~ ^//[^/]+/[^/]+$ ]] || fail "NAS_SMB debe tener formato //servidor/recurso."
  [[ "$NAS_MOUNT_POINT" == /* ]] || fail "NAS_MOUNT_POINT debe ser una ruta absoluta."
  [[ "$NAS_CREDENTIALS" == /* ]] || fail "NAS_CREDENTIALS debe ser una ruta absoluta."
  [[ "$NAS_CREDENTIALS" != *,* && "$NAS_SMB" != *,* ]] ||
    fail "NAS_SMB y NAS_CREDENTIALS no pueden contener comas."
  [[ "$NAS_SMB_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    fail "NAS_SMB_VERSION debe ser una versión como 3.1.1."
  [[ "$NAS_UID" =~ ^[0-9]+$ && "$NAS_GID" =~ ^[0-9]+$ ]] ||
    fail "NAS_UID y NAS_GID deben ser enteros no negativos."
  [[ "$NAS_FILE_MODE" =~ ^0?[0-7]{3,4}$ && "$NAS_DIR_MODE" =~ ^0?[0-7]{3,4}$ ]] ||
    fail "NAS_FILE_MODE y NAS_DIR_MODE deben ser permisos octales."
}

secure_credentials() {
  [[ -f "$NAS_CREDENTIALS" && ! -L "$NAS_CREDENTIALS" && -r "$NAS_CREDENTIALS" ]] ||
    fail "no existe un archivo regular de credenciales legible en $NAS_CREDENTIALS."
  awk -F= '
    $1 ~ /^[[:space:]]*username[[:space:]]*$/ { username=1 }
    $1 ~ /^[[:space:]]*password[[:space:]]*$/ { password=1 }
    END { exit !(username && password) }
  ' "$NAS_CREDENTIALS" ||
    fail "el archivo de credenciales debe contener username= y password=."

  if [[ "$NAS_CREDENTIALS" == "$NAS_CONFIG_DIR/"* ]]; then
    chmod 700 -- "$NAS_CONFIG_DIR" ||
      fail "no se pudieron restringir los permisos de $NAS_CONFIG_DIR."
  fi
  chmod 600 -- "$NAS_CREDENTIALS" ||
    fail "no se pudieron restringir los permisos del archivo de credenciales."
}

main() {
  (($# == 0)) || fail 'este script no acepta argumentos; configura el montaje con variables NAS_*.'
  validate_options
  require_command mountpoint
  require_command findmnt
  require_command sudo

  if mountpoint -q -- "$NAS_MOUNT_POINT"; then
    local mounted_source
    mounted_source="$(findmnt -n -o SOURCE --target "$NAS_MOUNT_POINT" 2>/dev/null || true)"
    if [[ "$mounted_source" == "$NAS_SMB" ]]; then
      printf 'TNAS ya conectado en %s\n' "$NAS_MOUNT_POINT"
      notify low 'TNAS' "Ya conectado en $NAS_MOUNT_POINT"
      return 0
    fi
    fail "$NAS_MOUNT_POINT ya está ocupado por '${mounted_source:-un montaje desconocido}'."
  fi

  require_command mount.cifs
  secure_credentials

  if ! sudo mkdir -p -- "$NAS_MOUNT_POINT"; then
    fail "no se pudo crear el punto de montaje $NAS_MOUNT_POINT."
  fi

  local mount_options output status
  mount_options="credentials=$NAS_CREDENTIALS,uid=$NAS_UID,gid=$NAS_GID,iocharset=utf8,vers=$NAS_SMB_VERSION,file_mode=$NAS_FILE_MODE,dir_mode=$NAS_DIR_MODE"
  if output="$(sudo mount -t cifs "$NAS_SMB" "$NAS_MOUNT_POINT" -o "$mount_options" 2>&1)"; then
    if ! mountpoint -q -- "$NAS_MOUNT_POINT"; then
      fail "el comando de montaje terminó sin error, pero $NAS_MOUNT_POINT no aparece montado."
    fi
    printf 'TNAS montado en %s usando SMB %s\n' "$NAS_MOUNT_POINT" "$NAS_SMB_VERSION"
    notify normal 'TNAS' "Montado en $NAS_MOUNT_POINT (SMB $NAS_SMB_VERSION)"
  else
    status=$?
    printf '%s\n' "${output:-mount.cifs no devolvió detalles.}" >&2
    notify critical 'TNAS: error al montar' "${output:-mount.cifs no devolvió detalles.}"
    return "$status"
  fi
}

main "$@"
