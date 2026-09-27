#!/usr/bin/env bash
# shellcheck shell=bash
# Sincroniza ~/.age desde macOS/Linux hacia ~/.age en una ThinkPad por SSH.
set -Eeuo pipefail
umask 077

ACTION=''
TARGET=''
SOURCE_DIR="${HOME}/.age"
IDENTITY=''
PORT=''
BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMP_LOG=''
SSH_ARGS=()
RSYNC_SSH=''

cleanup() {
  if [[ -n "$TMP_LOG" && -f "$TMP_LOG" ]]; then
    rm -f -- "$TMP_LOG"
  fi
}
trap cleanup EXIT

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso:
  sync_age_to_thinkpad_unix.sh --check --target <usuario@host|alias>
  sync_age_to_thinkpad_unix.sh --plan --target <usuario@host|alias>
  sync_age_to_thinkpad_unix.sh --status --target <usuario@host|alias>
  sync_age_to_thinkpad_unix.sh --apply --target <usuario@host|alias>

Copia ~/.age de forma unidireccional hacia ~/.age del destino remoto usando
rsync sobre SSH. Actualiza archivos nuevos o modificados, nunca usa --delete
y guarda los archivos reemplazados en un respaldo remoto fechado.

Opciones:
  --target <destino>    Destino SSH obligatorio; ejemplo: rafex@192.168.3.91
  --source <directorio> Origen local; default: ~/.age
  --identity <archivo>  Clave privada SSH opcional
  --port <puerto>       Puerto SSH opcional
  --check               Valida origen, herramientas y destino sin copiar
  --plan                Ejecuta una simulación sin modificar ningún archivo
  --status              Muestra estado resumido, sin nombres ni contenido
  --apply               Ejecuta la sincronización
  --help, -h            Muestra esta ayuda
EOF
}

