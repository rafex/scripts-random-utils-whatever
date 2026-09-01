---
title: kbd_brightness_privileged_linux.sh
description: Helper interno restringido para modificar la retroiluminación del teclado mediante Polkit.
tags:
  - hardware
  - polkit
  - seguridad
---

# kbd_brightness_privileged_linux.sh

Helper interno instalado en `/usr/local/libexec` para el respaldo Polkit del
brillo del teclado ThinkPad. No es una interfaz de usuario general.

- **Ruta:** `scripts/system/kbd_brightness_privileged_linux.sh`
- **SO requerido:** Linux (ThinkPad con `tpacpi::kbd_backlight`)
- **Dependencias:** `bash`, sysfs, ejecución autorizada por Polkit como root

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

El instalador [install_kbd_brightness_policy_linux.sh](../install/install_kbd_brightness_policy_linux.md)
debe haber instalado el helper como `root:root` con modo `0755` y registrado la
acción `org.rafex.kbd-backlight`.

## Uso

El script no debe invocarse directamente. `notify_kbd_brightness_linux.sh`
intenta primero `brightnessctl` o sysfs con los permisos normales y solo llama
a `pkexec` cuando la sesión todavía no incorporó el grupo `input`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `up` | — | Incrementa un nivel del LED fijo. |
| `down` | — | Reduce un nivel del LED fijo. |

Cualquier otro argumento se rechaza.

## Variables de entorno

No acepta variables de entorno para seleccionar el dispositivo, el archivo o la
operación. La ruta está compilada en el helper para impedir que una acción
Polkit se convierta en escritura arbitraria.

## Ejemplos

Uso indirecto desde los atajos del perfil:

```sh
~/.local/bin/kbd-brightness-notify.sh down
~/.local/bin/kbd-brightness-notify.sh up
```

No se recomienda ejecutar:

```sh
sudo /usr/local/libexec/rafex-kbd-backlight up
```

La prueba correcta es usar el binding XF86 después de instalar la política y
abrir una nueva sesión.

## Protecciones de seguridad

- Rechaza toda ejecución que no sea como root; el root debe provenir de Polkit.
- Acepta únicamente `up` y `down`.
- Solo lee y escribe `brightness` dentro de
  `/sys/class/leds/tpacpi::kbd_backlight`.
- Valida que los niveles sean enteros y limita el resultado entre cero y el
  máximo anunciado por el dispositivo.
- No ejecuta comandos externos, no recibe rutas y no maneja PIN, contraseñas ni
  archivos del usuario.
- La política Polkit permite la acción al usuario local activo, no a sesiones
  inactivas o remotas.

## Fallos conocidos

### `este helper debe ejecutarse mediante Polkit`

**Causa:** se intentó ejecutarlo como usuario normal.

**Solución:** usa `kbd-brightness-notify.sh`; no cambies permisos del helper ni
lo ejecutes manualmente con `sudo` desde un binding.

### `no existe el LED tpacpi::kbd_backlight`

**Causa:** el hardware no expone ese LED en sysfs.

**Solución:** usa `brightnessctl -l` y el control de firmware disponible. No se
  debe redirigir este helper a otro dispositivo.

## Changelog

### [Unreleased]

**feat:** helper root mínimo para el respaldo Polkit del brillo XF86 del teclado.
