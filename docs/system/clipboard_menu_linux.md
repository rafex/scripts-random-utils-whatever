---
title: clipboard_menu_linux.sh
description: Abre y diagnostica el historial visual de CopyQ en una sesión X11.
tags:
  - sistema
  - portapapeles
  - x11
---

# clipboard_menu_linux.sh

Helper de usuario para abrir CopyQ desde i3, Openbox o una terminal X11.
Forma parte de `install_clipboard_linux.sh` y no solicita privilegios.

- **Ruta:** `scripts/system/clipboard_menu_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `copyq`, `pgrep`, `sleep`.

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

Instala CopyQ e integra el autostart con:

```bash
just install-clipboard --apply
```

## Uso

```bash
clipboard-menu.sh --show
clipboard-menu.sh --menu
clipboard-menu.sh --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--show` | — | Abre u oculta la ventana principal de CopyQ. |
| `--menu` | — | Abre el menú de la bandeja de CopyQ. |
| `--status` | `--check` | Muestra el servidor, rutas y DISPLAY sin abrir la interfaz. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `DISPLAY` | el de la sesión | Pantalla X11 donde se abrirá CopyQ. |
| `XDG_CONFIG_HOME` | — | CopyQ determina su ubicación de configuración. |

## Ejemplos

```bash
just clipboard-menu --show
just clipboard-menu --menu
just clipboard-menu --status
```

## Protecciones de seguridad

- Se rechaza ejecutarlo como root.
- No usa sudo ni imprime elementos del historial.
- No muestra el contenido del portapapeles en diagnósticos.
- El historial de CopyQ puede contener secretos; adminístralo desde la propia
  aplicación y evita copiar credenciales mientras esté activo.

## Fallos conocidos

### `CopyQ no respondió`

**Causa:** el servidor no arrancó o `DISPLAY` no corresponde a una sesión X11.

**Solución:** ejecuta `copyq` dentro de i3/Openbox y revisa que la sesión tenga
un agente gráfico y una bandeja disponible.

## Changelog

### [Unreleased]

- **feat:** añadir acceso CLI idempotente a CopyQ.
