#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# connect_nas_linux.sh
# Monta un recurso compartido CIFS/SMB en /mnt/nas usando credenciales.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas}"
SMB="${NAS_SMB:-//192.168.3.56/rafex}"
CREDENTIALS="${NAS_CREDENTIALS:-/home/rafex/.smbcredentials}"
OPTS="credentials=${CREDENTIALS},uid=${NAS_UID:-1000},gid=${NAS_GID:-1000},file_mode=0644,dir_mode=0755"

if mountpoint -q "$MOUNT_POINT"; then
  notify-send -u low "NAS" "Ya conectado en $MOUNT_POINT"
  exit 0
fi

if [[ ! -d "$MOUNT_POINT" ]]; then
  if ! sudo mkdir -p "$MOUNT_POINT"; then
    notify-send -u critical "NAS" "No se pudo crear $MOUNT_POINT"
    exit 1
  fi
fi

OUTPUT=$(sudo mount -t cifs "$SMB" "$MOUNT_POINT" -o "$OPTS" 2>&1)
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
  notify-send -u normal "NAS" "Montado en $MOUNT_POINT"
else
  notify-send -u critical "NAS: error al montar" "$OUTPUT"
  exit $STATUS
fi
