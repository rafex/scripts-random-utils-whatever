---
title: screen_extend_auto_linux.sh
description: Extensión automática de pantallas
tags:
  - pantallas
---

# screen_extend_auto_linux.sh

Extiende el escritorio al monitor externo (a la derecha). Si no hay externo conectado, vuelve a solo laptop.

- **Ruta:** `scripts/display/screen_extend_auto_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `notify-send`, `awk`

______________________________________________________________________

## Uso

```sh
./scripts/display/screen_extend_auto_linux.sh
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SCREEN_INTERNAL` | autodetectada (`eDP-*`, `LVDS-*`, `DSI-*`) | Salida interna |
| `SCREEN_EXTERNAL` | autodetectada (`HDMI-*`, `DP-*`, `DVI-*`, `VGA-*`) | Salida externa |

______________________________________________________________________

## Ejemplos

```sh
./scripts/display/screen_extend_auto_linux.sh

SCREEN_INTERNAL=eDP1 SCREEN_EXTERNAL=DP1 ./scripts/display/screen_extend_auto_linux.sh
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

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

**feat:** autodetección de salidas xrandr.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-extend-auto.sh`.
