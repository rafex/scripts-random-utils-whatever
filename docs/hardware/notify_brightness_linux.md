---
title: notify_brightness_linux.sh
description: Notificaciones de brillo de pantalla
tags:
  - hardware
---

# notify_brightness_linux.sh

Ajusta el brillo de pantalla con `brightnessctl` y muestra una notificación con barra de progreso.

- **Ruta:** `scripts/hardware/notify_brightness_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `brightnessctl`, `notify-send`

En el perfil ThinkPad, F5 (`XF86MonBrightnessDown`) baja y F6
(`XF86MonBrightnessUp`) sube el brillo de pantalla. El helper funciona
como usuario normal y no requiere `sudo`.

______________________________________________________________________

## Uso

```sh
./scripts/hardware/notify_brightness_linux.sh up
./scripts/hardware/notify_brightness_linux.sh down
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `BRIGHTNESS_STEP` | `5` | Porcentaje de incremento/decremento |

______________________________________________________________________

## Ejemplos

```sh
./scripts/hardware/notify_brightness_linux.sh up
BRIGHTNESS_STEP=10 ./scripts/hardware/notify_brightness_linux.sh down
```

El incremento se aplica al brillo físico expuesto por `brightnessctl` y se
limita automáticamente entre `0%` y `100%`. Si el backlight ya está en
`100%`, `up` no puede producir más brillo físico; para compensar un panel
oscuro debe evaluarse por separado el ajuste software de `xrandr`.

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

Debe existir al menos un dispositivo de brillo administrado por
`brightnessctl`. Compruébalo con `brightnessctl -l`.

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Fallos conocidos

### `No se encontró dispositivo de brillo`

**Causa:** el kernel no expone un backlight compatible o `brightnessctl`
no puede acceder a él.

**Solución:** ejecuta `brightnessctl -l`, revisa el controlador gráfico
y usa el control de brillo del firmware mientras se diagnostica el hardware.

## Changelog

### [Unreleased]

- **docs:** documentar el límite físico de `brightnessctl` y el uso de
  `BRIGHTNESS_STEP` para incrementos configurables.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/brightness-notify.sh`.
