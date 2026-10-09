---
title: manage_tnas_usb_sync_linux.sh
description: Mantiene y supervisa copias locales del TNAS usando start-stop-daemon.
tags:
  - respaldo
  - TNAS
  - rsync
  - start-stop-daemon
---

# manage_tnas_usb_sync_linux.sh

Inicia en segundo plano el script de sincronización local del TNAS mediante
`start-stop-daemon`, registra el PID y guarda el progreso para consultar,
detener o verificar el resultado aunque se cierre SSH.

- **Ruta:** `scripts/backup/manage_tnas_usb_sync_linux.sh`
- **SO requerido:** Linux (TNAS)
- **Dependencias:** `sh`, `awk`, `grep`, `tail`, `start-stop-daemon`, `rsync`

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

- Ejecutar en el TNAS como el mismo usuario que tiene acceso de lectura al origen
  y escritura en el destino; para estas copias, `admin`.
- Tener montado el volumen en `/mnt/usb/usbshare1`.
- Tener instalados el script `sync_rafex_disco_externo_to_usbshare1_linux.sh` y `rsync`.
- El gestor usa `/home/admin/var/tnas-usb-sync` para PID y registros; su dueño
  debe ser `admin` para ejecutar sin `sudo`.

## Uso

```sh
./manage_tnas_usb_sync_linux.sh start discoExterno3
./manage_tnas_usb_sync_linux.sh status discoExterno3
./manage_tnas_usb_sync_linux.sh logs discoExterno3
./manage_tnas_usb_sync_linux.sh stop discoExterno3
```

La acción `start` realiza la copia y una comparación por checksum. El origen
no se borra, incluso si la tarea falla o se detiene. Solo se debe borrar tras
revisar el registro y confirmar que la verificación no informó diferencias.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `start [<carpeta>]` | — | Lanza la sincronización desacoplada de SSH y verifica por checksum al final. Al indicar carpeta usa `/home/rafex/home/<carpeta>` y `/mnt/usb/usbshare1/<carpeta>`. |
| `start [<carpeta>] --dry-run` | — | Ejecuta una simulación en segundo plano. |
| `status [<carpeta>]` | — | Informa si está activa o si terminó según el registro. |
| `logs [<carpeta>]` | — | Muestra las últimas 80 líneas del registro. |
| `stop [<carpeta>]` | — | Envía TERM, espera y recurre a KILL si hace falta; el script detiene rsync hijo. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `<carpeta>` | — | Nombre simple de carpeta; deriva origen, destino e identificador de registro. Solo permite letras, números, `.`, `_` y `-`; no acepta `.` ni `..`. |
| `SYNC_SOURCE_DIR` | `/home/rafex/home/discoExterno2` | Carpeta de origen; prevalece sobre la ruta derivada del argumento. |
| `SYNC_DEST_DIR` | `/mnt/usb/usbshare1/discoExterno2` | Carpeta de destino dentro del volumen USB; prevalece sobre la ruta derivada del argumento. |
| `SYNC_JOB_NAME` | Nombre base del origen o `<carpeta>` | Identificador seguro de PID y registro. |
| `SYNC_STATE_DIR` | `/home/admin/var/tnas-usb-sync` | Carpeta para estado y registro. |
| `SYNC_SCRIPT` | `/home/admin/bin/sync_rafex_disco_externo_to_usbshare1_linux.sh` | Script de sincronización. |
| `RSYNC_BIN` | `/usr/bin/rsync` | Ejecutable rsync utilizado por el script de sincronización. |
| `START_STOP_DAEMON` | `/sbin/start-stop-daemon` | Administrador de procesos en el TNAS. |

## Ejemplos

### Copiar una carpeta indicando solo su nombre

```sh
./manage_tnas_usb_sync_linux.sh start discoExterno3
./manage_tnas_usb_sync_linux.sh status discoExterno3
./manage_tnas_usb_sync_linux.sh logs discoExterno3
```

### Modo compatible con rutas personalizadas

```sh
env SYNC_SOURCE_DIR=/home/rafex/home/discoExterno \
  SYNC_DEST_DIR=/mnt/usb/usbshare1/discoExterno \
  SYNC_JOB_NAME=discoExterno \
  ./manage_tnas_usb_sync_linux.sh start
```

Si no se indica `<carpeta>` ni variables de entorno, se mantiene el valor
predeterminado `discoExterno2`.

### Detener de forma controlada

```sh
./manage_tnas_usb_sync_linux.sh stop
```

## Protecciones de seguridad

- Requiere que el punto de montaje USB esté activo antes de iniciar.
- Rechaza destinos fuera de `/mnt/usb/usbshare1`.
- No usa `rsync --delete` y nunca borra el origen.
- Guarda PID y registro en un directorio dedicado para permitir reanudar y auditar.
- Al detener, el script principal captura TERM y termina su proceso `rsync` hijo.

## Fallos conocidos

### `el volumen usbshare1 no está montado`

**Causa:** el TNAS no montó el volumen en la ruta prevista.

**Solución:** revisa el montaje y vuelve a iniciar cuando `/mnt/usb/usbshare1` esté activo.

### `el trabajo ya está activo`

**Causa:** ya hay una copia con el mismo `SYNC_JOB_NAME` en ejecución.

**Solución:** consulta `status` y `logs`; no inicies otro proceso con el mismo nombre.

### `Detenido o fallido`

**Causa:** hubo un error de lectura/escritura o se detuvo el proceso antes de registrar éxito.

**Solución:** revisa las últimas líneas del registro, conserva el origen y vuelve a ejecutar `start` después de resolver la causa.

## Changelog

### [Unreleased]

- Mantiene abiertos los descriptores de salida para registrar progreso y resultado al desacoplar el proceso.

### v1.2.0 — 2026-10-08

**feat:** gestionar copias indicando solo el nombre de la carpeta.

- `start`, `status`, `logs` y `stop` aceptan el nombre de la carpeta.
- Valida el nombre y comprueba que `admin` pueda leer el origen antes de iniciar.

### v1.1.0 — 2026-10-08

**feat:** permitir gestionar copias sin sudo.

- El estado y los registros pueden pertenecer a `admin`; el gestor deja de exigir root.

### v1.0.1 — 2026-10-08

**fix:** conservar el registro de la copia en segundo plano.

- Añade `--no-close` a `start-stop-daemon` para que stdout y stderr sigan conectados al archivo de registro.

### v1.0.0 — 2026-10-08

**feat:** iniciar y supervisar sincronizaciones con `start-stop-daemon`.

- Añade PID, registro, estado y parada controlada.