expand_home() {
  case "$1" in
    \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    \~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check|--plan|--status|--apply)
        [[ -z "$ACTION" ]] || die 'selecciona una sola acción'
        ACTION="${1#--}"
        ;;
      --target)
        (($# >= 2)) || die '--target requiere un valor'
        [[ -z "$TARGET" ]] || die '--target no puede repetirse'
        TARGET="$2"
        shift
        ;;
      --source)
        (($# >= 2)) || die '--source requiere un valor'
        SOURCE_DIR="$2"
        shift
        ;;
      --identity)
        (($# >= 2)) || die '--identity requiere un valor'
        IDENTITY="$2"
        shift
        ;;
      --port)
        (($# >= 2)) || die '--port requiere un valor'
        PORT="$2"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ -n "$ACTION" ]] || die 'debes indicar --check, --plan, --status o --apply'
  [[ -n "$TARGET" ]] || die '--target es obligatorio en cada ejecución'
  [[ "$TARGET" != -* && "$TARGET" != *[[:space:]]* ]] || die 'destino SSH inválido'
  [[ "$TARGET" != *:* || "$TARGET" == \[*\]:* ]] || die 'usa --port para el puerto SSH'
  if [[ -n "$PORT" ]]; then
    [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] ||
      die 'el puerto debe estar entre 1 y 65535'
  fi
  SOURCE_DIR="$(expand_home "$SOURCE_DIR")"
  if [[ -n "$IDENTITY" ]]; then
    IDENTITY="$(expand_home "$IDENTITY")"
  fi
}

require_local_tools() {
  local command_name
  for command_name in ssh rsync find date mktemp; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando local: $command_name"
  done
  [[ -d "$SOURCE_DIR" ]] || die "no existe el origen: ~/.age"
  [[ ! -L "$SOURCE_DIR" ]] || die 'el origen ~/.age no puede ser un enlace simbólico'
  [[ "$SOURCE_DIR" != / && "$SOURCE_DIR" != "$HOME" ]] || die 'origen demasiado amplio'
  [[ -r "$SOURCE_DIR" && -x "$SOURCE_DIR" ]] || die 'el origen no es legible'
  if [[ -n "$IDENTITY" ]]; then
    [[ -f "$IDENTITY" && ! -L "$IDENTITY" ]] || die 'la identidad SSH no es un archivo regular'
  fi
  if [[ -n "$(find "$SOURCE_DIR" -type l -print -quit)" ]]; then
    die 'el origen contiene enlaces simbólicos; se rechaza para proteger claves'
  fi
  if [[ -n "$(find "$SOURCE_DIR" ! -type d ! -type f -print -quit)" ]]; then
    die 'el origen contiene archivos especiales; solo se permiten archivos y directorios'
  fi
}

build_ssh() {
  SSH_ARGS=(
    ssh
    -o BatchMode=yes
    -o StrictHostKeyChecking=yes
    -o ConnectTimeout=10
  )
  [[ -n "$IDENTITY" ]] && SSH_ARGS+=(-i "$IDENTITY")
  [[ -n "$PORT" ]] && SSH_ARGS+=(-p "$PORT")

  RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10'
  if [[ -n "$IDENTITY" ]]; then
    local quoted_identity
    printf -v quoted_identity '%q' "$IDENTITY"
    RSYNC_SSH+=" -i ${quoted_identity}"
  fi
  [[ -n "$PORT" ]] && RSYNC_SSH+=" -p ${PORT}"
}

remote_preflight() {
  local remote_command
  # shellcheck disable=SC2016
  remote_command='set -eu
command -v rsync >/dev/null 2>&1
[ "$(id -u)" -ne 0 ]
[ -d "$HOME" ]
[ -w "$HOME" ]
if [ -e "$HOME/.age" ]; then
  [ -d "$HOME/.age" ]
  [ ! -L "$HOME/.age" ]
fi
printf "%s\\n" ready'
  "${SSH_ARGS[@]}" "$TARGET" "$remote_command" >/dev/null 2>&1 ||
    die 'no se pudo validar SSH, rsync remoto, HOME o ~/.age en el destino'
}

remote_status() {
  local remote_command
  # shellcheck disable=SC2016
  remote_command='set -eu
if [ -L "$HOME/.age" ]; then
  printf "%s\\n" destination=symlink
elif [ -d "$HOME/.age" ]; then
  printf "%s\\n" destination=present
  printf "files=%s\\n" "$(find "$HOME/.age" -type f 2>/dev/null | wc -l | tr -d " ")"
  printf "size_kib=%s\\n" "$(du -sk "$HOME/.age" 2>/dev/null | awk "{print \\$1}")"
else
  printf "%s\\n" destination=absent
fi
if [ -d "$HOME/.local/share/rafex/age-sync-backups" ]; then
  printf "backup_sets=%s\\n" "$(find "$HOME/.local/share/rafex/age-sync-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d " ")"
else
  printf "%s\\n" backup_sets=0
fi'
  "${SSH_ARGS[@]}" "$TARGET" "$remote_command" 2>/dev/null ||
    die 'no se pudo consultar el estado remoto sin exponer nombres o contenido'
}

source_status() {
  local file_count
  file_count="$(find "$SOURCE_DIR" -type f -print | wc -l | tr -d ' ')"
  printf 'source=~/.age\n'
  printf 'source_files=%s\n' "$file_count"
  printf 'policy=update_without_delete\n'
  printf 'remote_target=~/.age\n'
}

prepare_remote_backup() {
  local remote_command
  remote_command="set -eu
umask 077
mkdir -p \"\$HOME/.local/share/rafex/age-sync-backups/$BACKUP_STAMP\"
chmod 700 \"\$HOME/.local/share/rafex/age-sync-backups/$BACKUP_STAMP\""
  "${SSH_ARGS[@]}" "$TARGET" "$remote_command" >/dev/null 2>&1 ||
    die 'no se pudo crear el respaldo remoto privado'
}

run_rsync() {
  local mode="$1"
  local -a rsync_args
  rsync_args=(
    -a
    --quiet
    --backup
    --backup-dir="../.local/share/rafex/age-sync-backups/$BACKUP_STAMP"
    '--chmod=Du=rwx,Dgo=,Fu=rw,Fgo='
  )
  [[ "$mode" == plan ]] && rsync_args+=(--dry-run)
  TMP_LOG="$(mktemp -t rafex-age-sync)"
  if ! rsync "${rsync_args[@]}" -e "$RSYNC_SSH" \
      "$SOURCE_DIR/" "$TARGET:~/.age/" >"$TMP_LOG" 2>&1; then
    die 'rsync no pudo completar la operación; no se muestran detalles para proteger nombres sensibles'
  fi
}

main() {
  parse_args "$@"
  require_local_tools
  build_ssh
  remote_preflight

  case "$ACTION" in
    check)
      source_status
      ok 'origen, SSH, rsync local/remoto y destino validados; no se copió nada'
      ;;
    status)
      source_status
      remote_status
      ;;
    plan)
      source_status
      run_rsync plan
      ok 'plan validado; no se modificó el origen ni el destino'
      ;;
    apply)
      source_status
      prepare_remote_backup
      run_rsync apply
      ok "sincronización completada; reemplazos en respaldo remoto fechado (${BACKUP_STAMP})"
      ;;
  esac
}

main "$@"
