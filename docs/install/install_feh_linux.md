---
title: install_feh_linux.sh
description: Instala feh y unifica el fondo ThinkPad en i3 y Openbox.
tags:
  - instalación
  - fondos
  - thinkpad
---

# install_feh_linux.sh

Instala `feh` y el helper `rafex-wallpaper.sh`, evitando autostarts duplicados.

- **Ruta:** `scripts/install/install_feh_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, dpkg-query, sudo solo en `--apply`.

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

Ejecuta como usuario normal. El helper busca el fondo versionado del perfil y,
si no existe, un fondo en `~/Imágenes/FondosDePantalla`.

## Uso

```bash
just install-feh --check
just install-feh --plan
just install-feh --apply
just install-feh --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquete, helper e integraciones. |
| `--plan` | `--dry-run` | Muestra acciones sin escribir. |
| `--apply` | — | Instala y actualiza i3/Openbox. |
| `--status` | — | Muestra el estado actual. |

## Variables de entorno

No requiere variables. Respeta `HOME` y `XDG_CONFIG_HOME`.

## Ejemplos

```bash
just install-feh --apply
~/.local/bin/rafex-wallpaper.sh
```

## Fallos conocidos

### `no se encontró un fondo del perfil ThinkPad`

**Causa:** faltan los assets del perfil.

**Solución:** instala el perfil y sus fondos antes de ejecutar el helper.

## Changelog

### [Unreleased]
- **feat:** añadir integración idempotente de feh.
