---
title: theme_toggle_linux.sh
description: Selector de tema claro y oscuro para la sesión i3 de ThinkPad
tags:
  - i3
  - temas
  - configuración
---

# theme_toggle_linux.sh

Activa las paletas `light` y `dark` del perfil ThinkPad para i3, tmux,
Alacritty, Rofi y Dunst sin usar `sudo`.

- **Ruta:** `scripts/system/theme_toggle_linux.sh`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `bash`; opcionales `i3-msg`, `tmux`, `dunstctl`, `pgrep`

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

Instala el perfil `thinkpad-x1-yoga-1st` para crear las paletas en
`~/.config/rafex/themes`. El script puede ejecutarse desde SSH para revisar el
estado, pero la recarga de i3, tmux y Dunst requiere la sesión gráfica local.

## Uso

```sh
~/.local/bin/theme-toggle.sh --check
~/.local/bin/theme-toggle.sh --set light
~/.local/bin/theme-toggle.sh --set dark
~/.local/bin/theme-toggle.sh --toggle
```

El estado se guarda en `~/.config/rafex/theme` y el selector apunta
`~/.config/rafex/themes/current` a la paleta activa. El valor inicial es
`light`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paletas, estado y herramientas disponibles. |
| `--plan` | `--dry-run` | Muestra la paleta que se activaría sin modificar archivos. |
| `--set <modo>` | — | Activa `light` o `dark`. |
| `--toggle` | — | Alterna entre `light` y `dark`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio base de las paletas y del estado. |

No se aceptan credenciales ni se usa `.env`.

## Ejemplos

### Forma explícita recomendada

```sh
~/.local/bin/theme-toggle.sh --set light
```

### Alternar desde i3

Pulsa `Mod+Shift+T`, elige `Tema claro/oscuro` en 9menu o abre el centro Rofi
y selecciona `Tema visual — alternar`.

### Simular una activación

```sh
~/.local/bin/theme-toggle.sh --plan --set dark
```

### Diagnóstico remoto

```sh
ssh thinkpad '~/.local/bin/theme-toggle.sh --check'
```

## Protecciones de seguridad

- No requiere ni ejecuta `sudo`.
- `--check`, `--plan` y `--dry-run` no escriben archivos.
- Los archivos regulares existentes bajo `current` y el estado reciben
  respaldo fechado antes de reemplazarse.
- El enlace de la paleta se cambia mediante un enlace temporal y `mv` atómico.
- Solo modifica el estado y los fragmentos administrados del tema; no toca
  Xorg, DPI, autorandr ni configuraciones no administradas.

## Fallos conocidos

### `No existe la paleta`

**Causa:** el perfil ThinkPad todavía no fue instalado o sus archivos fueron
movidos.

**Solución:** ejecuta `just install-profile thinkpad-x1-yoga-1st` y repite el
diagnóstico.

### `i3 no pudo recargar su configuración`

**Causa:** el script se ejecutó por SSH o fuera de la sesión Xorg local.

**Solución:** inicia el selector desde i3 o ejecuta `i3-msg reload` dentro de la
sesión gráfica.

### `tmux no pudo recargar el tema`

**Causa:** no existe una sesión tmux activa o falta `tmux-256color`.

**Solución:** abre Alacritty, crea la sesión `thinkpad` y revisa
`infocmp tmux-256color`.

### `Una aplicación conserva sus colores`

**Causa:** algunas aplicaciones no leen cambios de tema en caliente.

**Solución:** reinicia esa aplicación; el selector solo recarga i3, tmux y
Dunst de forma controlada.

## Changelog

### [Unreleased]

**feat:** añadir paletas claras y oscuras centralizadas para ThinkPad.
