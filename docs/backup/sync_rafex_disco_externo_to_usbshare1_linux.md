---
title: sync_rafex_disco_externo_to_usbshare1_linux.sh
description: Copia incremental local de la carpeta discoExterno de rafex al USB del TNAS
tags:
  - respaldo
  - TNAS
  - rsync
---

# sync_rafex_disco_externo_to_usbshare1_linux.sh

Sincroniza la carpeta `discoExterno` del usuario `rafex` al volumen USB
`usbshare1`, ejecutando la copia dentro del TNAS para evitar usar la red local.

- **Ruta:** `scripts/backup/sync_rafex_disco_externo_to_usbshare1_linux.sh`
- **SO requerido:** Linux (TNAS)
- **Dependencias:** `sh`, `rsync`, `awk`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Ejecutar el script en el TNAS, donde existen las rutas de origen y destino.
- El volumen debe estar montado exactamente en `/mnt/usb/usbshare1`.
- El usuario que lo ejecute necesita lectura en el origen y escritura en el destino.
- Como `root` conserva propietario, grupo, permisos y fechas. Como usuario normal
  conserva datos y fechas de archivos, pero omite tiempos de directorios y
  propietario/grupo/permisos; los archivos nuevos quedan a nombre del usuario
  que ejecuta el script.
- `rsync` debe estar disponible en `/usr/bin/rsync` (o configurar `RSYNC_BIN`).

## Uso

Desde la carpeta donde se guardó el script en el TNAS:

```sh
./sync_rafex_disco_externo_to_usbshare1_linux.sh --dry-run
./sync_rafex_disco_externo_to_usbshare1_linux.sh --verify
```

La ejecución normal actualiza los archivos nuevos o modificados. No borra
archivos del origen ni archivos que solo existan en el destino.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--dry-run` | — | Simula la copia sin escribir. |
| `--verify` | — | Compara al final todos los contenidos mediante checksums; vuelve a leer los datos y puede tardar. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Las variables de entorno prevalecen sobre las rutas predeterminadas. Al usar
`sudo`, pásalas con `sudo env NOMBRE=valor ...`.

| Variable | Default | Descripción |
|---|---|---|
| `SYNC_SOURCE_DIR` | `/home/rafex/home/discoExterno` | Carpeta de origen. |
| `SYNC_DEST_DIR` | `/mnt/usb/usbshare1/discoExterno` | Carpeta de destino; debe permanecer dentro de `/mnt/usb/usbshare1`. |
| `RSYNC_BIN` | `/usr/bin/rsync` | Ruta al ejecutable de rsync. |

## Ejemplos

### Forma explícita recomendada

```sh
./sync_rafex_disco_externo_to_usbshare1_linux.sh --dry-run
./sync_rafex_disco_externo_to_usbshare1_linux.sh --verify
```

### Con variables de entorno

```sh
env RSYNC_BIN=/usr/bin/rsync \
  ./sync_rafex_disco_externo_to_usbshare1_linux.sh --dry-run
```

### Origen alternativo

```sh
env SYNC_SOURCE_DIR=/home/rafex/home/otraCarpeta \
  ./sync_rafex_disco_externo_to_usbshare1_linux.sh --dry-run
```

## Protecciones de seguridad

- Comprueba que `usbshare1` esté montado antes de crear o escribir en el destino.
- Rechaza destinos fuera de `/mnt/usb/usbshare1`.
- La copia es incremental y unidireccional; no usa `--delete`.
- Conserva el origen para permitir reintentar una copia interrumpida.
- `--verify` compara contenidos con checksum después de la copia.
- `--dry-run` no modifica datos.

## Fallos conocidos

### `usbshare1 no está montado`

**Causa:** el TNAS no montó el volumen USB en la ruta esperada.

**Solución:** revisa el montaje del volumen y vuelve a ejecutar el script cuando
`/mnt/usb/usbshare1` corresponda al disco externo.

### `rsync no terminó correctamente`

**Causa:** falta de espacio, error de lectura/escritura o desconexión del USB.

**Solución:** conserva el origen, revisa el estado del disco y el espacio libre,
y vuelve a ejecutar el script; rsync copiará los archivos que falten o hayan
cambiado.

## Changelog

### [Unreleased]

- Preparado para sincronización incremental en el TNAS.

### v1.2.0 — 2026-10-08

**feat:** permitir copias sin privilegios de root.

- Como usuario normal, conserva datos, fechas de archivos y enlaces simbólicos sin intentar cambiar propietario, grupo, permisos o tiempos de directorios.

### v1.1.0 — 2026-10-08

**fix:** propagar señales a `rsync` y hacer que `--verify` falle ante diferencias.

- Captura TERM/INT/HUP y detiene el `rsync` activo antes de salir.
- Solo confirma la verificación por checksum cuando rsync no reporta diferencias.

### v1.0.0 — 2026-10-08

**feat:** agregar copia local de `discoExterno` al volumen USB del TNAS.

- Añade simulación, verificación por checksum y validación del punto de montaje.
