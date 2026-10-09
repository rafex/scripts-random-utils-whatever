#!/bin/sh
# v1.2.0 - Sincroniza carpetas de rafex al volumen usbshare1 del TNAS.
set -eu

VERSION='v1.2.0'
SOURCE_DIR=${SYNC_SOURCE_DIR:-/home/rafex/home/discoExterno}
DEST_DIR=${SYNC_DEST_DIR:-/mnt/usb/usbshare1/discoExterno}
MOUNT_POINT='/mnt/usb/usbshare1'
RSYNC_BIN=${RSYNC_BIN:-/usr/bin/rsync}
DRY_RUN=0
VERIFY=0
RSYNC_PID=''
VERIFY_REPORT=''

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

terminate_rsync() {
  if [ -n "$RSYNC_PID" ] && kill -0 "$RSYNC_PID" 2>/dev/null; then
    kill -TERM "$RSYNC_PID" 2>/dev/null || true
    wait "$RSYNC_PID" 2>/dev/null || true
  fi
  RSYNC_PID=''
}

on_signal() {
  signal_name=$1
  trap - HUP INT TERM
  terminate_rsync
  printf 'Interrumpido por señal %s; el origen se conservó.\n' "$signal_name" >&2
  exit 128
}

cleanup_verify_report() {
  if [ -n "$VERIFY_REPORT" ]; then
    rm -f "$VERIFY_REPORT"
  fi
}

run_rsync() {
  "$RSYNC_BIN" "$@" &
  RSYNC_PID=$!
  if wait "$RSYNC_PID"; then
    rsync_status=0
  else
    rsync_status=$?
  fi
  RSYNC_PID=''
  return "$rsync_status"
}

trap 'on_signal HUP' HUP
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap cleanup_verify_report 0

usage() {
  cat <<EOF
Uso: $0 [--dry-run] [--verify] [--help]

Sincroniza en el propio TNAS desde:
  $SOURCE_DIR
hacia:
  $DEST_DIR

Opciones:
  --dry-run  Muestra lo que rsync copiaría, sin escribir.
  --verify   Después de copiar, compara el contenido mediante checksums.
  --help     Muestra esta ayuda.

La sincronización conserva archivos que existan solo en el destino; nunca borra
el origen ni usa --delete. Ejecuta con sudo para conservar propietario y grupo.
Como usuario normal copia los datos sin cambiar propietario ni grupo.
Versión: $VERSION
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verify) VERIFY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "opción desconocida: $1 (usa --help)" ;;
  esac
  shift
done

[ -d "$SOURCE_DIR" ] || die "no existe la carpeta de origen: $SOURCE_DIR"
[ ! -L "$SOURCE_DIR" ] || die 'el origen no puede ser un enlace simbólico'
case "$DEST_DIR" in
  "$MOUNT_POINT"/*) ;;
  *) die "el destino debe estar dentro de $MOUNT_POINT" ;;
esac

awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found=1 } END { exit !found }' /proc/mounts ||
  die "$MOUNT_POINT no está montado; se cancela para evitar copiar al disco interno"

[ -x "$RSYNC_BIN" ] || die "no se encontró rsync ejecutable en $RSYNC_BIN"

if [ "$(id -u)" -eq 0 ]; then
  RSYNC_ARGS='-a --partial --human-readable --info=progress2'
else
  RSYNC_ARGS='-rltO --partial --human-readable --info=progress2'
fi
if [ "$DRY_RUN" -eq 1 ]; then
  printf 'Simulación: no se modificarán archivos.\n'
  # shellcheck disable=SC2086
  run_rsync $RSYNC_ARGS --dry-run "$SOURCE_DIR/" "$DEST_DIR/"
  exit $?
fi

mkdir -p "$DEST_DIR"
printf 'Sincronizando %s -> %s\n' "$SOURCE_DIR" "$DEST_DIR"
# shellcheck disable=SC2086
run_rsync $RSYNC_ARGS "$SOURCE_DIR/" "$DEST_DIR/" ||
  die 'rsync no terminó correctamente; el origen sigue intacto y se puede volver a ejecutar'

if [ "$VERIFY" -eq 1 ]; then
  printf '\nVerificación por checksum; puede tardar porque lee todos los archivos.\n'
  VERIFY_REPORT="$(mktemp "${TMPDIR:-/tmp}/tnas-usb-verify.XXXXXX")" ||
    die 'no se pudo crear el informe temporal de verificación'
  if run_rsync -rcn --itemize-changes --out-format='%i %n%L' --quiet \
    "$SOURCE_DIR/" "$DEST_DIR/" > "$VERIFY_REPORT" 2>&1; then
    :
  else
    cat "$VERIFY_REPORT" >&2
    die 'falló la verificación por checksum'
  fi
  if [ -s "$VERIFY_REPORT" ]; then
    cat "$VERIFY_REPORT" >&2
    die 'la verificación encontró diferencias; conserva el origen y revisa el informe'
  fi
  printf 'Verificación por checksum completa: no hay diferencias.\n'
fi

printf 'Sincronización terminada. El origen se conservó.\n'
