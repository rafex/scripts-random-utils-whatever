---
title: eww_battery_status_linux.sh
description: Emite telemetría de alimentación y salud estimada para EWW.
tags:
  - sistema
  - eww
  - batería
---

# eww_battery_status_linux.sh

Lee la alimentación desde `sysfs` y la salud estimada desde UPower para que
EWW la muestre en una tarjeta que se actualiza cada 10 segundos.

- **Ruta:** `scripts/system/eww_battery_status_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `/sys/class/power_supply`; `upower` es opcional para `Salud`

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

- Linux con `/sys/class/power_supply`.
- Ejecutarse como usuario normal.
- `upower` para calcular la capacidad estimada; si no existe, se muestra
  `N/D` en `Salud`.

## Uso

La consulta directa se puede ejecutar mediante Just:

```bash
just eww-battery-status
just eww-battery-status --status
just eww-battery-status --check
```

EWW lo utiliza automáticamente como:

```text
(defpoll rafex-battery-telemetry :interval "10s" ...
  "$HOME/.local/bin/eww-battery-status.sh")
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| *(sin opción)* | — | Imprime AC, carga, estado y salud estimada. |
| `--status` | — | Imprime la misma telemetría para inspección manual. |
| `--check` | — | Comprueba la plataforma y la disponibilidad de sysfs sin leer valores. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este helper no utiliza variables de entorno para seleccionar archivos o
comandos.

## Ejemplos

### Consulta recomendada

```bash
just eww-battery-status
```

Salida esperada:

```text
AC: 1
Carga: 80
Estado: Charging
Salud: 100% (estimada)
```

### Configuración de EWW

```bash
just configure-eww-battery --check
just configure-eww-battery --apply
just eww-widgets --reload
```

## Protecciones de seguridad

- Solo lee `/sys/class/power_supply` y la salida de UPower.
- No utiliza `watch`, `sudo`, ADB, red ni comandos introducidos por el usuario.
- Devuelve `N/D` si falta una fuente de alimentación o una batería.
- No muestra números de serie, rutas privadas ni identificadores de hardware.

## Fallos conocidos

### `Salud: N/D`

**Causa:** UPower no está instalado, no hay un dispositivo de batería
publicado o la sesión no permite consultarlo.

**Solución:** instala/activa UPower en el sistema o interpreta la salud como
no disponible; la carga y el estado de sysfs pueden seguir funcionando.

### `Carga` baja y `Salud` alta

**Causa:** son magnitudes diferentes. `Carga` es el porcentaje actual de
energía; `Salud` es una estimación de capacidad máxima frente al diseño.

**Solución:** no confundas `Salud: 100%` con una batería cargada; revisa ambas
líneas y el estado `AC`.

## Changelog

### [Unreleased]

- **feat:** añadir salida de alimentación compatible con un `defpoll` EWW de
  10 segundos.
