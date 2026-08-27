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

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/brightness-notify.sh`.
