---
title: install_i3_gaps_linux.sh
description: Configura los gaps nativos de i3 en Debian sin compilar el proyecto i3-gaps archivado.
tags:
  - instalación
  - i3
  - referencia
---

# install_i3_gaps_linux.sh

Instala `i3-wm` desde Debian si hace falta y configura los gaps integrados en
i3 4.22 o posterior. Debian Forky ofrece una versión compatible; no se usa el
antiguo fork externo `i3-gaps`.

- **Ruta:** `scripts/install/install_i3_gaps_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `sudo`, `apt-get`, `i3`, `i3-msg`, `awk`, `cp`, `grep`, `sort`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

El usuario debe tener permisos de `sudo` para `--apply`. Se recomienda
instalar primero el perfil:

```bash
just install-profile thinkpad-x1-yoga-1st
```

La versión mínima de i3 es 4.22 porque los gaps forman parte de i3 desde esa
versión. La configuración objetivo por defecto es `~/.config/i3/config`.

## Uso

```bash
just install-i3-gaps --check
just install-i3-gaps --plan
just install-i3-gaps --apply
```

La configuración aplicada es:

```text
gaps inner 2px
gaps outer 3px
smart_gaps on
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra versión, conflictos y estado sin cambiar nada. |
| `--plan` | `--dry-run` | Muestra la instalación y modificación previstas. |
| `--apply` | — | Instala/verifica i3, modifica la configuración y valida. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `I3_GAPS_CONFIG` | Ruta alternativa de configuración de i3. |
| `XDG_CONFIG_HOME` | Base de la ruta predeterminada de configuración. |

No se leen archivos `.env`. La variable `I3_GAPS_CONFIG` tiene prioridad sobre
`XDG_CONFIG_HOME` para la ruta de configuración.

## Ejemplos

Auditar sin privilegios ni cambios:

```bash
just install-i3-gaps --check
```

Revisar el plan y aplicar desde una sesión local:

```bash
just install-i3-gaps --plan
just install-i3-gaps --apply
```

Validar una configuración alternativa:

```bash
I3_GAPS_CONFIG="$HOME/.config/i3/config-test" \
  bash scripts/install/install_i3_gaps_linux.sh --plan
```

Desde SSH, la validación se ejecuta, pero la recarga se omite. Dentro de i3
debe ejecutarse:

```bash
i3-msg reload
```

## Protecciones de seguridad

- `--check` y `--plan` no solicitan `sudo` ni modifican el sistema.
- `--apply` usa `sudo -v` y solo instala `i3-wm` desde las fuentes APT existentes.
- Se crea un respaldo fechado de `~/.config/i3/config` antes de modificarlo.
- Se rechazan directivas `gaps` o `smart_gaps` fuera del bloque administrado;
  no se sobrescriben silenciosamente.
- Se valida la configuración con `i3 -C` antes de recargarla.
- No se tocan Xorg, Mesa, DRI, pantallas, particiones, GRUB ni `fstab`.

## Fallos conocidos

### `hay directivas gaps fuera del bloque administrado`

**Causa:** Ya existe una configuración manual de gaps en el archivo.

**Solución:** Revisa las directivas duplicadas, conserva una sola política y
vuelve a ejecutar `--apply`.

### `i3 debe ser versión 4.22 o posterior`

**Causa:** El sistema tiene un i3 antiguo o el binario no está disponible.

**Solución:** Actualiza `i3-wm` desde Debian y vuelve a ejecutar el instalador.
No compiles el fork archivado de `i3-gaps`.

### La pantalla no cambia inmediatamente

**Causa:** El script fue aplicado desde SSH y no existe `DISPLAY` en esa sesión.

**Solución:** Ejecuta `i3-msg reload` dentro de la sesión gráfica local.

## Changelog

### [Unreleased]

- **feat:** Añadir instalación y configuración de gaps nativos de i3.
- **fix:** Reducir los gaps predeterminados a 2 píxeles internos y 3 externos
  para mejorar el aprovechamiento de la pantalla de la ThinkPad.

### v1.0.0 — 2026-08-29

**feat:** Preferir la implementación integrada de i3 sobre el fork archivado.
