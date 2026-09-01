---
title: set_wallpaper_linux.sh
description: Aplica el fondo administrado del perfil ThinkPad con feh.
tags:
  - sistema
  - fondos
---

# set_wallpaper_linux.sh

Helper de usuario para aplicar el fondo del perfil sin generar `fehbg`.

- **Ruta:** `scripts/system/set_wallpaper_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** bash, `feh`.

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

Debe existir una sesión X11 y un fondo versionado del perfil ThinkPad.

## Uso

```bash
~/.local/bin/rafex-wallpaper.sh
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | No recibe opciones; aplica el fondo administrado. |

## Variables de entorno

Respeta `HOME`; no guarda estado ni credenciales.

## Ejemplos

```bash
just install-feh --apply
~/.local/bin/rafex-wallpaper.sh
```

## Fallos conocidos

### `feh no está instalado`

**Causa:** falta el paquete de Debian.

**Solución:** instala el perfil con `just install-feh --apply`.

## Changelog

### [Unreleased]
- **feat:** añadir helper común para fondos.
