---
title: dunst_smart_start_linux.sh
description: Coloca Dunst debajo de la barra activa sin reservar espacio.
tags:
  - sistema
  - i3
  - notificaciones
---

# dunst_smart_start_linux.sh

Lee el perfil activo de barra (`i3bar`, `tint2` o `polybar`), calcula su altura
en píxeles y genera una configuración de Dunst con `origin = top-right` y un
`offset` vertical igual a esa altura. No usa `bottom-right`, no reserva espacio
adicional y no modifica la configuración de la barra.

- **Ruta:** `scripts/system/dunst_smart_start_linux.sh`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `bash`, `awk`, `dunst`; `i3-msg` y `python3` para i3bar;
  `xdpyinfo` para convertir alturas Polybar en `pt`; opcionales `dunstctl`,
  `pkill`, `pgrep`

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

Debe existir el tema activo en
`~/.config/rafex/themes/current/dunst.conf`. El perfil ThinkPad instala el
lanzador como `~/.local/bin/dunst-smart.sh` y lo ejecuta desde i3. También debe
existir `~/.config/rafex/i3-bar-profile` con uno de `i3bar`, `tint2` o
`polybar`, junto con la configuración correspondiente de la barra.

## Uso

```sh
just dunst-smart --check
just dunst-smart --plan
just dunst-smart --apply
just dunst-smart --start
just dunst-smart --reload
```

La configuración generada se guarda en `~/.config/rafex/dunst.conf` y siempre
contiene `origin = top-right`. El desplazamiento vertical se obtiene así:

- `tint2`: segundo valor de `panel_size` en `~/.config/rafex/i3-bars/tint2rc`.
- `polybar`: `height` más sus bordes en `polybar.ini`; los valores `pt` se
  convierten usando el DPI de X11.
- `i3bar`: `bar_height` del IPC de i3.

Por ejemplo, una barra de 28 píxeles produce `offset = (10, 28)`. El script
no añade un margen arbitrario ni permite que una barra desconocida fuerce una
posición inferior.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra perfil, altura calculada y estado sin escribir. |
| `--plan` | `--dry-run` | Muestra la configuración prevista sin escribir ni recargar. |
| `--apply` | — | Genera la configuración estable sin iniciar Dunst. |
| `--start` | — | Genera la configuración y arranca o recarga Dunst. |
| `--reload` | — | Regenera y recarga Dunst si ya está ejecutándose. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `DUNST_THEME_CONFIG` | `~/.config/rafex/themes/current/dunst.conf` | Plantilla de tema activa. |
| `DUNST_SMART_CONFIG` | `~/.config/rafex/dunst.conf` | Configuración generada para Dunst. |
| `XDG_CONFIG_HOME` | `~/.config` | Raíz de las configuraciones del usuario. |

Los valores de CLI determinan la acción; las variables solo personalizan rutas.
No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```sh
~/.local/bin/dunst-smart.sh --check
~/.local/bin/dunst-smart.sh --reload
```

### Diagnóstico de la barra activa

```sh
~/.local/bin/dunst-smart.sh --check
~/.local/bin/dunst-smart.sh --plan
```

### Integración con el tema

`theme-toggle.sh` invoca `dunst-smart.sh --reload` cuando está instalado, por
lo que el cambio de paleta conserva `top-right` y vuelve a calcular la altura
de la barra activa.

## Protecciones de seguridad

- `--check` y `--plan` no modifican archivos ni procesos.
- No requiere `sudo` y no almacena credenciales.
- La configuración se escribe en un archivo temporal y se reemplaza mediante
  `mv` atómico.
- La configuración anterior recibe respaldo fechado antes de cambiarse.
- No modifica i3, Xorg, pantallas ni configuraciones de hardware.

## Fallos conocidos

### `no existe la configuración activa de Dunst`

**Causa:** el perfil no fue instalado o las paletas todavía no fueron
materializadas.

**Solución:** ejecuta `just generate-terminal-themes --apply --theme all` y
revisa `~/.config/rafex/themes/current/dunst.conf`.

### `no se pudo determinar la altura de la barra activa`

**Causa:** falta el archivo del perfil activo, no está disponible el IPC de i3,
la altura usa una unidad no soportada o no se puede consultar el DPI de X11.

**Solución:** ejecuta `dunst-smart.sh --check`, confirma que existe
`~/.config/rafex/i3-bar-profile` y que la configuración de la barra activa es
legible. `--apply`, `--start` y `--reload` se detienen sin modificar Dunst
hasta resolver la altura.

### `Dunst no pudo recargarse`

**Causa:** no existe una sesión gráfica o el daemon no está ejecutándose con la
configuración generada.

**Solución:** ejecuta `dunst-smart.sh --start` desde la sesión local de i3.

## Changelog

### [Unreleased]

- **fix:** mantener Dunst en `top-right` y calcular el offset con la altura de
  `i3bar`, Tint2 o Polybar.
- **fix:** eliminar los fallbacks `bottom-right` y la altura fija de 36 píxeles.
