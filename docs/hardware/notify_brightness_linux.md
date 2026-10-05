---
title: notify_brightness_linux.sh
description: Control de brillo de pantalla con pasos finos cerca del 20% y extensión por xrandr sobre 100%.
tags:
  - hardware
---

# notify_brightness_linux.sh

Ajusta el backlight con `brightnessctl` y muestra una notificación. Cerca del
20% usa pasos finos; al llegar al 100%, amplía el brillo por software mediante
`xrandr` en incrementos graduales.

- **Ruta:** `scripts/hardware/notify_brightness_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `brightnessctl`; `xrandr` para superar el 100%; `notify-send` para mostrar la notificación.

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
| `up` | — | Sube el brillo con pasos de 2% en 20% o menos; sobre 20% usa `BRIGHTNESS_STEP`. En 100%, aumenta `xrandr` hasta 2.0. |
| `down` | — | Baja primero el extra de `xrandr` hasta la base configurada; después baja el backlight con pasos de 1% en 20% o menos y evita saltar el umbral. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `BRIGHTNESS_STEP` | `5` | Porcentaje de incremento/decremento normal por encima de 20%. Debe ser un entero positivo. |
| `XRANDR_BRIGHTNESS_STEP` | `0.05` | Incremento de brillo por software por pulsación. Acepta valores mayores que 0 y hasta 1.0. El valor preciso se recuerda entre pulsaciones porque `xrandr --verbose` lo muestra redondeado a una décima. |
| `XRANDR_BRIGHTNESS_BASE` | `1.1` | Nivel base al que `down` devuelve `xrandr` antes de reducir el backlight. Debe ser al menos 0.1 y menor que 2.0. |
| `XRANDR_BRIGHTNESS_OUTPUT` | detección automática | Salida de pantalla para `xrandr`; si no se indica, detecta la primera salida interna conectada (`eDP`, `LVDS` o `DSI`). |

## Ejemplos

```sh
# En 20%, sube a 22%; en 19%, sube a 21%.
./scripts/hardware/notify_brightness_linux.sh up

# En 20%, baja a 19%; en 19%, baja a 18%.
./scripts/hardware/notify_brightness_linux.sh down

# Conserva pasos de 10% fuera del rango fino.
BRIGHTNESS_STEP=10 ./scripts/hardware/notify_brightness_linux.sh down

# Usa incrementos de 0.10 al superar el 100% y selecciona la salida manualmente.
XRANDR_BRIGHTNESS_STEP=0.10 XRANDR_BRIGHTNESS_OUTPUT=eDP-1 \
  ./scripts/hardware/notify_brightness_linux.sh up
```

Al bajar desde más de 20%, el paso normal se conserva salvo que cruzaría el
umbral; en ese caso el brillo llega a 20% y los siguientes pasos bajan de 1%
en 1%. El porcentaje se redondea al entero más cercano porque el backlight
puede no representar cada porcentaje exacto. `brightnessctl` limita el nivel
físico entre 0% y 100%. Al alcanzar el 100%, cada pulsación de subir aumenta
la luminancia de `xrandr` en 0.05 por omisión, hasta el máximo fijo de 2.0. Al
bajar, se reduce primero ese valor hasta la base 1.1; las pulsaciones
siguientes actúan sobre el backlight. `xrandr` requiere una sesión gráfica
X11 y no controla el brillo físico del panel. El último valor preciso se guarda
en `$XDG_STATE_HOME/brightness-notify/<salida>.level` o, si
`XDG_STATE_HOME` no está definido, en `~/.local/state/brightness-notify/`.

## Fallos conocidos

### `No se encontró dispositivo de brillo`

**Causa:** el kernel no expone un backlight compatible o `brightnessctl` no
puede acceder a él.

**Solución:** ejecuta `brightnessctl -l`, revisa el controlador gráfico y usa
el control de brillo del firmware mientras se diagnostica el hardware.

### `No se pudo leer el brillo xrandr de una salida interna conectada.`

**Causa:** al 100%, `xrandr` no pudo consultar el servidor X, no se encontró
una salida interna conectada o la salida no reportó la propiedad
`Brightness`. La notificación incluye ahora el detalle de `DISPLAY`,
`XAUTHORITY` o la salida que falló.

**Solución:** ejecuta `xrandr --query` y `xrandr --verbose` desde la sesión
gráfica; define `XRANDR_BRIGHTNESS_OUTPUT` si la detección eligió mal y
asegúrate de que el atajo de i3 herede `DISPLAY` y `XAUTHORITY`.

## Changelog

### [Unreleased]

- Sin cambios pendientes.

### v1.2.1 — 2026-10-04

**fix:** mostrar por qué falla la lectura de brillo con `xrandr`.

- Diferenciar errores de conexión a X11, detección de salida y propiedad ausente.
- Incluir el detalle de `DISPLAY` y `XAUTHORITY` disponible en el diagnóstico.

### v1.2.2 — 2026-10-04

**fix:** conservar la precisión de los pasos de `xrandr`.

- Recordar el nivel aplicado por salida porque `xrandr --verbose` redondea el valor reportado a una décima.
- Permitir que pulsaciones consecutivas reduzcan el brillo aunque el cambio individual sea menor que una décima.

### v1.2.0 — 2026-10-04

**feat:** ampliar gradualmente el brillo sobre 100% con `xrandr`.

- Subir en pasos configurables hasta 2.0 y regresar a la base antes de bajar el backlight.
- Detectar la salida interna conectada o permitir configurarla explícitamente.

### v1.1.0 — 2026-10-04

**feat:** usar pasos de brillo direccionales cerca del 20%.

- Bajar de 1% en 1% dentro del rango fino y subir de 2% en 2%.
- Evitar que un paso normal cruce el umbral al bajar.
- Redondear el porcentaje mostrado a la resolución más cercana del backlight.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/brightness-notify.sh`.
