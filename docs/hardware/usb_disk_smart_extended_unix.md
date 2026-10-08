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
- **Dependencias:** `bash`, `smartmontools` (`smartctl`), `sudo`, `dd`; Linux: `lsblk`, `readlink`, `systemd-inhibit`, `tee`; macOS: `diskutil`, `caffeinate`
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
- El puente USB debe permitir el paso de comandos SMART y lecturas de bloque.
- Mantén el equipo conectado a corriente y los discos conectados hasta que todas las pruebas terminen. Las pruebas se ejecutan una a la vez; cada una puede tardar varias horas.

## Uso

Desde la raíz del repositorio:

```sh
just disk-smart-extended
```

El script lista los discos USB externos, permite elegir uno o todos y pide escribir `YES` antes de iniciar. Ejecuta las pruebas secuencialmente. Mientras espera, bloquea temporalmente la suspensión del equipo, desactiva autosuspend solo en el dispositivo USB del gabinete y realiza una lectura de 4 KiB cada minuto para evitar la hibernación por inactividad. Restaura el ajuste USB original al terminar o si recibe una interrupción. Guarda progreso y resultados en un directorio `usb-smart-extended.*` bajo `/tmp` (o bajo `$TMPDIR`).

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
- No inicia una segunda prueba hasta que la del disco actual haya terminado.
- En Linux, limita el cambio de autosuspend al puente USB detectado y devuelve `power/control` a su valor original. El bloqueo de suspensión del sistema dura solo lo que tardan las pruebas.
- Las lecturas keepalive acceden a una cantidad mínima de datos y no modifican el contenido del volumen.
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

**Causa:** el gabinete o el adaptador reinició o hibernó el disco, se perdió la conexión USB o el dispositivo no expone una lectura keepalive estable.
**Solución:** comprueba que el reporte muestre la protección USB activa, mantén energía estable y vuelve a ejecutar. Si persiste, conecta el disco directamente por SATA u otro puente.

## Changelog

### [Unreleased]

- Ejecuta autotests en serie, inhibe suspensión, previene autosuspend USB temporalmente y mantiene activo el disco con lecturas periódicas.

### v1.0.0 — 2026-10-07

**feat:** autotest SMART extendido para discos USB externos.

- Añade selección de un disco o de todos los discos externos detectados.
- Espera la finalización, registra el resultado y guarda un reporte local.
