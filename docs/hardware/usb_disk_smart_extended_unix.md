---
title: usb_disk_smart_extended_unix.sh
description: Ejecuta y espera la prueba SMART extendida de discos USB externos
tags:
  - hardware
  - almacenamiento
---

# usb_disk_smart_extended_unix.sh

Inicia el autotest SMART extendido de uno o de todos los discos USB externos y espera a que terminen. La prueba lee la superficie del disco sin escribir datos.

- **Ruta:** `scripts/hardware/usb_disk_smart_extended_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `smartmontools` (`smartctl`), `sudo`; además `lsblk` en Linux o `diskutil` en macOS
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

- Conecta los discos externos antes de ejecutar el diagnóstico.
- Instala `smartmontools` con `just install-disk-health-tools`.
- `sudo` debe estar disponible para consultar SMART e iniciar los autotests.
- El puente USB debe permitir el paso de comandos SMART.
- Mantén el equipo encendido y los discos conectados hasta que todas las pruebas terminen. Cada prueba puede tardar varias horas.

## Uso

Desde la raíz del repositorio:

```sh
just disk-smart-extended
```

El script lista los discos USB externos, permite elegir uno o todos y pide escribir `YES` antes de iniciar. Luego consulta el progreso cada minuto y guarda la salida completa en un directorio `usb-smart-extended.*` bajo `/tmp` (o bajo `$TMPDIR`).

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--all` | | Ejecutar la prueba en todos los discos USB externos detectados. |
| `--help` | `-h` | Mostrar esta ayuda. |

## Variables de entorno

| Variable | Descripción | Defecto |
|---|---|---|
| `TMPDIR` | Directorio local donde se guarda el reporte. | `/tmp` |

## Ejemplos

Ejecutar interactivamente y elegir un disco:

```sh
just disk-smart-extended
```

Probar todos los discos USB externos:

```sh
just disk-smart-extended --all
```

Guardar el reporte en otro directorio local:

```sh
TMPDIR="$HOME/tmp" just disk-smart-extended --all
```

Modo directo sin `just`:

```sh
bash scripts/hardware/usb_disk_smart_extended_unix.sh --all
```

## Protecciones de seguridad

- Solo selecciona discos externos USB en Linux o discos externos físicos en macOS.
- La prueba SMART extendida es de solo lectura; no formatea, particiona ni escribe archivos en el disco.
- Muestra los destinos y requiere confirmación antes de iniciar.
- Si el puente no admite SMART o el autotest no puede iniciarse, conserva el mensaje en el reporte.
- SMART no es garantía absoluta de salud futura. Conserva una copia de seguridad de los datos.

## Fallos conocidos

### `no se encontraron discos externos USB`

**Causa:** el sistema no identifica el disco como externo USB, no está conectado o el puente USB no expone esa clasificación.
**Solución:** confirma que el disco aparece en `lsblk` (Linux) o `diskutil list external physical` (macOS), y prueba otro puerto o adaptador.

### `smartctl no pudo iniciar la prueba extendida`

**Causa:** el puente USB no permite pasar la orden SMART, el disco ya está ejecutando un autotest o la unidad no admite la prueba.
**Solución:** revisa el reporte y la salida de `smartctl`. Si el puente no permite SMART, conecta el disco mediante un adaptador compatible.

### La prueba queda interrumpida

**Causa:** el equipo se suspendió, se apagó, se desconectó el gabinete o el puente USB reinició el disco.
**Solución:** evita suspender el equipo, mantén energía estable y reinicia el autotest cuando puedas dejar el disco conectado durante toda su duración.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-10-07

**feat:** autotest SMART extendido para discos USB externos.

- Añade selección de un disco o de todos los discos externos detectados.
- Espera la finalización, registra el resultado y guarda un reporte local.
