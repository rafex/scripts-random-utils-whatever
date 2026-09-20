---
title: install_i3_workspace_usage_linux.sh
description: Instala el registrador privado de workspaces i3 para la ThinkPad.
tags:
  - instalación
  - i3
  - thinkpad
---

# install_i3_workspace_usage_linux.sh

Instala el helper y la unidad `systemd --user` que registra uso agregado de
workspaces en i3. Está limitado al perfil `thinkpad-x1-yoga-1st` y no usa sudo.

- **Ruta:** `scripts/install/install_i3_workspace_usage_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `python3`, `systemctl`, perfil ThinkPad; `i3-msg` al iniciar el daemon.

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

Primero publica el perfil ThinkPad actualizado para que i3 tenga el autostart
administrado. El instalador se ejecuta como usuario normal.

## Uso

```bash
just install-i3-workspace-usage --plan
just install-i3-workspace-usage --apply
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba helper, unidad y autostart de i3. |
| `--plan` | — | Muestra los archivos que instalaría, sin modificarlos. |
| `--apply` | — | Instala helper y unidad, y recarga systemd de usuario. |
| `--status` | — | Muestra instalación y estado de la unidad. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Destino de la unidad de usuario y de `i3/config`. |
| `HOME` | usuario actual | Destino del helper en `~/.local/bin`. |

La prioridad es `XDG_CONFIG_HOME` sobre su valor predeterminado; el instalador
no usa `.env` ni acepta rutas arbitrarias como argumentos.

## Ejemplos

```bash
# Forma explícita/recomendada.
just install-profile thinkpad-x1-yoga-1st
just install-i3-workspace-usage --apply

# Verificar antes de instalar.
just install-i3-workspace-usage --plan

# Con configuración XDG aislada para pruebas.
XDG_CONFIG_HOME="$HOME/.config" just install-i3-workspace-usage --check
```

## Protecciones de seguridad

- Rechaza root, sistemas que no sean Linux y destinos no administrados.
- Solo instala archivos desde este checkout con permisos ejecutable `0700` para
  el helper y `0644` para la unidad.
- No habilita la unidad globalmente ni modifica la configuración i3 existente.
- No usa sudo, red ni datos de títulos de ventanas.

## Fallos conocidos

### `autostart i3 ausente`

**Causa:** la configuración local i3 pertenece a una versión anterior del
perfil ThinkPad.
**Solución:** ejecuta `just install-profile thinkpad-x1-yoga-1st` y reinicia i3.

### La unidad permanece `inactive`

**Causa:** todavía no se ha abierto una nueva sesión i3 con el helper instalado.
**Solución:** reinicia i3 o vuelve a iniciar sesión; el autostart importará el
socket y arrancará la unidad.

## Changelog

### [Unreleased]

- **feat:** instalar el registrador privado de workspaces para i3/ThinkPad.
