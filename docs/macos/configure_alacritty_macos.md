---
title: configure_alacritty_macos.sh
description: Instala una configuración oscura y respaldable de Alacritty en macOS.
tags:
  - macos
  - alacritty
---

# configure_alacritty_macos.sh

Instala la configuración macOS de Alacritty con una paleta oscura, fuente Hack,
decoraciones nativas, transparencia moderada y shell de inicio detectado.

- **Ruta:** `scripts/macos/configure_alacritty_macos.sh`
- **SO requerido:** macOS
- **Dependencias:** bash, `awk`, `cmp`, `cp`, `grep`, `mktemp`; Alacritty es opcional

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

El script solo configura `~/.config/alacritty/alacritty.toml`. No instala la
aplicación ni modifica Homebrew o Gatekeeper. Si Alacritty ya está instalado,
se mostrará su versión en `--status`.

La plantilla utiliza la sintaxis TOML actual de Alacritty, incluyendo
`[general]`, `[terminal.shell]` y opciones macOS de `window`. [Documentación
oficial de Alacritty](https://alacritty.org/config-alacritty.html)

## Uso

```bash
just configure-alacritty-macos --check
just configure-alacritty-macos --plan
just configure-alacritty-macos --apply
just configure-alacritty-macos --status
just configure-alacritty-macos --rollback
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida la plantilla y el entorno sin escribir. |
| `--plan` | `--dry-run` | Muestra las acciones previstas. |
| `--status` | — | Muestra la configuración y el runtime detectado. |
| `--apply` | — | Crea un respaldo e instala la configuración atómicamente. |
| `--rollback` | — | Restaura el respaldo administrado más reciente. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio base de la configuración de Alacritty. |
| `SHELL` | `/bin/zsh` | Shell de inicio; se usa solo si apunta a un ejecutable. |

Los argumentos no tienen prioridad sobre variables porque el script no acepta
opciones equivalentes para estas rutas; el destino siempre es el archivo de
configuración del usuario.

## Ejemplos

### Forma explícita recomendada

```bash
just configure-alacritty-macos --apply
```

### Revisar antes de aplicar

```bash
just configure-alacritty-macos --check
just configure-alacritty-macos --plan
```

### Volver al archivo anterior

```bash
just configure-alacritty-macos --rollback
```

## Protecciones de seguridad

- Rechaza ejecución fuera de macOS y como root.
- No instala ni actualiza Alacritty, Homebrew ni Gatekeeper.
- Respaldará el archivo actual antes de reemplazarlo.
- Usa reemplazo atómico y permisos `0600`.
- Conserva un marcador de estado ausente para poder revertir una primera instalación.
- No toca perfiles Linux, temas ThinkPad, shells, SSH ni credenciales.

## Fallos conocidos

### `Alacritty no está instalado`

**Causa:** la aplicación no está presente; en este Mac Homebrew la reporta como
deshabilitada por Gatekeeper.

**Solución:** la configuración queda preparada. Instala Alacritty por un medio
que autorices y luego ejecuta `--status`; este script no realiza esa instalación.

### `la configuración no se aplica hasta abrir una nueva ventana`

**Causa:** algunas opciones de ventana requieren reiniciar la ventana o la
aplicación.

**Solución:** cierra las ventanas de Alacritty y abre una nueva después de
`--apply`.

## Changelog

### [Unreleased]
- **feat:** añadir configuración macOS oscura con respaldo y rollback.

### v1.0.0 — 2026-09-05

**feat:** versión inicial.
