---
title: dunst_smart_start_linux.sh
description: Inicia Dunst dejando libre el espacio ocupado por i3bar.
tags:
  - sistema
  - i3
  - notificaciones
---

# dunst_smart_start_linux.sh

Detecta si `i3bar` está arriba o abajo y genera una configuración de Dunst con
un margen suficiente para que las notificaciones no se empalmen con la barra.

- **Ruta:** `scripts/system/dunst_smart_start_linux.sh`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `bash`, `awk`, `dunst`; opcionales `dunstctl`, `pkill`, `pgrep`

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
lanzador como `~/.local/bin/dunst-smart.sh` y lo ejecuta desde i3.

## Uso

```sh
just dunst-smart --check
just dunst-smart --plan
just dunst-smart --apply
just dunst-smart --start
just dunst-smart --reload
```

La configuración generada se guarda en
`~/.config/rafex/dunst.conf`. La barra superior usa `origin = top-right` y la
barra inferior usa `origin = bottom-right`; ambos casos aplican un desplazamiento
vertical predeterminado de 36 píxeles.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra posición, margen y estado de Dunst sin escribir. |
| `--plan` | `--dry-run` | Muestra la configuración prevista sin escribir ni recargar. |
| `--apply` | — | Genera la configuración estable sin iniciar Dunst. |
| `--start` | — | Genera la configuración y arranca o recarga Dunst. |
| `--reload` | — | Regenera y recarga Dunst si ya está ejecutándose. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `I3_CONFIG` | `~/.config/i3/config` | Archivo donde se detecta la posición de i3bar. |
| `DUNST_THEME_CONFIG` | `~/.config/rafex/themes/current/dunst.conf` | Plantilla de tema activa. |
| `DUNST_SMART_CONFIG` | `~/.config/rafex/dunst.conf` | Configuración generada para Dunst. |
| `DUNST_BAR_MARGIN` | `36` | Margen vertical en píxeles respecto a i3bar. |
| `DUNST_BAR_POSITION` | autodetectado | Fuerza `top` o `bottom` si la detección no coincide. |

Los valores de CLI determinan la acción; las variables solo personalizan rutas
y el margen. No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```sh
~/.local/bin/dunst-smart.sh --check
~/.local/bin/dunst-smart.sh --reload
```

### Margen mayor para una barra personalizada

```sh
DUNST_BAR_MARGIN=44 ~/.local/bin/dunst-smart.sh --reload
```

### Forzar la posición durante el diagnóstico

```sh
DUNST_BAR_POSITION=top ~/.local/bin/dunst-smart.sh --plan
```

### Integración con el tema

`theme-toggle.sh` invoca `dunst-smart.sh --reload` cuando está instalado, por
lo que el cambio de paleta conserva la separación de i3bar.

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

### `Las notificaciones aún se empalman`

**Causa:** la barra tiene una altura personalizada mayor que el margen de 36
píxeles o Dunst fue iniciado con otra configuración.

**Solución:** usa `DUNST_BAR_MARGIN=48 dunst-smart.sh --reload` y comprueba
`dunst-smart.sh --check`.

### `Dunst no pudo recargarse`

**Causa:** no existe una sesión gráfica o el daemon no está ejecutándose con la
configuración generada.

**Solución:** ejecuta `dunst-smart.sh --start` desde la sesión local de i3.

## Changelog

### [Unreleased]

**feat:** detectar la posición de i3bar y reservar espacio para las
notificaciones Dunst.
