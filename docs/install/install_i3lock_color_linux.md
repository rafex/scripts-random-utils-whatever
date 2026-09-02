---
title: install_i3lock_color_linux.sh
description: Compila y activa i3lock-color conservando el bloqueador oficial de Debian como respaldo.
tags:
  - instalación
  - seguridad
  - bloqueo
---

# install_i3lock_color_linux.sh

Instala `i3lock-color` en `~/.local/bin`, lo integra con el bloqueo manual y
automático de i3/Openbox, y conserva `/usr/bin/i3lock` como respaldo.

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

La instalación compila el tag `2.12.c.5`. Durante `--apply` instala el wrapper
`lock-screen.sh`, sus dependencias de imagen (`imagemagick` y `x11-utils`) y
actualiza de forma idempotente los bloques administrados de i3 y Openbox para
que el atajo y `xss-lock` utilicen `i3lock-color` en modo imagen.

## Uso

```bash
just install-i3lock-color --check
just install-i3lock-color --plan
just install-i3lock-color --apply
just install-i3lock-color --status
just lock-screen --mode image
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba dependencias y binarios. |
| `--plan` | `--dry-run` | Simula la compilación. |
| `--apply` | — | Compila, instala y activa el wrapper en i3/Openbox. |
| `--status` | — | Muestra ambos bloqueadores. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `I3LOCK_COLOR_BIN` | `~/.local/bin/i3lock-color` | Binario usado por el wrapper. |
| `I3LOCK_COLOR_I3_CONFIG` | `~/.config/i3/config` | Configuración i3 que se integra. |
| `I3LOCK_COLOR_OPENBOX_RC` | `~/.config/openbox/rc.xml` | Configuración de teclas de Openbox. |
| `I3LOCK_COLOR_OPENBOX_AUTOSTART` | `~/.config/openbox/autostart` | Autoinicio de `xss-lock` en Openbox. |

## Ejemplos

```bash
just lock-screen --mode solid
just lock-screen --mode image
just lock-screen --mode blur
just lock-screen --status
```

Después de aplicar la configuración, recarga i3 con `Mod4+Shift+r` o
reinicia Openbox con `openbox --reconfigure`. El atajo de i3/Openbox es
`Super+Shift+l`; el bloqueo automático usa `xss-lock` y el modo imagen. El
modo sólido sigue disponible como alternativa explícita.

## Fallos conocidos

### `Duplicate keybinding ... Super+Shift+l`

**Causa:** una instalación anterior podía dejar fuera del bloque administrado
un binding de `Super+Shift+l` que llamaba a `lock-screen.sh --mode solid` (o a
`i3lock`). i3 considera ambas líneas el mismo atajo y rechaza la configuración
completa.

**Solución:** ejecuta `just install-i3lock-color --apply`. El instalador
respalda la configuración y elimina únicamente las variantes antiguas de ese
atajo antes de escribir el binding administrado en modo imagen. Después recarga
i3 con `Mod4+Shift+r` y comprueba `just install-i3lock-color --status`.

### `i3 sigue usando el bloqueador oficial`

**Causa:** se instaló el binario paralelo, pero no se ejecutó de nuevo
`install-i3lock-color --apply` después de actualizar el perfil.

**Solución:** ejecuta `just install-i3lock-color --apply`, recarga i3/Openbox y
comprueba `just install-i3lock-color --status`. El instalador no sobrescribe el
binario oficial.

### `blur requiere ImageMagick`

**Causa:** el modo desenfoque necesita `convert` además de `maim`.

**Solución:** usa `solid` o `image`, o instala ImageMagick desde Debian.

## Changelog

### [Unreleased]
- **feat:** añadir compilación paralela, wrapper y activación idempotente en i3/Openbox.

### v1.2.2 — 2026-09-02

**fix:** evitar que el contenido del bloque administrado se conserve al migrarlo.

- Se descarta el bloque anterior completo antes de insertar su versión canónica.
- Se evita que las reinstalaciones vuelvan a crear bindings duplicados en i3.

### v1.2.1 — 2026-09-02

**fix:** eliminar bindings legacy de `Super+Shift+l` que provocaban duplicados.

- Se limpian variantes antiguas que invocaban el modo sólido o `i3lock`.
- El estado reporta el conflicto antes de volver a aplicar la configuración.
