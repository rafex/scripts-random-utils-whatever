---
title: notify_brightness_linux.sh
description: Control de brillo de pantalla con pasos finos cerca del 20%.
tags:
  - hardware
---

# notify_brightness_linux.sh

Ajusta el brillo de pantalla con `brightnessctl` y muestra una notificación con
el nivel actual. Cerca del 20% usa pasos finos para facilitar el ajuste.

- **Ruta:** `scripts/hardware/notify_brightness_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `brightnessctl`; `notify-send` para mostrar la notificación.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

Debe existir al menos un dispositivo de brillo administrado por
`brightnessctl`. Compruébalo con `brightnessctl -l`. En el perfil ThinkPad,
F5 (`XF86MonBrightnessDown`) baja y F6 (`XF86MonBrightnessUp`) sube el brillo
de pantalla. El helper funciona como usuario normal y no requiere `sudo`.

## Uso

```sh
./scripts/hardware/notify_brightness_linux.sh up
./scripts/hardware/notify_brightness_linux.sh down
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `up` | — | Sube el brillo con pasos de 2% en 20% o menos; sobre 20% usa `BRIGHTNESS_STEP`. |
| `down` | — | Baja el brillo con pasos de 1% en 20% o menos; evita saltar de más de 20% a menos de 20%. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `BRIGHTNESS_STEP` | `5` | Porcentaje de incremento/decremento normal por encima de 20%. Debe ser un entero positivo. |

## Ejemplos

```sh
# En 20%, sube a 22%; en 19%, sube a 21%.
./scripts/hardware/notify_brightness_linux.sh up

# En 20%, baja a 19%; en 19%, baja a 18%.
./scripts/hardware/notify_brightness_linux.sh down

# Conserva pasos de 10% fuera del rango fino.
BRIGHTNESS_STEP=10 ./scripts/hardware/notify_brightness_linux.sh down
```

Al bajar desde más de 20%, el paso normal se conserva salvo que cruzaría el
umbral; en ese caso el brillo llega a 20% y los siguientes pasos bajan de 1%
en 1%. El porcentaje se redondea al entero más cercano porque el backlight
puede no representar cada porcentaje exacto. `brightnessctl` limita el nivel
físico entre 0% y 100%.

## Fallos conocidos

### `No se encontró dispositivo de brillo`

**Causa:** el kernel no expone un backlight compatible o `brightnessctl` no
puede acceder a él.

**Solución:** ejecuta `brightnessctl -l`, revisa el controlador gráfico y usa
el control de brillo del firmware mientras se diagnostica el hardware.

## Changelog

### [Unreleased]

- Sin cambios pendientes.

### v1.1.0 — 2026-10-04

**feat:** usar pasos de brillo direccionales cerca del 20%.

- Bajar de 1% en 1% dentro del rango fino y subir de 2% en 2%.
- Evitar que un paso normal cruce el umbral al bajar.
- Redondear el porcentaje mostrado a la resolución más cercana del backlight.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/brightness-notify.sh`.
