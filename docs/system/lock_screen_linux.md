---
title: lock_screen_linux.sh
description: Bloquea X11 con i3lock-color en modos sólido, imagen o desenfoque.
tags:
  - sistema
  - seguridad
---

# lock_screen_linux.sh

Wrapper usado por el bloqueo manual y, después de `install-i3lock-color
--apply`, por `xss-lock` en i3/Openbox. El i3lock oficial se conserva como
respaldo.

- **Ruta:** `scripts/system/lock_screen_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** bash, i3lock-color local; `maim` y ImageMagick solo para `blur`.

---

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

Instala primero `i3lock-color` y ejecuta `just install-i3lock-color --apply`
para activar el wrapper en el atajo y el bloqueo automático. El wrapper pasa
`--nofork` para que `xss-lock` mantenga correctamente la sesión bloqueada.

## Uso

```bash
just lock-screen --mode solid
just lock-screen --mode image
just lock-screen --mode blur
just lock-screen --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--mode solid` | — | Fondo Nord sólido. |
| `--mode image` | — | Usa el fondo de login del perfil. |
| `--mode blur` | — | Captura temporal, desenfoque y borrado al salir. |
| `--status` | — | Comprueba bloqueadores sin bloquear. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `I3LOCK_COLOR_BIN` | `~/.local/bin/i3lock-color` | Ruta alternativa del binario. |

## Ejemplos

```bash
just lock-screen --mode solid
just lock-screen --mode blur
```

## Protecciones de seguridad

La captura del modo `blur` se guarda en un directorio temporal privado y se
elimina mediante `trap`; no se conserva una imagen permanente.

## Fallos conocidos

### `i3lock-color no está instalado`

**Causa:** solo se encuentra el bloqueador de Debian.

**Solución:** ejecuta `just install-i3lock-color --apply`.

## Changelog

### [Unreleased]
- **feat:** añadir tres modos de bloqueo y ejecución sin fork para `xss-lock`.
