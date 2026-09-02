---
title: install_eww_linux.sh
description: Compila EWW X11 fijado e instala el dashboard Rafex sin reservar espacio.
tags:
  - instalación
  - eww
  - widgets
---

# install_eww_linux.sh

Compila EWW `v0.6.0` con soporte X11 en el espacio del usuario e instala una
columna de widgets tipo dashboard para la ThinkPad.

- **Ruta:** `scripts/install/install_eww_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, git, cargo, rustc, compilador C, GTK3, `playerctl` y sudo solo para APT.

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

La primera aplicación descarga el código oficial y compila. Después instala el
dashboard `rafex-widgets`, sus helpers y bloques idempotentes de autostart para
i3/Openbox. El dashboard se fija al monitor primario y el daemon solo se inicia
dentro de la sesión gráfica del usuario.

## Uso

```bash
just install-eww --check
just install-eww --plan
just install-eww --apply
just install-eww --status
just eww-widgets --open dashboard
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
just eww-widgets --open dashboard
just eww-widgets --toggle dashboard
just eww-widgets --close dashboard
```

## Fallos conocidos

### `cargo build` falla

**Causa:** faltan dependencias GTK3 o una versión de Rust compatible.

**Solución:** ejecuta `--check`, instala las dependencias con `--apply` y revisa
la salida de Cargo.

### `error[E0282]: type annotations needed for Box<_>` en `time 0.3.34`

**Causa:** el `Cargo.lock` de EWW `v0.6.0` puede resolver `time 0.3.34`, cuya
inferencia falla con versiones modernas de Rust.

**Solución:** el instalador detecta exactamente esa versión y ejecuta
`cargo update -p time@0.3.34 --precise 0.3.36` dentro del árbol local de EWW
antes de compilar. La versión se especifica explícitamente porque EWW también
usa una rama antigua `time 0.1.x`. No se modifica el código fuente de EWW ni
se escribe en el registro global de Cargo.

La ejecución muestra `dependencia time compatible confirmada: 0.3.36`; si la
salida todavía comienza directamente con `Compiling time v0.3.34`, el checkout
de la ThinkPad está desactualizado y debe sincronizarse con
`git pull --ff-only` antes de repetir el comando.

## Changelog

### [Unreleased]
- **feat:** instalar dashboard Rafex derecho con calendario, multimedia, dispositivos y controles.

### v1.0.1 — 2026-09-01

**fix:** actualizar `time 0.3.34` a `0.3.36` cuando el compilador moderno no
puede inferir el tipo de `Box`.

### v1.0.2 — 2026-09-01

**fix:** verificar la actualización exacta del `Cargo.lock` antes de compilar y
evitar la ambigüedad entre `time 0.1.x` y `time 0.3.x`.
