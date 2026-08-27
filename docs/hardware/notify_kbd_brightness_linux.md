---
title: notify_kbd_brightness_linux.sh
description: Notificaciones de brillo del teclado
tags:
  - hardware
---

# notify_kbd_brightness_linux.sh

Ajusta el brillo del teclado retroiluminado directamente vía sysfs y muestra notificación.

- **Ruta:** `scripts/hardware/notify_kbd_brightness_linux.sh`
- **SO requerido:** Linux (ThinkPad, MacBook u otro equipo con LED de teclado)
- **Dependencias:** `notify-send`

______________________________________________________________________

## Uso

```sh
./scripts/hardware/notify_kbd_brightness_linux.sh up
./scripts/hardware/notify_kbd_brightness_linux.sh down
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `KBD_BACKLIGHT_DEVICE` | autodetectado | Ruta al dispositivo sysfs del backlight |
| `KBD_BRIGHTNESS_STEP` | `20` | Incremento/decremento (unidades raw) |

______________________________________________________________________

## Ejemplos

```sh
./scripts/hardware/notify_kbd_brightness_linux.sh up
KBD_BRIGHTNESS_STEP=10 ./scripts/hardware/notify_kbd_brightness_linux.sh down
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

**fix:** autodetección de `tpacpi::kbd_backlight` y pasos adecuados para dispositivos con pocos niveles.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/kbd-brightness-notify.sh`.
