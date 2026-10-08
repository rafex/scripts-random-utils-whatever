#!/bin/sh
# Sincroniza la carpeta discoExterno de rafex al volumen usbshare1 del TNAS.
set -eu

VERSION='v1.0.0'
SOURCE_DIR=${SYNC_SOURCE_DIR:-/home/rafex/home/discoExterno}
DEST_DIR=${SYNC_DEST_DIR:-/mnt/usb/usbshare1/discoExterno}
MOUNT_POINT='/mnt/usb/usbshare1'
RSYNC_BIN=${RSYNC_BIN:-/usr/bin/rsync}
DRY_RUN=0
VERIFY=0

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

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

[ "$(id -u)" -eq 0 ] || die "ejecuta el script con sudo"
[ -d "$SOURCE_DIR" ] || die "no existe la carpeta de origen: $SOURCE_DIR"
[ ! -L "$SOURCE_DIR" ] || die 'el origen no puede ser un enlace simbólico'
case "$DEST_DIR" in
  "$MOUNT_POINT"/*) ;;
  *) die "el destino debe estar dentro de $MOUNT_POINT" ;;
esac

awk -v mount_point="$MOUNT_POINT" '$2 == mount_point { found=1 } END { exit !found }' /proc/mounts ||
  die "$MOUNT_POINT no está montado; se cancela para evitar copiar al disco interno"

[ -x "$RSYNC_BIN" ] || die "no se encontró rsync ejecutable en $RSYNC_BIN"

RSYNC_ARGS='-a --partial --human-readable --info=progress2'
if [ "$DRY_RUN" -eq 1 ]; then
  printf 'Simulación: no se modificarán archivos.\n'
  # shellcheck disable=SC2086
  "$RSYNC_BIN" $RSYNC_ARGS --dry-run "$SOURCE_DIR/" "$DEST_DIR/"
  exit $?
fi

mkdir -p "$DEST_DIR"
printf 'Sincronizando %s -> %s\n' "$SOURCE_DIR" "$DEST_DIR"
# shellcheck disable=SC2086
"$RSYNC_BIN" $RSYNC_ARGS "$SOURCE_DIR/" "$DEST_DIR/" ||
  die 'rsync no terminó correctamente; el origen sigue intacto y se puede volver a ejecutar'

if [ "$VERIFY" -eq 1 ]; then
  printf '\nVerificación por checksum; puede tardar porque lee todos los archivos.\n'
  "$RSYNC_BIN" -rcn --itemize-changes --out-format='%i %n%L' --quiet \
    "$SOURCE_DIR/" "$DEST_DIR/" || die 'falló la verificación por checksum'
  printf 'Verificación terminada. Si rsync no listó diferencias, el contenido coincide.\n'
fi

printf 'Sincronización terminada. El origen se conservó.\n'
