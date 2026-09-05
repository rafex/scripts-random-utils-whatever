---
title: install_i3_bar_profiles_linux.sh
description: Prepara los perfiles de barra i3bar, tint2 y Polybar para la ThinkPad.
tags:
  - instalación
  - i3
  - barras
---

# install_i3_bar_profiles_linux.sh

Instala las plantillas y helpers de los tres perfiles de barra de i3. Migra
el bloque `bar` administrado a una única inclusión y deja `i3bar` como
predeterminado.

- **Ruta:** `scripts/install/install_i3_bar_profiles_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `awk`, `cmp`, `dpkg-query`, `find`, `grep`, `install`, `mktemp`, `mv`.

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

Debe existir el perfil `dotfiles/profiles/thinkpad-x1-yoga-1st` y una
configuración de i3 en `~/.config/i3/config`. El instalador no requiere sudo:
Tint2 y Polybar se instalan, si hiciera falta, cuando se selecciona el perfil
mediante [`i3_bar_profile_linux.sh`](../system/i3_bar_profile_linux.md).

## Uso

```bash
just install-i3-bar-profiles --check
just install-i3-bar-profiles --plan
just install-i3-bar-profiles --apply
just install-i3-bar-profiles --status
```

Después de aplicar, selecciona la barra desde
[`just i3-bar`](../system/i3_bar_profile_linux.md).

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida fuentes, configuración i3 y dependencias sin escribir. |
| `--plan` | `--dry-run` | Muestra los archivos que se prepararían sin modificar el usuario. |
| `--apply` | — | Instala plantillas y helpers, migra el bloque administrado y crea el perfil i3bar. |
| `--status` | — | Muestra el estado de fuentes, destinos y paquetes. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio de configuración del usuario. |

No se usan archivos `.env`. La selección de barra se guarda en
`$XDG_CONFIG_HOME/rafex/i3-bar-profile`.

## Ejemplos

```bash
# Flujo recomendado.
just install-i3-bar-profiles --check
just install-i3-bar-profiles --plan
just install-i3-bar-profiles --apply
just i3-bar --status

# Validar sin tocar la configuración.
just install-i3-bar-profiles --check
```

## Protecciones de seguridad

- Solo migra un bloque `bar` que conserva las firmas de la configuración Rafex actual.
- Rechaza bloques manuales o inclusiones duplicadas en lugar de sobrescribirlos.
- Usa archivos temporales y respaldos fechados para los destinos modificados.
- No modifica Conky, EWW, Picom, Openbox ni el contenido de `i3status`.
- No inicia procesos externos ni reinicia la sesión automáticamente.

## Fallos conocidos

### `se detectó un bloque bar manual; no se sobrescribe`

**Causa:** i3 contiene una barra que no coincide con el bloque administrado por Rafex.

**Solución:** revisa el bloque manual, respáldalo y decide su migración antes de repetir.

### `falta i3/config`

**Causa:** el perfil todavía no se instaló o la sesión usa otra ruta.

**Solución:** instala primero el perfil ThinkPad o define `XDG_CONFIG_HOME` correctamente.

## Changelog

### [Unreleased]

- **feat:** preparar tres perfiles de barra i3 con migración atómica y fallback i3bar.
