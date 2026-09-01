---
title: install_eww_linux.sh
description: Compila EWW X11 fijado y prepara widgets opcionales sin reserva.
tags:
  - instalación
  - eww
  - widgets
---

# install_eww_linux.sh

Compila EWW `v0.6.0` con soporte X11 en el espacio del usuario.

- **Ruta:** `scripts/install/install_eww_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, git, cargo, rustc, compilador C, GTK3 y sudo solo para APT.

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

La primera aplicación descarga el código oficial y compila. No se activa ningún
daemon ni autostart.

## Uso

```bash
just install-eww --check
just install-eww --plan
just install-eww --apply
just install-eww --status
just eww-widgets --open status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba dependencias y estado. |
| `--plan` | `--dry-run` | Describe la compilación sin modificar. |
| `--apply` | — | Instala dependencias, compila y prepara configuración. |
| `--status` | — | Consulta binario, configuración y daemon. |

## Variables de entorno

No requiere variables. El binario se instala en `~/.local/bin/eww`.

## Ejemplos

```bash
just install-eww --apply
just eww-widgets --open status
just eww-widgets --close status
```

## Fallos conocidos

### `cargo build` falla

**Causa:** faltan dependencias GTK3 o una versión de Rust compatible.

**Solución:** ejecuta `--check`, instala las dependencias con `--apply` y revisa
la salida de Cargo.

## Changelog

### [Unreleased]
- **feat:** añadir EWW X11 opcional con versión fijada.
