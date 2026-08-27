# autorotate_x1_yoga_linux.sh

Rota automáticamente la pantalla interna de una ThinkPad X1 Yoga en Xorg y
alinea la pantalla táctil y la pluma Wacom con la orientación actual.

- **Ruta:** `scripts/hardware/autorotate_x1_yoga_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `xrandr`, `xinput`, `xsetwacom`, `monitor-sensor`, `iio-sensor-proxy`, `flock`, `notify-send` (opcional)

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

La ThinkPad X1 Yoga 1st Gen debe tener Xorg/i3 iniciado y los paquetes de
entrada instalados. La etapa correspondiente de la migración instala:

```sh
just migrate-laptop --stage tablet --apply
```

La primera prueba de sensores debe hacerse desde Alacritty dentro de i3, no
desde SSH. Comprueba que el firmware exponga el modo tablet:

```sh
cat /sys/devices/platform/thinkpad_acpi/hotkey_tablet_mode
```

## Uso

```sh
~/.local/bin/autorotate-x1-yoga.sh --check
~/.local/bin/autorotate-x1-yoga.sh --daemon
```

El perfil i3 instala el daemon de forma idempotente cuando se aplica la etapa
`tablet`. Reinicia i3 con `Mod4+Shift+r` o cierra e inicia sesión para cargarlo.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra sensores, salidas y dispositivos sin cambiar nada. |
| `--once` | — | Aplica una orientación y termina. |
| `--daemon` | — | Escucha modo tablet y eventos de `monitor-sensor`. |
| `--orientation <valor>` | — | `normal`, `right`, `inverted` o `left`; también acepta nombres del sensor. |
| `--sensor-only` | — | Usa el acelerómetro aunque no exista el evento `hotkey_tablet_mode`. |
| `--disable-inputs` | — | Desactiva teclado, touchpad y TrackPoint en modo tablet. |
| `--enable-inputs` | — | Mantiene esos dispositivos activos; es el valor predeterminado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `SCREEN_INTERNAL` | Fuerza la salida interna de `xrandr`; si se omite, detecta `eDP-*`, `LVDS-*` o `DSI-*`. |
| `AUTOROTATE_DISABLE_INPUTS=1` | Equivale a `--disable-inputs`; se recomienda probarlo manualmente antes de usarlo permanentemente. |

Los argumentos de línea de comandos tienen prioridad sobre las variables de
entorno para la desactivación de dispositivos.

## Ejemplos

Diagnóstico desde la sesión gráfica:

```sh
just migrate-laptop --stage tablet --check
~/.local/bin/autorotate-x1-yoga.sh --check
monitor-sensor --accel
```

Prueba manual de las cuatro orientaciones:

```sh
~/.local/bin/autorotate-x1-yoga.sh --once --orientation normal
~/.local/bin/autorotate-x1-yoga.sh --once --orientation right
~/.local/bin/autorotate-x1-yoga.sh --once --orientation inverted
~/.local/bin/autorotate-x1-yoga.sh --once --orientation left
```

Activación normal y alternativa solo con sensor:

```sh
~/.local/bin/autorotate-x1-yoga.sh --daemon
~/.local/bin/autorotate-x1-yoga.sh --daemon --sensor-only
```

## Protecciones de seguridad

- No requiere ni solicita `sudo`; opera dentro de la sesión X11 del usuario.
- Detecta la salida y los nombres de dispositivos dinámicamente; no usa IDs XInput fijos.
- Solo rota la salida interna y deja los monitores externos sin cambios.
- Usa `flock` para impedir dos daemons simultáneos.
- No modifica Xorg, `fstab`, GRUB, parámetros del kernel ni permisos globales de `/dev/iio:*`.
- Teclado, touchpad y TrackPoint no se desactivan por defecto.
- Si el sensor termina o la orientación no puede aplicarse, registra el evento y
  muestra una notificación opcional.

## Fallos conocidos

### `Failed to claim accelerometer: ... AccessDenied`

**Causa:** la prueba se ejecutó desde SSH o fuera de la sesión gráfica local.

**Solución:** inicia Alacritty desde i3 y ejecuta `monitor-sensor --accel` allí.
Si también falla localmente, revisar el estado de `iio-sensor-proxy` y su
política D-Bus antes de agregar permisos.

### `no se detectó una salida interna eDP/LVDS/DSI`

**Causa:** no hay una sesión Xorg activa, la pantalla está desconectada o el
nombre de salida no coincide con los patrones automáticos.

**Solución:** ejecuta `xrandr --query` y usa `SCREEN_INTERNAL=NOMBRE`.

### La imagen rota pero el touch o la pluma quedan desalineados

**Causa:** el sensor puede reportar una orientación invertida respecto del
hardware concreto o Xorg puede estar usando otro controlador de entrada.

**Solución:** prueba las cuatro orientaciones con `--once`, valida
`xsetwacom --list devices` y ajusta el mapeo solo después de una prueba física.

## Changelog

### [Unreleased]

- `feat:` autorrotación condicionada al modo tablet con fallback sensor-only.
- `feat:` alineación dinámica de touch y pluma Wacom.
