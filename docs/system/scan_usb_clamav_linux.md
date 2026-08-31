---
title: scan_usb_clamav_linux.sh
description: Escanea medios USB extraíbles sin borrado ni cuarentena mediante ClamAV.
tags:
  - sistema
  - seguridad
  - usb
---

# scan_usb_clamav_linux.sh

Escanea una memoria USB montada en una ruta de usuario usando ClamAV. El
escáner rechaza el sistema, el HOME, el NVMe interno y cualquier ruta fuera de
los directorios de medios extraíbles.

- **Ruta:** `scripts/system/scan_usb_clamav_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, findmnt, lsblk, realpath, clamscan; `notify-send` es opcional y permite notificaciones del hook automático.

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

- ClamAV instalado mediante `just install-antivirus --apply`.
- La memoria debe estar montada bajo `/run/media/$USER` o `/media/$USER`.
- El dispositivo padre debe anunciarse como extraíble en sysfs.

## Uso

```bash
just scan-usb --path /run/media/$USER/NOMBRE_USB
```

Un evento de udiskie puede invocarlo mediante:

```bash
~/.local/bin/scan-usb-clamav.sh --auto-event device_mounted
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--path <ruta>` | — | Escanea un montaje extraíble validado. |
| `--auto-event <evento>` | — | Escanea montajes extraíbles tras un evento de udiskie compatible. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. Usa el usuario actual para calcular las
rutas permitidas y guarda logs automáticos en
`~/.local/state/rafex/clamav/`.

## Ejemplos

```bash
just scan-usb --path /run/media/$USER/USB
just scan-usb --path /media/$USER/DISCO
```

Los códigos de salida son `0` sin infección, `1` con infección encontrada y
`2` ante una ruta insegura, herramienta ausente o error de lectura.

## Protecciones de seguridad

- Solo acepta rutas bajo `/run/media/$USER` o `/media/$USER`.
- Comprueba con `findmnt`, `lsblk` y sysfs que el dispositivo sea extraíble.
- Rechaza explícitamente el NVMe interno y los montajes `/` y `$HOME`.
- No usa sudo, no borra archivos y no mueve archivos a cuarentena.
- El hook automático usa un lock para evitar escaneos simultáneos.

## Fallos conocidos

### `el montaje no pertenece a un dispositivo extraíble`

**Causa:** la ruta pertenece a un disco interno, un volumen virtual o no está
montada mediante un dispositivo de bloque extraíble.

**Solución:** utiliza una memoria USB real montada por udiskie en
`/run/media/$USER/NOMBRE` o `/media/$USER/NOMBRE`.

### `falta clamscan`

**Causa:** ClamAV aún no está instalado o no está en el PATH.

**Solución:** ejecuta `just install-antivirus --apply` y espera a que FreshClam
descargue las firmas.

## Changelog

### [Unreleased]

- **feat:** añadir escaneo USB explícito y seguro con ClamAV.
