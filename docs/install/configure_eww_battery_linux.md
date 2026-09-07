---
title: configure_eww_battery_linux.sh
description: Añade a EWW una tarjeta de telemetría de batería con actualización cada 10 segundos.
tags:
  - instalación
  - eww
  - batería
---

# configure_eww_battery_linux.sh

Instala el helper de alimentación y añade bloques administrados, idempotentes
y reversibles a la configuración EWW del perfil ThinkPad.

- **Ruta:** `scripts/install/configure_eww_battery_linux.sh`
- **SO requerido:** Linux (X11/EWW)
- **Dependencias:** `bash`, `awk`, `cmp`, `cp`, `grep`, EWW instalado por `install_eww_linux.sh`

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

- Haber ejecutado `just install-eww --apply` para crear
  `~/.config/eww/eww.yuck`.
- Sesión Linux normal; el script no se ejecuta como root y no necesita `sudo`.
- El helper `~/.local/bin/eww-widgets.sh` es opcional; si existe, se usa para
  recargar la ventana administrada.

## Uso

```bash
just configure-eww-battery --check
just configure-eww-battery --plan
just configure-eww-battery --apply
just eww-widgets --reload
```

Para retirarlo:

```bash
just configure-eww-battery --rollback
just eww-widgets --reload
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida el Yuck administrado y el helper fuente. |
| `--plan` | `--dry-run` | Describe el cambio sin modificar archivos. |
| `--status` | — | Comprueba bloques, helper y posibilidad de recarga. |
| `--apply` | — | Instala el helper y añade/actualiza los dos bloques EWW. |
| `--rollback` | — | Retira solo los bloques y helper administrados por esta función. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Ubicación de la configuración EWW. |

Los argumentos de línea de comandos seleccionan la operación y tienen
precedencia sobre cualquier valor implícito; no se admite archivo `.env`.

## Ejemplos

### Forma recomendada

```bash
just configure-eww-battery --check
just configure-eww-battery --apply
```

### Ver la telemetría sin abrir EWW

```bash
just eww-battery-status
```

### Recuperación

```bash
just configure-eww-battery --rollback
```

## Protecciones de seguridad

- Los bloques usan marcadores `BEGIN/END rafex` y se reemplazan sin duplicarse.
- Se guarda un respaldo fechado de `eww.yuck` bajo
  `~/.local/share/rafex/eww-battery/rollback/`.
- Un Yuck no administrado o ausente se rechaza; no se sobrescribe una
  configuración arbitraria.
- No se ejecuta `watch`, no se usa `sudo` y no se aceptan comandos EWW desde el
  usuario.
- El `defpoll` solo consulta el helper cerrado y la tarjeta no reserva espacio
  adicional del escritorio.

## Fallos conocidos

### `falta ~/.config/eww/eww.yuck`

**Causa:** EWW todavía no fue instalado/configurado para el usuario.

**Solución:** ejecuta `just install-eww --apply` y después repite
`just configure-eww-battery --apply`.

### La tarjeta no aparece tras aplicar

**Causa:** el daemon o la ventana EWW no recargaron la configuración actual.

**Solución:** ejecuta `just eww-widgets --reload` dentro de la sesión X11.

### `Salud` no es un diagnóstico físico completo

**Causa:** UPower expone una estimación de capacidad; no mide por sí solo
resistencia interna, ciclos reales o degradación bajo carga.

**Solución:** usa la línea como indicador operativo y confirma la salud con
mediciones de energía/capacidad y el comportamiento de la batería.

## Changelog

### [Unreleased]

- **feat:** añadir una tarjeta EWW administrada de telemetría de alimentación
  y salud estimada cada 10 segundos.
