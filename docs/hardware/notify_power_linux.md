---
title: notify_power_linux.sh
description: Notificaciones de conexión de energía
tags:
  - hardware
---

# notify_power_linux.sh

Monitoriza cambios de estado de energía (AC/batería) mediante eventos de UPower y notifica al conectar o desconectar el cargador.

Se ejecuta como daemon (bloquea escuchando eventos).

El perfil ThinkPad instala `fonts-noto-color-emoji` porque Dunst necesita una
fuente con esos glifos para mostrar `🔌` y `🔋` en el título de la notificación.
Después de instalarla, recarga Dunst o reinicia la sesión gráfica.

- **Ruta:** `scripts/hardware/notify_power_linux.sh`
- **SO requerido:** Linux (UPower)
- **Dependencias:** `upower`, `notify-send`, `fonts-noto-color-emoji` (para los iconos Unicode)

______________________________________________________________________

## Uso

```sh
./scripts/hardware/notify_power_linux.sh &
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `POWER_DEVICE` | autodetectado | Dispositivo UPower a monitorizar; útil para forzar un nombre concreto |

______________________________________________________________________

## Ejemplos

```sh
# Lanzar en background
./scripts/hardware/notify_power_linux.sh &

# ThinkPad: detecta automáticamente AC y BAT0
~/.local/bin/power-notify.sh &

# Con dispositivo personalizado
POWER_DEVICE=/org/freedesktop/UPower/devices/line_power_AC0 \
  ./scripts/hardware/notify_power_linux.sh &
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

**fix:** detección dinámica de dispositivos AC compatible con ThinkPad y MacBook.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/power-notify.sh`.
