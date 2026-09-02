---
title: rafex_ratmenu_linux.sh
description: Menú activo de acciones Rafex para la ThinkPad mediante ratmenu.
tags:
  - sistema
  - menú
  - thinkpad
---

# rafex_ratmenu_linux.sh

Abre el menú ligero de aplicaciones, controles, capturas y energía mediante
ratmenu. Si ratmenu no está disponible, usa el menú 9menu versionado como
fallback.

- **Ruta:** `scripts/system/rafex_ratmenu_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `ratmenu` y helpers del perfil.

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

Debe ejecutarse dentro de i3 u Openbox. Las acciones sensibles conservan las
confirmaciones de los helpers existentes.

## Uso

```bash
just install-ratmenu --apply
just rafex-ratmenu
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | El menú no necesita argumentos. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `HOME` | sesión actual | Ubicación de helpers y configuración. |

## Ejemplos

```bash
~/.local/bin/rafex-ratmenu.sh
```

## Fallos conocidos

### `ratmenu no está instalado`

**Causa:** se intentó abrir el helper antes del instalador.

**Solución:** instala con `just install-ratmenu --apply`.

## Changelog

### [Unreleased]
- **feat:** crear menú activo ratmenu con respaldo 9menu.
- **fix:** activar fallback automático a 9menu cuando ratmenu no está disponible.
