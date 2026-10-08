---
title: usb_disk_health_unix.sh
description: Diagnóstico SMART y prueba acotada de escritura para discos USB externos
tags:
  - hardware
  - almacenamiento
---

# usb_disk_health_unix.sh

Consulta SMART y mide la escritura secuencial de un archivo temporal en un disco USB externo. El archivo de prueba se elimina al terminar.

- **Ruta:** `scripts/hardware/usb_disk_health_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `fio`, `smartmontools` (`smartctl`), `python3`, `sudo`; además `lsblk` y `findmnt` en Linux
- **Task runner:** `just` (recomendado)

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

- Conecta y monta el disco externo antes de ejecutar el diagnóstico.
- Instala `fio` y `smartmontools` (`smartctl`). En Linux también se necesitan `lsblk` y `findmnt`, normalmente incluidos en las utilidades del sistema.
- `sudo` debe estar disponible para consultar SMART.
- El volumen debe tener al menos el tamaño de prueba más 128 MiB libres. El tamaño predeterminado es 1 GiB.
- El gabinete o adaptador USB debe permitir el paso de comandos SMART para que la consulta y el autotest funcionen.

## Uso

Desde la raíz del repositorio:

```sh
just disk-health
```

El comando lista los discos externos detectados y pide seleccionar uno. Después muestra los puntos de montaje y solicita que escribas la ruta del volumen que corresponde al disco. Comprueba que correspondan, solicita confirmación y ejecuta la consulta SMART y la prueba de escritura.

El reporte se guarda en un directorio `usb-disk-health.*` bajo `/tmp` (o bajo `$TMPDIR` si está definido). La prueba SMART corta puede continuar en el disco después de que el comando termine; el reporte conserva la respuesta de `smartctl`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--size <tamano>` | | Cantidad escrita en el archivo temporal. Acepta enteros con sufijo `K`, `M` o `G`; defecto: `1G`. |
| `--help` | `-h` | Mostrar la ayuda. |

## Variables de entorno

| Variable | Descripción | Defecto |
|---|---|---|
| `TMPDIR` | Directorio local donde se guarda el reporte temporal. No cambia la ubicación del archivo escrito para la prueba. | `/tmp` |

## Ejemplos

Prueba predeterminada de 1 GiB:

```sh
just disk-health
```

Escribir 2 GiB:

```sh
just disk-health --size 2G
```

Guardar el reporte en otro directorio local:

```sh
TMPDIR="$HOME/tmp" just disk-health --size 512M
```

Ejecutar directamente:

```sh
bash scripts/hardware/usb_disk_health_unix.sh --size 1G
```

## Protecciones de seguridad

- Solo enumera discos externos USB en Linux y discos externos físicos en macOS.
- Rechaza el punto de montaje si no pertenece al disco elegido.
- Bloquea el disco que contiene el filesystem raíz del sistema.
- Muestra el destino y requiere escribir `YES` antes de empezar.
- Escribe únicamente en un archivo temporal dentro del volumen montado; nunca dirige `fio` al dispositivo de bloques.
- Comprueba el espacio disponible antes de escribir y elimina el archivo de prueba al terminar, incluso ante interrupciones.
- SMART no es una prueba concluyente de salud física. Si el adaptador USB no expone SMART, el reporte lo indica; no se debe interpretar como un resultado saludable.

## Fallos conocidos

### `no se encontraron discos externos USB`

**Causa:** el sistema no identifica el disco como externo USB, no está conectado o el puente USB no expone esa clasificación.
**Solución:** confirma que el disco aparece en `lsblk` (Linux) o `diskutil list external physical` (macOS), y prueba otro puerto o adaptador.

### `smartctl` no puede acceder al dispositivo

**Causa:** el adaptador USB no pasa los comandos SMART, o el disco no admite la consulta solicitada.
**Solución:** revisa el manual del gabinete y la salida completa del reporte. Si el puente no soporta SMART, el script no puede validar ese aspecto de la salud del disco.

### `fio` falla o informa espacio insuficiente

**Causa:** el volumen no tiene espacio libre suficiente, está montado como solo lectura o el sistema de archivos rechazó la escritura.
**Solución:** libera espacio, revisa que el volumen permita escritura y reduce el tamaño con `--size`.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-10-07

**feat:** diagnóstico SMART y prueba acotada de escritura en discos USB externos.

- Añade selección interactiva de disco y punto de montaje con comprobación de correspondencia.
- Consulta SMART, solicita autotest corto y mide escritura secuencial con `fio`.
- Genera un reporte local y elimina el archivo temporal de prueba.
