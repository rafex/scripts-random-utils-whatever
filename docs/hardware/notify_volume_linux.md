---
title: notify_volume_linux.sh
description: Notificaciones de volumen
tags:
  - hardware
---

# notify_volume_linux.sh

Ajusta el volumen del sistema con `wpctl` (PipeWire) y usa `pactl` como fallback; muestra una notificación con el nivel actual o estado de mute.

- **Ruta:** `scripts/hardware/notify_volume_linux.sh`
- **SO requerido:** Linux (PipeWire o PulseAudio)
- **Dependencias:** `wpctl` o `pactl`, `notify-send`

______________________________________________________________________

## Uso

```sh
./scripts/hardware/notify_volume_linux.sh up
./scripts/hardware/notify_volume_linux.sh down
./scripts/hardware/notify_volume_linux.sh mute
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `VOLUME_STEP` | `5` | Porcentaje de incremento/decremento |
| `VOLUME_SINK` | `@DEFAULT_AUDIO_SINK@` | Sink de PipeWire usado por `wpctl`. |

______________________________________________________________________

## Ejemplos

```sh
./scripts/hardware/notify_volume_linux.sh up
./scripts/hardware/notify_volume_linux.sh mute
VOLUME_STEP=10 ./scripts/hardware/notify_volume_linux.sh down
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

### `pactl: command not found`

**Causa:** PipeWire está activo, pero solo está disponible `wpctl`.
**Solución:** la versión actual usa `wpctl` automáticamente; `pactl` queda
como fallback para sesiones PulseAudio.

## Changelog

### v1.1.0 — 2026-08-27

**fix:** usar `wpctl` en PipeWire para que funcionen las teclas de volumen.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/volume-notify.sh`.
