---
title: hidpi_xorg_linux.sh
description: Diagnóstico y configuración de DPI para Xorg
tags:
  - pantallas
---

# hidpi_xorg_linux.sh

Detecta la resolución y DPI del monitor conectado y ajusta el escalado de Xorg (`xrandr --scale`) y `Xft.dpi` en `~/.Xresources`.

- **Ruta:** `scripts/display/hidpi_xorg_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `python3`, `xrdb`

______________________________________________________________________

## Uso

```sh
./scripts/display/hidpi_xorg_linux.sh --check
./scripts/display/hidpi_xorg_linux.sh --apply
```

______________________________________________________________________

## Cómo funciona

1. Detecta el panel interno (`eDP-*`, `LVDS-*` o `DSI-*`) o usa el primero disponible
1. Mide DPI a partir de la resolución y dimensiones físicas (mm) del EDID
1. Si no hay mm en EDID, estima por resolución (4K → 200%, QHD+ → 150%, etc.)
1. `--check` solo informa; `--apply` ajusta `xrandr`, `Xft.dpi` y aplica `xrdb -merge`

## Opciones

| Opción | Descripción |
|---|---|
| `--check` | Diagnóstico sin modificar archivos, modo predeterminado |
| `--apply` | Aplica el escalado y actualiza `~/.Xresources` |
| `--output <nombre>` | Fuerza una salida concreta |

______________________________________________________________________

## Ejemplos

```sh
./scripts/display/hidpi_xorg_linux.sh
```

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Variables de entorno

No se requieren variables adicionales fuera de las indicadas en esta documentación.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

**feat:** modo diagnóstico y detección de panel interno portable.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/hidpi_xorg.sh`.
