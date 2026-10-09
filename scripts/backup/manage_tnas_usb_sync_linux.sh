#!/bin/sh
# v1.2.0 - Acepta el nombre de carpeta para gestionar copias sin rutas manuales.
set -eu
umask 022

ACTION=''
DRY_RUN=0
SOURCE_NAME=''
SOURCE_DIR=${SYNC_SOURCE_DIR:-/home/rafex/home/discoExterno2}
DEST_DIR=${SYNC_DEST_DIR:-/mnt/usb/usbshare1/discoExterno2}
RSYNC_BIN=${RSYNC_BIN:-/usr/bin/rsync}
SYNC_SCRIPT=${SYNC_SCRIPT:-/home/admin/bin/sync_rafex_disco_externo_to_usbshare1_linux.sh}
START_STOP_DAEMON=${START_STOP_DAEMON:-/sbin/start-stop-daemon}
STATE_DIR=${SYNC_STATE_DIR:-/home/admin/var/tnas-usb-sync}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Uso: $0 start [<carpeta>] [--dry-run] | status [<carpeta>] | logs [<carpeta>] | stop [<carpeta>]

start ejecuta la copia en segundo plano y verifica con checksum al terminar.
El origen se conserva siempre. Al indicar una carpeta, las rutas se forman así:
  origen:  /home/rafex/home/<carpeta>
  destino: /mnt/usb/usbshare1/<carpeta>
Sin carpeta, usa SYNC_SOURCE_DIR, SYNC_DEST_DIR o estos valores predeterminados:
  origen:  $SOURCE_DIR
  destino: $DEST_DIR
EOF
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
ACTION=$1
shift
if [ "$#" -gt 0 ]; then
  case "$1" in
    --*) ;;
    *) SOURCE_NAME=$1; shift ;;
  esac
fi
if [ "$ACTION" = start ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
elif [ "$#" -gt 0 ]; then
  [ "$#" -eq 1 ] && [ "$1" = --help ] && { usage; exit 0; }
  die "$ACTION no acepta argumentos"
fi
[ "$ACTION" != help ] && [ "$ACTION" != -h ] && [ "$ACTION" != --help ] || { usage; exit 0; }

if [ -n "$SOURCE_NAME" ]; then
  case "$SOURCE_NAME" in
    .|..) die 'el nombre de carpeta no puede ser . ni ..' ;;
    *[!A-Za-z0-9._-]*) die 'el nombre de carpeta solo permite letras, números, punto, guion y guion bajo' ;;
  esac
  SOURCE_DIR=${SYNC_SOURCE_DIR:-/home/rafex/home/$SOURCE_NAME}
  DEST_DIR=${SYNC_DEST_DIR:-/mnt/usb/usbshare1/$SOURCE_NAME}
  JOB_NAME=${SYNC_JOB_NAME:-$SOURCE_NAME}
