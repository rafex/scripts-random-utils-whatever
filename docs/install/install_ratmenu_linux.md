---
title: install_ratmenu_linux.sh
description: Instala ratmenu como menú activo y conserva 9menu como fallback.
tags:
  - instalación
  - menú
  - thinkpad
---

# install_ratmenu_linux.sh

Configura el menú ligero del perfil Rafex para i3 y Openbox.

- **Ruta:** `scripts/install/install_ratmenu_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, apt-cache, dpkg-query, ratmenu, sudo en `--apply`.

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

`9menu` se conserva instalado y `~/.config/9menu/laptop.menu` permanece como
respaldo. `ratmenu` ejecuta solo las acciones definidas por el helper.

## Uso

```bash
just install-ratmenu --check
just install-ratmenu --plan
just install-ratmenu --apply
just install-ratmenu --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba candidato e integración. |
| `--plan` | `--dry-run` | Simula la migración. |
| `--apply` | — | Instala ratmenu y migra los accesos conocidos. |
| `--status` | — | Muestra ratmenu y el fallback. |

## Variables de entorno

No requiere variables. El tema se lee de `~/.config/rafex/theme` sin mostrar
credenciales.

## Ejemplos

```bash
just install-ratmenu --apply
~/.local/bin/rafex-ratmenu.sh
9menu -popup -label ThinkPad -file ~/.config/9menu/laptop.menu
```

## Fallos conocidos

### `ratmenu no está instalado`

**Causa:** aún no se ejecutó la instalación.

**Solución:** ejecuta `just install-ratmenu --apply`; usa 9menu mientras tanto.

## Changelog

### [Unreleased]
- **feat:** incorporar ratmenu sin retirar 9menu.
