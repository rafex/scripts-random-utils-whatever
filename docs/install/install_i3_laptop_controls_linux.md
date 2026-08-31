---
title: install_i3_laptop_controls_linux.sh
description: Instalar toggles y atajos multimedia para i3
tags:
  - instalación
  - i3
---

# install_i3_laptop_controls_linux.sh

Instala utilidades y configura atajos para volumen, brillo de pantalla, brillo
del teclado, micrófono, Wi‑Fi, modo avión, búsqueda Rofi, Synaptic y un centro
de control completo para i3. También instala `lxpolkit` para mostrar
gráficamente las solicitudes de autenticación.

- **Ruta:** `scripts/install/install_i3_laptop_controls_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con APT)
- **Dependencias:** `bash`, `apt-get`, `sudo`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

Ejecutar desde el repositorio como usuario normal con permisos `sudo`.

## Uso

```sh
just install-i3-laptop-controls --check
just install-i3-laptop-controls --plan
just install-i3-laptop-controls --apply
```

El bloque i3 añade `XF86AudioMicMute`, `XF86WLAN`, `XF86RFKill`,
`XF86Search`, `XF86LaunchA`, `XF86Explorer`,
`XF86WakeUp` y `XF86Tools`. `XF86LaunchA` baja y
`XF86Explorer` sube el brillo del teclado. `XF86Tools` abre
el centro de control completo; `XF86WakeUp` abre solo energía y sesión.
El navegador conserva un atajo alternativo en `Mod+Shift+b` y también
está disponible en Rofi. El centro incluye `Software — Synaptic`, que
se ejecuta mediante `synaptic-pkexec`.

F5/F6 siguen controlando el brillo de pantalla mediante `brightnessctl`.
Fn+Space continúa siendo el control nativo del firmware para la
retroiluminación del teclado.

Además, instala los helpers de brillo, `dunst` y registra `dunst-smart.sh`, que detecta si i3bar está
arriba o abajo y coloca las notificaciones fuera de su área.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquetes y archivos sin cambios persistentes. |
| `--plan` | `--dry-run` | Muestra paquetes y archivos que cambiarían. |
| `--apply` | — | Instala paquetes, helpers y el bloque i3; guarda un log. |
| `--log-file <archivo>` | — | Guarda la salida en el archivo indicado. Puede combinarse con cualquier modo. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `I3_CONTROLS_CONFIG` | `~/.config/i3/config` | Configuración i3 a modificar. |
| `I3_CONTROLS_LOG_FILE` | vacío | Archivo de log. Si se omite en `--apply`, se crea uno fechado en `~/.local/state/scripts-random-utils-whatever/logs/`. |
| `I3_CONTROLS_LOG_DIR` | `~/.local/state/scripts-random-utils-whatever/logs/` | Directorio de logs automáticos. |

## Ejemplos

```sh
just install-i3-laptop-controls --apply
just install-i3-laptop-controls --apply --log-file "$HOME/control-i3.log"
I3_CONTROLS_CONFIG="$HOME/.config/i3/config" \
  just install-i3-laptop-controls --plan
```

En `--apply`, la salida de `sudo apt-get`, la instalación y la configuración
se muestra en pantalla y se conserva en un log fechado. Si la ejecución falla,
el script imprime la ruta del log para facilitar el diagnóstico:

```sh
ls -lt "$HOME/.local/state/scripts-random-utils-whatever/logs/"
tail -n 80 "$HOME/.local/state/scripts-random-utils-whatever/logs/"*.log
```

`--check` y `--plan` no crean logs persistentes por defecto. Para registrar
explícitamente uno de esos modos, usa `--log-file`.

## Protecciones de seguridad

- Solicita autorización mediante `sudo -v`; nunca lee ni guarda la contraseña.
- Respaldа el archivo i3 y cada helper antes de reemplazarlo.
- Usa un bloque administrado idempotente y no duplica atajos.
- Elimina vinculaciones heredadas conflictivas de `XF86Tools`,
  `XF86WakeUp`, `XF86Explorer`, `XF86LaunchA` y
  el navegador alternativo fuera del bloque administrado para reparar perfiles
  anteriores sin perder el respaldo.
- Las acciones de energía del centro de control siempre piden confirmación;
  hibernar se comprueba con `loginctl can-hibernate` antes de ejecutarse.
- Los helpers de brillo no usan `sudo`.
- No modifica particiones, `fstab`, GRUB ni archivos de contraseñas.

## Fallos conocidos

### `justfile does not contain recipe install-i3-laptop-controls`

**Causa:** el repositorio de la ThinkPad no se ha actualizado con esta versión.
**Solución:** ejecutar `git pull --ff-only` después de sincronizar el commit.

### `El paquete «network-manager-gnome» no tiene un candidato` / `No se ha podido localizar el paquete xev`

**Causa:** en Debian Forky el paquete del applet se llama
`network-manager-applet` y `xev` es un ejecutable proporcionado por
`x11-utils`; ninguno debe instalarse con esos nombres antiguos.
**Solución:** actualizar el repositorio y repetir `--apply`; el instalador ya
usa los nombres correctos.

### `ERROR: Duplicate keybinding ... XF86WakeUp` o `XF86Tools`

**Causa:** una versión anterior del perfil ThinkPad definía esas teclas y el
instalador de controles también las añadía en su bloque administrado.

**Solución:** actualizar el repositorio y ejecutar `just install-i3-laptop-controls
--apply`. El archivo original se respalda y las vinculaciones duplicadas se
retiran únicamente fuera del bloque administrado. Después recarga i3 con
`Mod+Shift+r`.

### `F11` o `F12` no cambia el brillo del teclado

**Causa:** X11 puede reportar otro keysym, o el equipo puede no exponer un LED
de teclado escribible.

**Solución:** ejecuta `xev` y comprueba `brightnessctl -l`. Fn+Space
sigue siendo la alternativa del firmware. Si se reutiliza el perfil, vuelve a
ejecutar el instalador para reparar el bloque administrado.

## Changelog

### [Unreleased]

**feat:** instalador de controles multimedia y utilidades de i3.

**fix:** corregir nombres de paquetes para Debian Forky y registrar las
ejecuciones de aplicación con logs fechados.

**feat:** instalar `lxpolkit` y Synaptic para autenticación y administración
gráfica desde i3.