else
  SOURCE_DIR=${SYNC_SOURCE_DIR:-/home/rafex/home/discoExterno2}
  DEST_DIR=${SYNC_DEST_DIR:-/mnt/usb/usbshare1/discoExterno2}
  JOB_NAME=${SYNC_JOB_NAME:-${SOURCE_DIR##*/}}
fi

[ -x "$START_STOP_DAEMON" ] || die "no se encontró start-stop-daemon: $START_STOP_DAEMON"
[ -x "$SYNC_SCRIPT" ] || die "no se encontró el script de sincronización: $SYNC_SCRIPT"
[ -n "$JOB_NAME" ] || die 'SYNC_JOB_NAME no puede estar vacío'
case "$JOB_NAME" in
  *[!A-Za-z0-9._-]*) die 'SYNC_JOB_NAME solo permite letras, números, punto, guion y guion bajo' ;;
esac

mkdir -p "$STATE_DIR"
chmod 0755 "$STATE_DIR"
PID_FILE="$STATE_DIR/$JOB_NAME.pid"
LOG_FILE="$STATE_DIR/$JOB_NAME.log"

case "$ACTION" in
  start)
    if "$START_STOP_DAEMON" --status --pidfile "$PID_FILE" --exec /bin/sh >/dev/null 2>&1; then
      die "el trabajo '$JOB_NAME' ya está activo (PID $(cat "$PID_FILE"))"
    fi
    if [ -f "$PID_FILE" ]; then
      rm -f "$PID_FILE"
    fi
    [ -d "$SOURCE_DIR" ] || die "no existe el origen: $SOURCE_DIR"
    [ -r "$SOURCE_DIR" ] && [ -x "$SOURCE_DIR" ] || die "admin no puede leer el origen: $SOURCE_DIR"
    awk -v mount_point='/mnt/usb/usbshare1' '$2 == mount_point { found=1 } END { exit !found }' /proc/mounts \
      || die '/mnt/usb/usbshare1 no está montado'
    case "$DEST_DIR" in
      /mnt/usb/usbshare1/*) ;;
      *) die 'el destino debe estar dentro de /mnt/usb/usbshare1' ;;
    esac
    [ -x "$RSYNC_BIN" ] || die "no se encontró rsync: $RSYNC_BIN"
    printf '\n=== Inicio %s; trabajo=%s; origen=%s; destino=%s ===\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$JOB_NAME" "$SOURCE_DIR" "$DEST_DIR" >> "$LOG_FILE"
    chmod 0644 "$LOG_FILE"
    set --
    if [ "$DRY_RUN" -eq 1 ]; then
      set -- --dry-run
    else
      set -- --verify
    fi
    "$START_STOP_DAEMON" --start --background --no-close --make-pidfile \
      --pidfile "$PID_FILE" --exec /bin/sh --startas /usr/bin/env \
      -- SYNC_SOURCE_DIR="$SOURCE_DIR" SYNC_DEST_DIR="$DEST_DIR" \
      RSYNC_BIN="$RSYNC_BIN" "$SYNC_SCRIPT" "$@" \
      </dev/null >> "$LOG_FILE" 2>&1
    chmod 0644 "$PID_FILE"
    printf 'Trabajo iniciado: %s\nPID: %s\nRegistro: %s\n' \
      "$JOB_NAME" "$(cat "$PID_FILE")" "$LOG_FILE"
    ;;
  status)
    if "$START_STOP_DAEMON" --status --pidfile "$PID_FILE" --exec /bin/sh >/dev/null 2>&1; then
      printf 'En ejecución: %s (PID %s)\n' "$JOB_NAME" "$(cat "$PID_FILE")"
    elif [ -f "$PID_FILE" ]; then
      if grep -q 'Sincronización terminada. El origen se conservó.' "$LOG_FILE" 2>/dev/null; then
        printf 'Completado; el origen sigue intacto.\n'
      else
        printf 'Detenido o fallido; revisa el registro. El origen sigue intacto.\n'
      fi
      printf 'Registro: %s\n' "$LOG_FILE"
    else
      printf 'No hay un trabajo activo llamado %s.\n' "$JOB_NAME"
      exit 3
    fi
    ;;
  logs)
    [ -f "$LOG_FILE" ] || die "no existe el registro: $LOG_FILE"
    tail -n 80 "$LOG_FILE"
    ;;
  stop)
    if "$START_STOP_DAEMON" --status --pidfile "$PID_FILE" --exec /bin/sh >/dev/null 2>&1; then
      "$START_STOP_DAEMON" --stop --pidfile "$PID_FILE" --exec /bin/sh \
        --retry 10/TERM/10/KILL/5 --remove-pidfile
      printf 'Trabajo detenido; se intentó terminar rsync de forma controlada.\n'
    else
      [ ! -f "$PID_FILE" ] || rm -f "$PID_FILE"
      printf 'No había un proceso activo.\n'
    fi
    ;;
  *) usage >&2; die "acción desconocida: $ACTION" ;;
esac
