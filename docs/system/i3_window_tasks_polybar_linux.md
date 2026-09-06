---
title: i3_window_tasks_polybar_linux.sh
description: Genera el listado seguro de ventanas del workspace actual para Polybar.
tags:
  - sistema
  - i3
  - polybar
---

# i3_window_tasks_polybar_linux.sh

Genera una línea de salida para el módulo `custom/script` de Polybar. Muestra
las ventanas normales del workspace enfocado con un glifo semántico, título
corto y una única acción: enfocar la ventana con clic izquierdo.

- **Ruta:** `scripts/system/i3_window_tasks_polybar_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `python3`, `i3-msg` y una sesión X11 con `DISPLAY`.

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

Debe ejecutarse dentro de i3, con `i3-msg -t get_tree` disponible y acceso al
socket IPC de la sesión. Polybar debe tener instaladas las familias `Font
Awesome 7 Free Solid` y `Font Awesome 7 Brands Regular` para mostrar todos los
glifos semánticos. Si no hay ventanas normales, se muestra
`Escritorio`.

Tint2 usa su taskbar nativo y puede mostrar el icono real publicado por cada
ventana mediante `_NET_WM_ICON`; este helper no intenta leer imágenes. Polybar
recibe texto, por lo que usa una allowlist de glifos para Firefox, Chromium,
terminales, editores, gestores de archivos y una ventana genérica.

## Uso

```bash
just i3-window-tasks
~/.local/bin/i3-window-tasks-polybar.sh
```

El módulo Polybar lo invoca automáticamente una vez por segundo desde
`~/.config/rafex/i3-bars/polybar.ini`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| *(sin opciones)* | — | Imprime las ventanas normales del workspace actual. |
| *(cualquier argumento)* | — | Se rechaza; el helper no acepta comandos operativos. |

Los argumentos adicionales se rechazan explícitamente; no se interpretan como
comandos.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `DISPLAY` | — | Identifica la sesión X11 y es obligatorio. |
| `I3SOCK` | — | Puede ser usado por `i3-msg` para seleccionar el socket IPC. |

No se usan archivos `.env` ni variables para introducir acciones.

## Ejemplos

```bash
# Inspección desde la sesión gráfica.
just i3-window-tasks

# Ejecutar el helper instalado directamente.
DISPLAY=:0 ~/.local/bin/i3-window-tasks-polybar.sh

# Probar la plantilla completa de Polybar.
polybar -l info --config="$HOME/.config/rafex/i3-bars/polybar.ini" rafex
```

## Protecciones de seguridad

- Solo consulta `i3-msg -t get_tree`; no usa `i3-msg` para modificar layouts.
- Solo enumera ventanas del workspace actualmente enfocado.
- Ignora scratchpad, contenedores sin una ventana X11 y nodos sin identificador
  numérico.
- El título se limita a 24 caracteres y se eliminan controles, saltos de línea,
  llaves y marcadores `%` que podrían alterar el markup de Polybar.
- La acción de cada botón contiene únicamente un identificador numérico de i3
  y `focus`; no incorpora títulos, clases ni comandos proporcionados por el
  usuario.
- No ofrece clic central, derecho, cierre, minimización, movimiento ni shell
  remoto.
- No requiere `sudo`, no abre sockets de red y no registra títulos ni clases.

## Fallos conocidos

### `DISPLAY no está disponible`

**Causa:** se ejecutó desde una TTY o una conexión SSH sin el entorno X11 de la
sesión gráfica.

**Solución:** ejecuta el helper desde i3 o define el `DISPLAY` y el socket IPC
de la sesión correcta.

### `árbol i3 inválido`

**Causa:** `i3-msg` devolvió un error, una respuesta incompleta o texto que no
es JSON.

**Solución:** comprueba `i3-msg -t get_tree` y revisa el log de i3; Polybar
volverá a consultar el helper en el siguiente intervalo.

### Los iconos de Firefox o Chromium no aparecen

**Causa:** Firefox y Chromium usan glifos de la familia de marcas (`Brands`),
no de `Font Awesome 7 Free Solid`. La plantilla administrada debe declarar
`Font Awesome 7 Brands Regular` como `font-2`.

**Solución:** reinstala la configuración administrada y recarga Polybar:

```bash
just install-i3-bar-profiles --apply
just i3-bar --set polybar
```

### Los glifos aparecen como cuadrados

**Causa:** falta Font Awesome o Polybar no está usando las fuentes configuradas
en `font-1` y `font-2`.

**Solución:** instala la fuente administrada por el perfil y recarga Polybar.
Tint2 seguirá usando sus iconos reales independientemente de este mapeo.

## Changelog

### [Unreleased]

- **feat:** añadir listado de ventanas del workspace actual para Polybar con
  enfoque seguro mediante clic izquierdo.
- **fix:** declarar también `Font Awesome 7 Brands Regular` para que los
  iconos de Firefox y Chromium se rendericen en Polybar.
