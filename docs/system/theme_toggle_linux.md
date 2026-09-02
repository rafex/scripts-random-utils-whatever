---
title: theme_toggle_linux.sh
description: Selector de cuatro paletas para i3, Openbox, tint2, Conky, EWW, tmux, Alacritty, rxvt-unicode, Rofi y Dunst en ThinkPad.
tags:
  - i3
  - temas
  - configuración
---

# theme_toggle_linux.sh

Activa las paletas `paper`, `nord`, `everforest` y `dracula` del perfil
ThinkPad para i3, Openbox, tint2, i3status, Conky, EWW, tmux, Alacritty,
rxvt-unicode, Rofi y Dunst sin usar `sudo`.

- **Ruta:** `scripts/system/theme_toggle_linux.sh`
- **SO requerido:** Linux (Xorg/i3 u Openbox)
- **Dependencias:** `bash`; opcionales `i3-msg`, `openbox`, `tmux`, `tint2`, `dunstctl`, `conky-launch.sh`, `pgrep`

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

Instala el perfil `thinkpad-x1-yoga-1st` y ejecuta el generador para crear las paletas en
`~/.config/rafex/themes`. El script puede ejecutarse desde SSH para revisar el
estado, pero la recarga de i3, tmux y Dunst requiere la sesión gráfica local.

## Uso

```sh
~/.local/bin/theme-toggle.sh --check
~/.local/bin/theme-toggle.sh --list
~/.local/bin/theme-toggle.sh --set nord
~/.local/bin/theme-toggle.sh --set paper
~/.local/bin/theme-toggle.sh --set everforest
~/.local/bin/theme-toggle.sh --set dracula
~/.local/bin/theme-toggle.sh --cycle
~/.local/bin/theme-toggle.sh --toggle
```

El estado se guarda en `~/.config/rafex/theme` y el selector apunta
`~/.config/rafex/themes/current` a la paleta activa. El valor inicial es
`nord`. `light` es alias de `nord` y `dark` es alias de `dracula`. Los colores de i3 se sincronizan en un bloque administrado dentro de
`~/.config/i3/config`; esto evita depender de la expansión de `~` en la
directiva `include` de algunas versiones de i3. Los colores de i3status se
sincronizan en `~/.config/i3status/config` para conservar contraste en la barra.
La paleta X11 se sincroniza en `~/.Xresources` y se aplica con `xrdb` cuando
existe una sesión gráfica. Si la sesión activa es Openbox, también actualiza
su tema `~/.themes/Rafex-*/openbox-3/themerc`, el bloque administrado de
`~/.config/openbox/rc.xml`, el bloque de colores de `~/.config/tint2/tint2rc`
y el bloque de colores de `~/.config/conky/conky.conf` si Conky está instalado.
Si el dashboard EWW administrado existe, reemplaza solo su estilo por la
paleta activa y recarga únicamente el daemon EWW de usuario; la geometría y el
fondo transparente permanecen sin cambios.
Si la sesión activa es i3, solo recarga i3; no intenta conectarse a un socket
de i3 inexistente desde Openbox.

Cuando está instalado `dunst-smart.sh`, las notificaciones se regeneran según
la posición de i3bar y reservan un margen vertical para no empalmarse con la
barra.

Cuando está instalado `conky-launch.sh`, el selector recarga únicamente la
instancia Conky administrada por Rafex. No detiene instancias de otros usuarios
ni configura Conky desde SSH sin `DISPLAY`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paletas, estado y herramientas disponibles. |
| `--plan` | `--dry-run` | Muestra la paleta que se activaría sin modificar archivos. |
| `--list` | — | Lista las cuatro paletas y marca la activa. |
| `--set <modo>` | — | Activa `paper`, `nord`, `everforest` o `dracula`; acepta `light`/`dark` como alias. |
| `--cycle` | — | Activa la siguiente paleta en orden Paper, Nord, Everforest, Dracula. |
| `--toggle` | — | Alterna entre `nord` y `dracula`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio base de las paletas y del estado. |

No se aceptan credenciales ni se usa `.env`.

## Ejemplos

### Forma explícita recomendada

```sh
~/.local/bin/theme-toggle.sh --set nord
```

### Alternar desde i3

Pulsa `Mod+Shift+T`, elige `Tema claro/oscuro` o una paleta concreta en 9menu,
o abre el centro Rofi y selecciona la paleta deseada.

### Simular una activación

```sh
~/.local/bin/theme-toggle.sh --plan --set dracula
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

### `Openbox o i3 no pudo recargar su configuración`

**Causa:** el script se ejecutó por SSH, fuera de la sesión Xorg local o el
gestor de ventanas no está activo todavía.

**Solución:** inicia el selector desde el entorno gráfico. En i3 puedes
ejecutar `i3-msg reload`; en Openbox, `openbox --reconfigure`.

### `tmux no pudo recargar el tema`

**Causa:** no existe una sesión tmux activa o falta `tmux-256color`.

**Solución:** abre Alacritty, crea la sesión `thinkpad` y revisa
`infocmp tmux-256color`.

### `Una aplicación conserva sus colores`

**Causa:** algunas aplicaciones no leen cambios de tema en caliente.

**Solución:** reinicia esa aplicación; el selector solo recarga i3, tmux y
Dunst de forma controlada.

### `i3bar muestra texto invisible o colores como $theme_bar_fg`

**Causa:** una configuración anterior usaba `include
~/.config/rafex/themes/current/i3.conf`; algunas versiones de i3 no expanden
esa ruta y dejan las variables sin resolver.

**Solución:** instala la versión actual del selector y ejecuta
`theme-toggle.sh --set nord` o `theme-toggle.sh --set dracula`. El script migra la
línea antigua al bloque administrado y recarga i3 cuando se ejecuta dentro de
la sesión gráfica.

### `La terminal rxvt no usa la paleta nueva`

**Causa:** `urxvt` lee Xresources al iniciar y no todas las ventanas releen
recursos después de `xrdb -merge`.

**Solución:** ejecuta `xrdb -merge ~/.Xresources` y abre una nueva ventana de
`urxvt`. La fuente definida por el perfil es DejaVu Sans Mono tamaño `7`, igual
que Alacritty. Si resulta demasiado pequeña, ajusta `URxvt.font` en la
configuración local después de probar la nueva ventana.

## Changelog

### [Unreleased]

**feat:** añadir cuatro paletas centralizadas, colores contrastados de i3status
y soporte Xresources para ThinkPad.
