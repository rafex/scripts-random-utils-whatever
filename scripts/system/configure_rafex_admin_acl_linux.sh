#!/bin/bash
set -Eeuo pipefail

# v1.0.0 - Gestiona ACL reversibles para que admin pueda modificar /home/rafex.

readonly SCRIPT_NAME="${0##*/}"
readonly BACKUP_ROOT="/home/admin/var/rafex-admin-acl-backups"
readonly DEFAULT_ROOT="/home/rafex"
readonly ADMIN_USER="admin"

ACTION="check"
ROOT_PATH="$DEFAULT_ROOT"
ROOT_WAS_SET=0
RESTORE_FILE=""
ACTION_SELECTED=0
ORIGINAL_ARGS=("$@")

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  $SCRIPT_NAME [--check | --dry-run | --apply | --restore <respaldo>] [--root <ruta>]

Acciones:
  --check             Informa el estado ACL (predeterminado; no modifica).
  --dry-run           Simula las ACL que aplicaría, sin escribir cambios.
  --apply             Respalda ACL y da rwX a $ADMIN_USER en el árbol indicado.
  --restore <archivo> Restaura las ACL desde un respaldo creado por este script.
  --root <ruta>       Árbol a revisar o modificar (default: $DEFAULT_ROOT).
  -h, --help          Muestra esta ayuda.

