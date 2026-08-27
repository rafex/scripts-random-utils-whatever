---
title: notify_microphone_linux.sh
description: Alternar el mute del micrófono en PipeWire
tags:
  - hardware
  - audio
---

# notify_microphone_linux.sh

Alterna o fija el estado mute de la fuente de audio predeterminada.

- **Ruta:** `scripts/hardware/notify_microphone_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `wpctl`, `notify-send`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

Debe existir una sesión PipeWire/WirePlumber activa.

## Uso

```sh
~/.local/bin/microphone-notify.sh toggle
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `toggle` | — | Alterna el mute. |
| `mute` | — | Silencia la fuente. |
| `unmute` | — | Activa la fuente. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `MICROPHONE_SOURCE` | `@DEFAULT_AUDIO_SOURCE@` | Fuente administrada por `wpctl`. |

## Ejemplos

```sh
~/.local/bin/microphone-notify.sh toggle
MICROPHONE_SOURCE=57 ~/.local/bin/microphone-notify.sh mute
```

## Fallos conocidos

### `wpctl` no está disponible

**Causa:** PipeWire no está instalado o no inició la sesión de usuario.
**Solución:** ejecutar la etapa de hardware/terminal y comprobar `wpctl status`.

## Changelog

### [Unreleased]

**feat:** añadir control de mute para la tecla de micrófono de i3.
