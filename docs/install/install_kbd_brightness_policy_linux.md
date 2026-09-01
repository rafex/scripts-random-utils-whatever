---
title: install_kbd_brightness_policy_linux.sh
description: Prepara el brillo del teclado ThinkPad con el grupo input y un respaldo Polkit.
tags:
  - instalación
  - hardware
  - polkit
---

# install_kbd_brightness_policy_linux.sh

Añade el usuario actual al grupo `input` y registra un helper Polkit mínimo para
controlar únicamente `tpacpi::kbd_backlight`. El uso diario no ejecuta `sudo`.

- **Ruta:** `scripts/install/install_kbd_brightness_policy_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `id`, `getent`, `dpkg-query`, `apt-cache`, `sudo` solo para `--apply`, `pkexec`

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

- Ejecutar el instalador como `rafex`, no como `root`.
- Debian con APT y `sudo` configurado.
- El kernel debe exponer `/sys/class/leds/tpacpi::kbd_backlight` para que el
  control tenga efecto.
- La sesión gráfica debe tener Polkit y un agente activo para usar el respaldo.

## Uso

```sh
just install-kbd-brightness --check
just install-kbd-brightness --plan
just install-kbd-brightness --apply
just install-kbd-brightness --status
```

Después de `--apply`, cierra y abre la sesión gráfica. La nueva pertenencia a
`input` no aparece en procesos ya iniciados. Los bindings del perfil usan
`XF86LaunchA`/`XF86Explorer` y también los keysyms de brillo de teclado cuando
el firmware los expone.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Inspecciona grupo, archivos y dispositivo sin modificar nada. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin escribir archivos ni usar `sudo`. |
| `--apply` | — | Instala `pkexec` si falta, añade el usuario a `input` y registra la política. |
| `--status` | — | Muestra el estado del grupo, helper, política y LED. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El instalador no requiere variables de entorno. El usuario objetivo es el
usuario que ejecuta el script; no se acepta un usuario arbitrario mediante una
variable.

## Ejemplos

```sh
just install-kbd-brightness --check
just install-kbd-brightness --plan
just install-kbd-brightness --apply
id -nG
brightnessctl -d tpacpi::kbd_backlight get
brightnessctl -d tpacpi::kbd_backlight max
```

Para comprobar el helper desde la sesión gráfica, usa los atajos XF86. No lo
ejecutes directamente como root; la política lo autoriza mediante `pkexec`.

## Protecciones de seguridad

- `sudo` solo se usa durante `--apply`, para APT, `usermod` y copiar los dos
  archivos protegidos.
- El helper instalado es propiedad de `root:root`, modo `0755`, y la política
  es propiedad de `root:root`, modo `0644`.
- El helper acepta únicamente `up` o `down` y escribe únicamente en el LED
  fijo `tpacpi::kbd_backlight`.
- No se concede acceso Polkit a brillo de pantalla, dispositivos arbitrarios,
  comandos shell ni otros grupos.
- El grupo `input` permite leer eventos de `/dev/input/event*`, incluidos
  teclado, touchpad, Wacom y teclas multimedia. Esto es más amplio que solo
  controlar el LED y queda advertido explícitamente.
- Los bindings nunca contienen `sudo` y el helper no almacena credenciales.
- La instalación es idempotente: no duplica la pertenencia al grupo ni la
  política; los archivos protegidos se respaldan antes de cambiarse.

## Fallos conocidos

### `rafex no pertenece al grupo input` después de aplicar

**Causa:** la sesión actual conserva la lista de grupos anterior.

**Solución:** cierra y abre sesión, o reinicia. `newgrp input` puede servir para
  una prueba puntual, pero no reemplaza una nueva sesión gráfica.

### `No se pudo autorizar el cambio de brillo mediante Polkit`

**Causa:** falta un agente Polkit en la sesión gráfica, o la política no fue
  instalada correctamente.

**Solución:** ejecuta `just install-kbd-brightness --status`, confirma que
  `lxpolkit` o el agente equivalente está activo y revisa que existan el helper
  y la política. No agregues `sudo` al binding.

### `el LED tpacpi::kbd_backlight no está expuesto`

**Causa:** el firmware o el kernel no ofrecen el dispositivo esperado.

**Solución:** revisa `brightnessctl -l`; conserva `Fn+Space` como control nativo
  del firmware. Este instalador no fuerza módulos ni escribe otros LEDs.

## Changelog

### [Unreleased]

**feat:** añadir pertenencia idempotente a `input` y respaldo Polkit restringido
para el brillo XF86 del teclado.
