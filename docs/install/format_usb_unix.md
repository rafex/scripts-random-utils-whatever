---
title: format_usb_unix.sh
description: Formateo controlado de memorias USB
tags:
  - instalación
---

# format_usb_unix.sh

Formatea un disco USB en macOS y Linux con el sistema de archivos y nombre de volumen deseados.

- **Ruta:** `scripts/install/format_usb_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `diskutil` (macOS), `mkfs.*` (Linux), `sudo`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Formatos disponibles](#formatos-disponibles)
- [Variables de entorno](#variables-de-entorno)
- [Archivo .env](#archivo-env)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

______________________________________________________________________

## Requisitos

- **macOS:** `diskutil` (incluido en el sistema)
- **Linux:** `mkfs.fat` (paquete `dosfstools`), `mkfs.exfat` (paquete `exfatprogs` o `exfat-utils`), `mkfs.ext4` (paquete `e2fsprogs`), `mkfs.ntfs` (paquete `ntfs-3g`)
- `sudo` disponible y configurado para el usuario actual
- El disco USB debe estar conectado y reconocido por el sistema

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
just format-usb [opciones]
```

### Directamente

```sh
./scripts/install/format_usb_unix.sh [opciones]
```

Si no se especifica el disco por argumento o variable, el script mostrará un error con instrucciones de uso.

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--disk <diskN\|sdX>` | `-d` | Disco destino (ej. `disk5`, `sdb`) |
| `--format <formato>` | `-f` | Sistema de archivos (defecto: `FAT32`) |
| `--name <etiqueta>` | `-n` | Nombre del volumen (defecto: `USB`) |
| `--env <archivo.env>` | | Archivo `.env` con `USB_DISK`, `USB_FORMAT`, `USB_NAME` |
| `--help` | `-h` | Mostrar ayuda |

______________________________________________________________________

## Formatos disponibles

| Formato | macOS | Linux | Notas |
|---|---|---|---|
| `FAT32` | ✓ | ✓ | Compatible con todos los SO. Límite de 4 GB por archivo |
| `exFAT` | ✓ | ✓ | Sin límite de 4 GB. Requiere `exfatprogs` en Linux |
| `APFS` | ✓ | ✗ | Solo macOS 10.13+ |
| `HFS+` | ✓ | ✗ | Solo macOS |
| `ext4` | ✗ | ✓ | Requiere `e2fsprogs` |
| `ext3` | ✗ | ✓ | Requiere `e2fsprogs` |
| `ext2` | ✗ | ✓ | Requiere `e2fsprogs` |
| `NTFS` | ✗ | ✓ | Requiere `ntfs-3g` |

______________________________________________________________________

## Variables de entorno

| Variable | Descripción | Defecto |
|---|---|---|
| `USB_DISK` | Disco destino (ej. `disk5`, `sdb`) | — |
| `USB_FORMAT` | Sistema de archivos | `FAT32` |
| `USB_NAME` | Nombre del volumen | `USB` |

**Orden de prioridad (mayor a menor):**

```
--disk / --format / --name  >  USB_DISK / USB_FORMAT / USB_NAME (env)  >  .env file
```

______________________________________________________________________

## Archivo .env

El script carga automáticamente `.env` en el directorio actual. Se puede especificar otro con `--env`.

Solo se leen `USB_DISK`, `USB_FORMAT` y `USB_NAME` (sin `source` para evitar ejecución arbitraria).

**Formato:**

```env
USB_DISK=disk5
USB_FORMAT=FAT32
USB_NAME=MI_USB
```

______________________________________________________________________

## Ejemplos

### Con `just` desde la raíz (recomendado)

```sh
just format-usb --disk disk5 --format FAT32 --name MI_USB
```

```sh
just format-usb -d sdb -f exFAT -n DATOS
```

Con variables de entorno:

```sh
USB_DISK=disk5 USB_FORMAT=FAT32 USB_NAME=MI_USB just format-usb
```

Con archivo `.env`:

```sh
just format-usb --env config.env
```

Ver tareas disponibles:

```sh
just
```

______________________________________________________________________

### Directamente sobre el script

#### FAT32 en macOS (recomendado para USBs)

```sh
./scripts/install/format_usb_unix.sh --disk disk5 --format FAT32 --name MI_USB
```

#### exFAT en macOS (archivos mayores de 4 GB)

```sh
./scripts/install/format_usb_unix.sh --disk disk5 --format exFAT --name DATOS
```

#### ext4 en Linux

```sh
./scripts/install/format_usb_unix.sh --disk sdb --format ext4 --name LINUXDISK
```

#### Con variables de entorno

```sh
USB_DISK=disk5 USB_FORMAT=FAT32 USB_NAME=MI_USB ./scripts/install/format_usb_unix.sh
```

#### Con archivo .env en otra ruta

```sh
./scripts/install/format_usb_unix.sh --env /tmp/usb.env
```

______________________________________________________________________

## Protecciones de seguridad

| Verificación | Acción |
|---|---|
| `disk0` como destino (macOS) | Bloqueo automático (error fatal) |
| Disco con `Device Location: Internal` (macOS) | Bloqueo automático (error fatal) |
| Disco coincide con el disco de boot del sistema | Bloqueo automático (error fatal) |
| Disco no extraíble (macOS: sin `Removable/External`; Linux: `/sys/block/*/removable`) | Advertencia en amarillo + confirmación adicional requerida |
| Formato no soportado en el OS actual | Error con lista de formatos válidos |
| Confirmación final antes de formatear | Se requiere escribir `YES` en mayúsculas |

______________________________________________________________________

## Fallos conocidos

> Esta sección se irá completando con problemas encontrados en uso real.

### `mkfs.exfat: command not found`

**Causa:** el paquete `exfatprogs` (o `exfat-utils` en distribuciones antiguas) no está instalado.\
**Solución:**

```sh
# Debian/Ubuntu
sudo apt install exfatprogs

# Arch
sudo pacman -S exfatprogs

# Fedora
sudo dnf install exfatprogs
```

______________________________________________________________________

### `mkfs.ntfs: command not found`

**Causa:** el paquete `ntfs-3g` no está instalado.\
**Solución:**

```sh
# Debian/Ubuntu
sudo apt install ntfs-3g

# Arch
sudo pacman -S ntfs-3g
```

______________________________________________________________________

### `diskutil eraseDisk` falla con error de permisos en macOS

**Causa:** el disco tiene particiones protegidas o está siendo usado por otro proceso.\
**Solución:** desmontar manualmente y reintentar:

```sh
diskutil unmountDisk force /dev/disk5
just format-usb --disk disk5 --format FAT32 --name MI_USB
```

______________________________________________________________________

### El volumen no aparece en el Finder después de formatear

**Causa:** macOS no montó automáticamente el nuevo volumen.\
**Solución:**

```sh
diskutil mountDisk /dev/disk5
```

______________________________________________________________________

## Changelog

### [Unreleased]

- Pendiente: soporte para particionado personalizado (MBR/GPT).

______________________________________________________________________

### v1.0.0 — 2026-05-02

**feat:** versión inicial.

- Soporte macOS (`diskutil eraseDisk`) y Linux (`mkfs.*`)
- Formatos: FAT32, exFAT, ext4, ext3, ext2, NTFS (Linux); FAT32, exFAT, APFS, HFS+ (macOS)
- Argumentos `--disk`/`-d`, `--format`/`-f`, `--name`/`-n`
- Variables de entorno `USB_DISK`, `USB_FORMAT`, `USB_NAME`
- Soporte para archivo `.env` vía `--env`
- Protección contra discos de sistema (disk0, internos, boot)
- Advertencia para discos no extraíbles con confirmación
- Validación de formato disponible por OS
- Banner de confirmación en rojo antes de la operación destructiva
- Tarea `just format-usb` en `just/install.just`
