---
title: install_i3lock_color_linux.sh
description: Compila i3lock-color en paralelo al bloqueador oficial de Debian.
tags:
  - instalación
  - seguridad
  - bloqueo
---

# install_i3lock_color_linux.sh

Instala `i3lock-color` en `~/.local/bin` sin reemplazar `/usr/bin/i3lock`.

- **Ruta:** `scripts/install/install_i3lock_color_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, git, autoconf, gcc, make, bibliotecas XCB/PAM y sudo para APT.

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

La instalación compila el tag `2.12.c.5`. `xss-lock` y el bloqueo automático
existente no cambian.

## Uso

```bash
just install-i3lock-color --check
just install-i3lock-color --plan
just install-i3lock-color --apply
just install-i3lock-color --status
just lock-screen --mode solid
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba dependencias y binarios. |
| `--plan` | `--dry-run` | Simula la compilación. |
| `--apply` | — | Compila e instala en el usuario. |
| `--status` | — | Muestra ambos bloqueadores. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `I3LOCK_COLOR_BIN` | `~/.local/bin/i3lock-color` | Binario usado por el wrapper. |

## Ejemplos

```bash
just lock-screen --mode solid
just lock-screen --mode image
just lock-screen --mode blur
just lock-screen --status
```

## Fallos conocidos

### `blur requiere ImageMagick`

**Causa:** el modo desenfoque necesita `convert` además de `maim`.

**Solución:** usa `solid` o `image`, o instala ImageMagick desde Debian.

## Changelog

### [Unreleased]
- **feat:** añadir compilación paralela y wrapper de bloqueo.
