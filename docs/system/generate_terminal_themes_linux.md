---
title: generate_terminal_themes_linux.sh
description: Materializa las paletas de terminal, i3, Openbox, tint2, Conky, tmux, Rofi, Dunst y rxvt-unicode del perfil ThinkPad.
tags:
  - sistema
  - temas
  - referencia
---

# generate_terminal_themes_linux.sh

Genera las paletas versionadas del perfil `thinkpad-x1-yoga-1st` en la
configuración del usuario. No instala paquetes ni requiere `sudo`.

- **Ruta:** `scripts/system/generate_terminal_themes_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `cp`, `cmp`, `find`, `mktemp` y `mv`

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

Ejecuta el comando desde una copia del repositorio en Linux. Las plantillas
están en `dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes/`.

Cada paleta debe contener `i3.conf`, `i3status.conf`, `tmux.conf`,
`alacritty.toml`, `rofi.rasi`, `dunst.conf`, `xresources`, `openbox.themerc`,
`tint2.conf` y `conky.conf`. El archivo `i3status.conf` se sincroniza en
`~/.config/i3status/config` para que el texto de la barra conserve contraste
tanto en temas claros como oscuros.

## Uso

La tarea recomendada es:

```bash
just generate-terminal-themes --apply --theme all
```

Después selecciona una paleta con `theme-toggle.sh`:

```bash
~/.local/bin/theme-toggle.sh --set nord
```

El destino es `~/.config/rafex/themes/`. Alacritty, Rofi, Dunst, Openbox, tint2
y Conky utilizan el enlace `current` que mantiene el selector. Openbox, tint2
y Conky solo se sincronizan cuando sus configuraciones están instaladas.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba plantillas y destino sin modificar archivos. |
| `--plan` | `--dry-run` | Muestra las paletas que se materializarían. |
| `--apply` | — | Copia las paletas con reemplazo atómico. |
| `--theme <tema>` | — | Selecciona `paper`, `nord`, `everforest`, `dracula` o `all`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Cambia el directorio de configuración del usuario; por defecto `~/.config`. |

No se leen archivos `.env`. Las opciones de la línea de comandos determinan la
acción y la paleta.

## Ejemplos

Comprobar el estado sin cambios:

```bash
just generate-terminal-themes --check
```

Revisar y aplicar solo Nord:

```bash
just generate-terminal-themes --plan --theme nord
just generate-terminal-themes --apply --theme nord
~/.local/bin/theme-toggle.sh --set nord
```

Aplicar todas las paletas y recorrerlas:

```bash
just generate-terminal-themes --apply --theme all
~/.local/bin/theme-toggle.sh --list
~/.local/bin/theme-toggle.sh --cycle
```

## Protecciones de seguridad

- `--check` y `--plan` no escriben archivos ni crean respaldos.
- Los archivos existentes reciben un respaldo fechado antes de reemplazarse.
- La escritura se hace mediante archivo temporal y `mv`.
- No se ejecuta código descargado, no se usa `sudo` y no se guardan secretos.
- Las paletas antiguas `light` y `dark` se conservan como archivos del perfil;
  el selector las interpreta como alias de `nord` y `dracula`.

## Fallos conocidos

### `falta la plantilla de tema`

**Causa:** El script se ejecuta fuera de una copia completa del repositorio o
faltan archivos en el perfil ThinkPad.

**Solución:** Ejecuta el comando desde la raíz del repositorio y actualiza la
copia con `git pull --ff-only`.

### `rxvt` no cambia de color

**Causa:** `xrdb` solo puede actualizar una sesión X11 disponible y rxvt ya
abierto no siempre relee los recursos automáticamente.

**Solución:** Ejecuta `xrdb -merge ~/.Xresources` y abre una nueva ventana de
`urxvt`.

## Changelog

### [Unreleased]

- **feat:** Añadir Paper, Nord, Everforest y Dracula con soporte para
  rxvt-unicode, i3status, Openbox, tint2 y Conky.

### v1.0.0 — 2026-08-29

**feat:** Crear el materializador idempotente de paletas ThinkPad.
