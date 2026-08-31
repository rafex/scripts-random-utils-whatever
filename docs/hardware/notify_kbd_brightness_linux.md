---
title: notify_kbd_brightness_linux.sh
description: Notificaciones de brillo del teclado
tags:
  - hardware
---

# notify_kbd_brightness_linux.sh

Ajusta el brillo del teclado retroiluminado con niveles reales del dispositivo y
muestra una notificación. Prefiere `brightnessctl` y usa sysfs como alternativa
si el dispositivo permite escritura al usuario.

- **Ruta:** `scripts/hardware/notify_kbd_brightness_linux.sh`
- **SO requerido:** Linux (ThinkPad, MacBook u otro equipo con LED de teclado)
- **Dependencias:** `brightnessctl` (preferida), `notify-send` y un LED
  compatible en `/sys/class/leds`

______________________________________________________________________

## Uso

```sh
./scripts/hardware/notify_kbd_brightness_linux.sh up
./scripts/hardware/notify_kbd_brightness_linux.sh down
```

En el perfil ThinkPad, F11 (`XF86LaunchA`) baja y F12 (`XF86Explorer`)
sube el brillo del teclado. El control nativo del firmware con Fn+Space se
conserva; estos atajos son una alternativa software.

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `KBD_BACKLIGHT_DEVICE` | autodetectado | Ruta al dispositivo sysfs del backlight |
| `KBD_BRIGHTNESS_STEP` | `20` o `1` | Incremento/decremento en niveles raw; se usa `1` automáticamente cuando el dispositivo tiene diez niveles o menos |

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

El usuario debe tener permiso para cambiar el dispositivo de backlight. El
script no ejecuta `sudo`; si sysfs no es escribible, informa el problema.

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Fallos conocidos

### `No se encontró retroiluminación de teclado`

**Causa:** el equipo no expone un LED compatible, o el kernel no cargó el
controlador ACPI del teclado.

**Solución:** revisa `brightnessctl -l` y `/sys/class/leds`. En la X1 Yoga
la ruta esperada suele ser `tpacpi::kbd_backlight`; Fn+Space puede seguir
funcionando aunque Linux no exponga un control software.

### `No hay permisos de usuario para modificar .../brightness`

**Causa:** el dispositivo existe, pero sus permisos no permiten escritura a la
sesión gráfica.

**Solución:** usa Fn+Space o corrige la política de permisos del sistema
separadamente. El helper no eleva privilegios.

## Changelog

### [Unreleased]

**fix:** preferir `tpacpi::kbd_backlight`, respetar niveles reales y notificar
errores de permisos sin usar sudo.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/kbd-brightness-notify.sh`.