La ACL predeterminada de cada directorio también se actualiza para contenido
nuevo. Los enlaces simbólicos no se siguen. --apply y --restore usan sudo si
el usuario actual no puede administrar ACL en el árbol.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--dry-run|--apply)
        (( ACTION_SELECTED == 0 )) || die 'elige una sola acción'
        ACTION="${1#--}"
        ACTION_SELECTED=1
        shift
        ;;
      --restore)
        (( ACTION_SELECTED == 0 )) || die 'elige una sola acción'
        (($# >= 2)) || die '--restore requiere un archivo de respaldo'
        ACTION="restore"
        RESTORE_FILE="$2"
        ACTION_SELECTED=1
        shift 2
        ;;
      --root)
        (($# >= 2)) || die '--root requiere una ruta'
        ROOT_PATH="$2"
        ROOT_WAS_SET=1
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
}

require_linux_and_tools() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Linux'
  local command_name
  for command_name in awk chmod chown cmp date find getfacl head id mkdir mktemp rm sed setfacl sort stat; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
  id "$ADMIN_USER" >/dev/null 2>&1 || die "no existe el usuario $ADMIN_USER"
}

resolve_root() {
  [[ "$ROOT_PATH" == /* ]] || die '--root debe ser una ruta absoluta'
  [[ -d "$ROOT_PATH" ]] || die "no existe el directorio: $ROOT_PATH"
  [[ ! -L "$ROOT_PATH" ]] || die '--root no puede ser un enlace simbólico'
  ROOT_PATH="$(cd -- "$ROOT_PATH" && pwd -P)"
  [[ "$ROOT_PATH" != / ]] || die 'por seguridad no se permite modificar /'
  [[ "$ROOT_PATH" != /home ]] || die 'por seguridad no se permite modificar /home'
}

backup_dir() {
  if (( EUID == 0 )); then
    printf '%s\n' "$BACKUP_ROOT"
  else
    printf '%s/rafex-admin-acl-backups\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
  fi
}

ensure_acl_privilege() {
  (( EUID == 0 )) && return 0

  local root_owner current_uid
  root_owner="$(stat -c '%u' -- "$ROOT_PATH")" || die 'no se pudo determinar el propietario del árbol'
  current_uid="$(id -u)"
  if [[ "$root_owner" == "$current_uid" ]]; then
    return 0
  fi

  command -v sudo >/dev/null 2>&1 || die 'se requieren privilegios root y no está disponible sudo'
  info 'Se solicitarán privilegios sudo para administrar las ACL.'
  exec sudo -- "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
}

validate_restore_file() {
  local directory expected_root backup_name
  directory="$(backup_dir)"
  [[ "$RESTORE_FILE" == "$directory/"* ]] ||
    die "el respaldo debe estar dentro de $directory"
  backup_name="${RESTORE_FILE#"$directory"/}"
  [[ "$backup_name" != */* && "$backup_name" == rafex-home-acl-*.acl ]] ||
    die 'el respaldo debe ser un archivo generado directamente en el directorio de respaldos'
  [[ ! -L "$directory" ]] || die 'el directorio de respaldos no puede ser un enlace simbólico'
  [[ -f "$RESTORE_FILE" && ! -L "$RESTORE_FILE" ]] || die 'el respaldo no existe o no es un archivo regular'
  expected_root="$(sed -n 's/^# RAFEX_ADMIN_ACL_ROOT=//p' "$RESTORE_FILE" | head -n 1)"
  [[ -n "$expected_root" ]] || die 'el respaldo no contiene la ruta de origen esperada'
  if (( ROOT_WAS_SET )) && [[ "$ROOT_PATH" != "$expected_root" ]]; then
    die "--root no coincide con el respaldo ($expected_root)"
  fi
  ROOT_PATH="$expected_root"
  [[ -d "$ROOT_PATH" && ! -L "$ROOT_PATH" ]] || die "no existe la ruta original del respaldo: $ROOT_PATH"
  ROOT_PATH="$(cd -- "$ROOT_PATH" && pwd -P)"
  [[ "$ROOT_PATH" == "$expected_root" ]] || die 'la ruta del respaldo ya no resuelve al mismo árbol'
}

new_backup() {
  local directory timestamp
  directory="$(backup_dir)"
  mkdir -p -- "$directory"
  chmod 700 -- "$directory"
  if (( EUID == 0 )); then
    chown root:root -- "$directory"
  fi
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_FILE="$directory/rafex-home-acl-$timestamp-$$.acl"
  umask 077
  {
    printf '# RAFEX_ADMIN_ACL_ROOT=%s\n' "$ROOT_PATH"
    getfacl -R -P -p -- "$ROOT_PATH" | awk '!/^# (owner|group|flags):/'
  } > "$BACKUP_FILE" || die 'no se pudieron guardar las ACL; no se aplicaron cambios'
  chmod 600 -- "$BACKUP_FILE"
}

acl_effective_dump() {
  local root="$1" destination="$2"
  getfacl -R -P -e -p -- "$root" |
    awk '
      /^# file: / { path = $0; next }
      /^#/ || /^$/ { next }
      {
        if ($0 ~ /^default:/) next
        full = $0
        effective = ""
        if (match(full, /#effective:/)) {
          effective = substr(full, RSTART + 11)
          sub(/[[:space:]].*$/, "", effective)
        }
        base = full
        sub(/[[:space:]]+#effective:.*/, "", base)
        count = split(base, fields, ":")
        permission = fields[count]
        key = substr(base, 1, length(base) - length(permission) - 1)
        if (key == "mask:" || key == "default:mask:" || key == "user:admin" || key == "default:user:admin") next
        if (effective == "") effective = permission
        printf "%s|%s|%s\n", path, key, effective
      }
    ' | LC_ALL=C sort > "$destination"
}

acl_default_effective_dump() {
  local root="$1" destination="$2"
  {
    printf '# snapshot\n'
    getfacl -R -P -e -p -- "$root"
  } | awk '
    /^# file: / { path = $0; next }
    /^#/ || /^$/ { next }
    /^default:/ {
      full = $0
      effective = ""
      if (match(full, /#effective:/)) {
        effective = substr(full, RSTART + 11)
        sub(/[[:space:]].*$/, "", effective)
      }
      base = full
      sub(/[[:space:]]+#effective:.*/, "", base)
      count = split(base, fields, ":")
      permission = fields[count]
      key = substr(base, 1, length(base) - length(permission) - 1)
      if (key == "default:mask:" || key == "default:user:admin") next
      if (effective == "") effective = permission
      printf "%s|%s|%s\n", path, key, effective
    }
  ' | LC_ALL=C sort > "$destination"
}

existing_default_acl_rights_unchanged() {
  local before="$1" after="$2"
  awk -F'|' '
    FNR == NR {
      if ($0 !~ /^#/) old[$1 SUBSEP $2] = $3
      next
    }
    $0 !~ /^#/ {
      key = $1 SUBSEP $2
      if (key in old) {
        seen[key] = 1
        if (old[key] != $3) changed = 1
      }
    }
    END {
      for (key in old) if (!(key in seen)) changed = 1
      exit changed
    }
  ' "$before" "$after"
}

count_paths() {
  local root="$1" type="$2" count=0 ignored listing
  listing="$(mktemp)"
  find "$root" -type "$type" -print0 > "$listing" || {
    rm -f -- "$listing"
    die "no se pudo recorrer $root"
  }
  while IFS= read -r -d '' ignored; do
    : "$ignored"
    count=$((count + 1))
  done < "$listing"
  rm -f -- "$listing"
  printf '%s\n' "$count"
}

check_acl() {
  local access_count default_count no_access_rw no_access_traverse
  local entries_with_no_admin summary_file
  local default_no_rw directories objects output_file
  output_file="$(mktemp)"
  find "$ROOT_PATH" \( -type d -o -type f \) -exec getfacl -e -p -- {} + > "$output_file" || {
    rm -f -- "$output_file"
    die 'no se pudieron leer todas las ACL del árbol'
  }
  directories="$(count_paths "$ROOT_PATH" d)"
  objects=$((directories + $(count_paths "$ROOT_PATH" f)))

  summary_file="$(mktemp)"
  awk '
      function rights(line, is_default, value, parts) {
        value = line
        if (is_default) sub(/^default:user:admin:/, "", value)
        else sub(/^user:admin:/, "", value)
        if (value ~ /#effective:/) sub(/^.*#effective:/, "", value)
        split(value, parts, /[[:space:]]+/)
        return parts[1]
      }
      function finish_entry() {
        if (!seen) return
        objects++
        if (!access_found) missing_access++
        if (default_found) {
          defaults++
          if (default_rights !~ /r/ || default_rights !~ /w/) bad_default++
          if (access_rights !~ /x/) bad_traverse++
        }
        if (access_found && (access_rights !~ /r/ || access_rights !~ /w/)) bad_access++
      }
      /^# file: / {
        finish_entry()
        seen = 1
        access_found = 0
        default_found = 0
        access_rights = ""
        default_rights = ""
      }
      /^user:admin:/ {
        access_found = 1
        access_rights = rights($0, 0)
      }
      /^default:user:admin:/ {
        default_found = 1
        default_rights = rights($0, 1)
      }
      END {
        finish_entry()
        printf "%d %d %d %d %d %d\n", objects - (missing_access + 0), missing_access, bad_access, bad_traverse, defaults, bad_default
      }
    ' "$output_file" > "$summary_file"
  read -r access_count entries_with_no_admin no_access_rw no_access_traverse default_count default_no_rw < "$summary_file"
  rm -f -- "$output_file"
  rm -f -- "$summary_file"

  printf 'Ruta: %s\n' "$ROOT_PATH"
  printf 'Objetos regulares/directorios: %s; ACL de acceso admin: %s\n' "$objects" "$access_count"
  printf 'Directorios: %s; ACL predeterminadas admin: %s\n' "$directories" "$default_count"

  if (( access_count == objects && entries_with_no_admin == 0 && no_access_rw == 0 && no_access_traverse == 0 &&
        default_count == directories && default_no_rw == 0 )); then
    ok "$ADMIN_USER tiene escritura efectiva en el árbol y herencia en directorios."
    return 0
  fi
  warn 'faltan permisos ACL efectivos o ACL predeterminadas; ejecuta --dry-run y luego --apply.'
  return 1
}

dry_run() {
  info "Simulando ACL de acceso para $ADMIN_USER en $ROOT_PATH..."
  setfacl --test -R -P -m "u:$ADMIN_USER:rwX" -- "$ROOT_PATH" >/dev/null ||
    die 'setfacl no pudo simular las ACL de acceso'
  find "$ROOT_PATH" -type d -exec setfacl --test -m "d:u:$ADMIN_USER:rwx" -- {} + >/dev/null ||
    die 'setfacl no pudo simular las ACL predeterminadas'
  ok 'la simulación terminó sin errores; no se modificó ninguna ACL.'
}

apply_acl() {
  local before after before_defaults after_defaults
  ensure_acl_privilege
  before="$(mktemp)"
  after="$(mktemp)"
  before_defaults="$(mktemp)"
  after_defaults="$(mktemp)"
  trap 'rm -f -- "${before:-}" "${after:-}" "${before_defaults:-}" "${after_defaults:-}"' EXIT

  acl_effective_dump "$ROOT_PATH" "$before" || die 'no se pudieron auditar las ACL actuales'
  acl_default_effective_dump "$ROOT_PATH" "$before_defaults" || die 'no se pudieron auditar las ACL predeterminadas actuales'
  new_backup
  info "Respaldo previo: $BACKUP_FILE"

  if ! setfacl -R -P -m "u:$ADMIN_USER:rwX" -- "$ROOT_PATH"; then
    setfacl --restore="$BACKUP_FILE" || die "falló la ACL y su restauración; conserva $BACKUP_FILE"
    die "falló la ACL de acceso; conserva el respaldo: $BACKUP_FILE"
  fi
  if ! find "$ROOT_PATH" -type d -exec setfacl -m "d:u:$ADMIN_USER:rwx" -- {} +; then
    warn 'falló la ACL predeterminada; restaurando el respaldo.'
    setfacl --restore="$BACKUP_FILE" || die "falló la restauración; respaldo: $BACKUP_FILE"
    die 'se restauraron las ACL previas; no se completó el cambio'
  fi

  acl_effective_dump "$ROOT_PATH" "$after" || {
    setfacl --restore="$BACKUP_FILE" || die "no se pudo auditar ni restaurar; respaldo: $BACKUP_FILE"
    die 'se restauraron las ACL previas porque falló la auditoría posterior'
  }
  acl_default_effective_dump "$ROOT_PATH" "$after_defaults" || {
    setfacl --restore="$BACKUP_FILE" || die "no se pudo auditar ni restaurar; respaldo: $BACKUP_FILE"
    die 'se restauraron las ACL previas porque falló la auditoría posterior'
  }
  if ! cmp -s -- "$before" "$after" || ! existing_default_acl_rights_unchanged "$before_defaults" "$after_defaults"; then
    warn 'el cambio alteraría permisos efectivos de otras entradas ACL; restaurando el respaldo.'
    setfacl --restore="$BACKUP_FILE" || die "falló la restauración; respaldo: $BACKUP_FILE"
    die 'se restauraron las ACL previas para no ampliar permisos de otros usuarios o grupos'
  fi

  ok "ACL aplicadas para $ADMIN_USER; no cambiaron los permisos efectivos de otros usuarios o grupos."
  ok "Para revertir: $SCRIPT_NAME --restore $BACKUP_FILE"
}

restore_acl() {
  local rollback_file
  ensure_acl_privilege
  new_backup
  rollback_file="$BACKUP_FILE"
  info "Respaldo del estado actual: $rollback_file"
  info "Restaurando ACL desde $RESTORE_FILE..."
  if ! setfacl -R -P -x "u:$ADMIN_USER" -- "$ROOT_PATH"; then
    setfacl --restore="$rollback_file" || die "falló la restauración y su reversión; conserva $rollback_file"
    die "no se pudieron quitar ACL de acceso posteriores al respaldo; se restauró el estado anterior"
  fi
  if ! find "$ROOT_PATH" -type d -exec setfacl -k -- {} +; then
    setfacl --restore="$rollback_file" || die "falló la restauración y su reversión; conserva $rollback_file"
    die "no se pudieron quitar ACL predeterminadas posteriores al respaldo; se restauró el estado anterior"
  fi
  if ! setfacl --restore="$RESTORE_FILE"; then
    setfacl --restore="$rollback_file" || die "falló la restauración y su reversión; conserva $rollback_file"
    die 'setfacl no pudo restaurar el respaldo; se recuperó el estado anterior'
  fi
  ok "ACL restauradas para $ROOT_PATH."
}

main() {
  parse_args "$@"
  require_linux_and_tools
  if [[ "$ACTION" == restore ]]; then
    if (( EUID != 0 )) && [[ "$RESTORE_FILE" == "$BACKUP_ROOT/"* ]]; then
      command -v sudo >/dev/null 2>&1 || die 'se requieren privilegios root y no está disponible sudo'
      info 'Se solicitarán privilegios sudo para restaurar el respaldo.'
      exec sudo -- "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
    fi
    validate_restore_file
  else
    resolve_root
  fi

  case "$ACTION" in
    check) check_acl ;;
    dry-run) dry_run ;;
    apply) apply_acl ;;
    restore) restore_acl ;;
    *) die "acción interna desconocida: $ACTION" ;;
  esac
}

SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}"
main "$@"
