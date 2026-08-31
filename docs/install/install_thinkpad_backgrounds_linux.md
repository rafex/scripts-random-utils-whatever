---
title: install_thinkpad_backgrounds_linux
description: Aplica los fondos del perfil ThinkPad a i3, GRUB y LightDM
tags:
  - linux
  - thinkpad
  - i3
  - grub
---

# install_thinkpad_backgrounds_linux

Instala los cinco fondos de identidad del perfil `thinkpad-x1-yoga-1st` y aplica
el fondo adecuado a la sesión i3, GRUB y el greeter GTK de LightDM.

- **Ruta:** `scripts/install/install_thinkpad_backgrounds_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `coreutils`, `awk`, `grep`; `feh` para mostrar el fondo en i3; `sudo` y `update-grub` para GRUB; `lightdm-gtk-greeter` para la pantalla de inicio.

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

- Ejecutar desde una copia del repositorio que contenga:
  `dotfiles/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/`.
- Ejecutar como usuario normal; el script rechaza una ejecución directa como root.
- Tener instalado el perfil i3 antes de aplicar la etapa `desktop`.
- Tener GRUB instalado para la etapa `grub`.
- Tener LightDM y `lightdm-gtk-greeter` para la etapa `login`.
- La etapa `grub` requiere poder usar `sudo`; `update-grub` se ejecuta después de validar la configuración.

## Uso

Desde la raíz del repositorio:

```bash
just install-thinkpad-backgrounds --check
just install-thinkpad-backgrounds --plan --stage all
just install-thinkpad-backgrounds --apply --stage desktop
just install-thinkpad-backgrounds --apply --stage grub
just install-thinkpad-backgrounds --apply --stage login
```

Las etapas también se pueden combinar:

```bash
just install-thinkpad-backgrounds --apply --stage all
```

`desktop` copia los fondos al área de usuario, agrega un bloque administrado
a `~/.config/i3/config` y recarga i3 solo cuando existe una sesión gráfica
local. `grub` instala el fondo en `/boot/grub/`, actualiza
`/etc/default/grub` y ejecuta `update-grub`. `login` instala el fondo en
`/usr/local/share/backgrounds/rafex/` y configura
`lightdm-gtk-greeter.conf`, pero no reinicia LightDM.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba fuentes, destinos y bloques administrados sin modificar archivos. Devuelve error si falta algún elemento de la etapa. |
| `--plan` | `--dry-run` | Muestra las acciones previstas; no crea respaldos, no solicita sudo y no modifica archivos. |
| `--apply` | — | Aplica la etapa seleccionada. Solicita sudo solo si incluye GRUB o LightDM. |
| `--status` | — | Muestra el estado de fuentes y destinos sin usar sudo ni recargar servicios. |
| `--stage desktop` | — | Instala los cinco fondos en el usuario y configura i3. Es la etapa predeterminada. |
| `--stage grub` | — | Configura el fondo de arranque de GRUB. |
| `--stage login` | — | Configura el fondo de LightDM GTK. |
| `--stage all` | — | Ejecuta las etapas `desktop`, `grub` y `login`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de entorno ni archivos `.env`. Las rutas se calculan
desde la raíz del repositorio, `$HOME` y las rutas estándar del sistema.

## Ejemplos

Aplicar primero la sesión gráfica y validar i3:

```bash
just install-thinkpad-backgrounds --apply --stage desktop
i3 -C -c ~/.config/i3/config
i3-msg reload
```

Aplicar GRUB y conservar la posibilidad de volver atrás:

```bash
just install-thinkpad-backgrounds --plan --stage grub
just install-thinkpad-backgrounds --apply --stage grub
just install-thinkpad-backgrounds --status
```

Aplicarlo desde SSH:

```bash
ssh thinkpad 'cd /opt/repository/github/rafex/scripts-random-utils-whatever &&
  just install-thinkpad-backgrounds --apply --stage grub'
```

La etapa `desktop` no puede recargar una sesión i3 si se ejecuta por SSH.
Después de volver a la sesión gráfica, usar:

```bash
i3-msg reload
```

Para revisar el estado sin cambios:

```bash
just install-thinkpad-backgrounds --status
just install-thinkpad-backgrounds --check --stage all
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no escriben en el sistema ni solicitan sudo.
- Las configuraciones existentes de i3, GRUB y LightDM se respaldan antes de
  modificarse.
- Los respaldos de usuario se guardan en
  `~/.local/state/rafex/backups/thinkpad-backgrounds/`; los respaldos del
  sistema en `/var/backups/rafex-thinkpad-backgrounds/`.
- El bloque administrado se reemplaza de forma idempotente; no se duplican
  entradas al repetir la instalación.
- Si ya existe un `GRUB_BACKGROUND` fuera del bloque administrado, el script
  se detiene y solicita revisión manual.
- `update-grub` se valida y, si falla, se restaura automáticamente
  `/etc/default/grub` desde el respaldo de esta ejecución.
- No se reinicia LightDM, no se reinicia el equipo y no se modifican Xorg,
  particiones, LUKS, LVM, `fstab` ni credenciales.
- El fondo de escritorio usa `feh` solo dentro de la sesión del usuario.

## Fallos conocidos

### `GRUB_BACKGROUND no administrado ya existe`

**Causa:** GRUB ya tiene un fondo configurado fuera del bloque de Rafex.

**Solución:** revisar `/etc/default/grub`, conservar o retirar manualmente la
configuración anterior y repetir la etapa `grub`.

### `no existe ~/.config/i3/config`

**Causa:** el perfil i3 todavía no fue instalado o se está ejecutando otro
window manager.

**Solución:** ejecutar `just install-profile thinkpad-x1-yoga-1st` y repetir
`--stage desktop`. Las imágenes se copian aunque no exista i3.

### `LightDM o lightdm-gtk-greeter no está instalado`

**Causa:** el equipo usa otro gestor de sesiones o no tiene instalado el
greeter GTK.

**Solución:** instalar LightDM y `lightdm-gtk-greeter` si ese es el gestor
elegido. El script no cambia automáticamente el display manager.

### El fondo de i3 no cambia inmediatamente

**Causa:** la etapa se ejecutó por SSH o i3 no tiene un socket disponible.

**Solución:** ejecutar `i3-msg reload` desde la sesión gráfica. El cambio
queda persistente en el bloque administrado.

## Changelog

### [Unreleased]

- `feat:` instalador por etapas para escritorio i3, GRUB y LightDM.
- `feat:` respaldos, reemplazo idempotente y validación de conflictos de GRUB.

