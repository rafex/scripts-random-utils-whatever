---
title: configure_xrandr_brightness_linux.sh
description: Fija el multiplicador de brillo de xrandr en i3 y lo reaplica tras suspender/reanudar.
tags:
  - hardware
  - display
  - i3
---

# configure_xrandr_brightness_linux.sh

Agrega un `exec_always --no-startup-id xrandr --output ... --brightness ...`
al archivo de i3 y un hook de `systemd-sleep` que vuelve a aplicar ese mismo
valor justo después de reanudar de suspensión. X11 resetea `xrandr
--brightness` a `1.0` al suspender, cerrar la tapa, cambiar de resolución o
reconectar el panel — sin el hook, hay que volver a escribir el comando a
mano cada vez.

`xrandr --brightness` es un multiplicador de software (gamma) aplicado por el
servidor X, **no** control real de backlight — para eso usa
[notify_brightness_linux.sh](notify_brightness_linux.md) (`brightnessctl`).
Sirve para compensar paneles cuyo brillo máximo de hardware no alcanza.

- **Ruta:** `scripts/hardware/configure_xrandr_brightness_linux.sh`
- **SO requerido:** Linux (Xorg + systemd)
- **Dependencias:** `bash`, `xrandr`, `sudo`, `systemd` (para el hook de
  suspensión)

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

- Sesión Xorg activa con una salida interna `eDP-*`/`LVDS-*`/`DSI-*`
  conectada (se detecta automáticamente; usa `--output` para forzar otra).
- `sudo` configurado para el usuario actual (solo se usa para instalar el
  hook en `/lib/systemd/system-sleep/`).
- El perfil de i3 ya desplegado (`~/.config/i3/config` debe existir).

## Uso

```bash
just configure-xrandr-brightness --check
just configure-xrandr-brightness --plan
just configure-xrandr-brightness --apply
```

Con un brillo o salida específicos:

```bash
just configure-xrandr-brightness --apply --brightness 1.2 --output eDP-1
```

Después de aplicar, recarga i3 (`$mod+Shift+r`) para que el `exec_always`
corra de inmediato; el hook de suspensión no requiere recargar nada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra salida detectada, brillo actual y objetivo, y estado del bloque/hook. |
| `--plan` | `--dry-run` | Muestra las acciones previstas sin modificar nada. |
| `--apply` | — | Escribe el bloque en i3 y el hook de systemd-sleep. |
| `--output <salida>` | — | Salida xrandr; por defecto detecta eDP/LVDS/DSI. |
| `--brightness <valor>` | — | Multiplicador de brillo (0.1-2.0); default `1.1`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `XRANDR_BRIGHTNESS_OUTPUT` | Sobrescrita por `--output` | Salida xrandr por defecto. |
| `XRANDR_BRIGHTNESS_VALUE` | Sobrescrita por `--brightness` | Brillo por defecto. |
| `XDG_CONFIG_HOME` | Entorno | Determina dónde se busca `i3/config`. |

No se usa `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```bash
just configure-xrandr-brightness --apply
```

### Diagnóstico antes de aplicar

```bash
just configure-xrandr-brightness --check
just configure-xrandr-brightness --plan
```

### Verificación posterior

```bash
xrandr --verbose | grep -A1 "^eDP-1" | grep Brightness
cat /lib/systemd/system-sleep/rafex-xrandr-brightness.sh
```

## Protecciones de seguridad

- `--check` y `--plan` no modifican nada ni solicitan `sudo`.
- Rechaza valores de brillo no numéricos o fuera de `0.1-2.0`.
- El bloque de i3 se parcha con marcadores `# BEGIN rafex xrandr-brightness`/
  `# END rafex xrandr-brightness` idempotentes (nunca toca el resto del
  archivo), con respaldo colocado (`config.bak.<fecha>`) antes de modificar —
  reconocible por [find_safety_backups_unix.sh](../dev/find_safety_backups_unix.md).
- El hook de systemd-sleep se respalda en
  `/var/backups/rafex-xrandr-brightness/` antes de reemplazarlo, y se instala
  con permisos `0755`.
- El hook solo ejecuta `xrandr --output ... --brightness ...` como el mismo
  usuario que corrió `--apply`; no ejecuta nada más ni acepta parámetros
  externos en tiempo de reanudación.
- `sudo` se solicita únicamente mediante `sudo -v` antes de escribir el hook.

## Fallos conocidos

### `no se pudo determinar la salida xrandr`

**Causa:** el script ya asume `DISPLAY=:0` si no está definida (una shell de
tmux/SSH normal no la exporta aunque la sesión gráfica real sí esté
corriendo), así que este error significa que no hay ningún servidor X en
`:0` o no se detectó ninguna salida `eDP-*`/`LVDS-*`/`DSI-*` conectada.

**Solución:** ejecuta el comando dentro de la sesión gráfica real (o con
`DISPLAY` apuntando a la correcta si usas otra distinta de `:0`), o indica
la salida exacta con `--output` (revisa `xrandr --query`).

### El brillo vuelve a `1.0` después de reanudar

**Causa:** el hook de systemd-sleep no está instalado, no es ejecutable, o
`DISPLAY`/`XAUTHORITY` no coinciden con la sesión real del usuario.

**Solución:** ejecuta `just configure-xrandr-brightness --check` para
confirmar que el hook está presente y ejecutable; revisa
`journalctl -b | grep rafex-xrandr-brightness` tras una suspensión real.

### El brillo no cambia visualmente

**Causa:** `xrandr --brightness` es un ajuste de gamma por software; algunos
paneles o compuestos (picom) pueden limitar su efecto visible.

**Solución:** confirma el valor efectivo con `xrandr --verbose`; para brillo
real de backlight usa `notify_brightness_linux.sh` en su lugar.

## Changelog

### [Unreleased]

- **feat:** agregar configuración idempotente de brillo xrandr en i3, con
  hook de systemd-sleep para reaplicarlo tras suspender/reanudar.
- **fix:** asumir `DISPLAY=:0` cuando no está exportada, para que `--check`/
  `--plan`/`--apply` funcionen desde una shell de tmux/SSH normal (donde la
  sesión gráfica real sí está corriendo, pero no exporta `DISPLAY`), no
  solo desde dentro de la sesión X directamente.
