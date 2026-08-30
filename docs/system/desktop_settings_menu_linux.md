---
title: desktop_settings_menu_linux.sh
description: Centro de control Rofi común para sesiones i3 y Openbox en Xorg.
tags:
  - sistema
  - rofi
  - openbox
---

# desktop_settings_menu_linux.sh

Abre un centro de control gráfico común para las sesiones i3 y Openbox.

- **Ruta:** `scripts/system/desktop_settings_menu_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `rofi`; las acciones seleccionadas requieren sus aplicaciones correspondientes.

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

Debe ejecutarse dentro de una sesión gráfica Xorg con `rofi` disponible.

## Uso

```bash
desktop-settings-menu.sh
desktop-settings-menu.sh power
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `all` | — | Abre el centro de control completo. |
| `power` | — | Muestra solo bloqueo, suspensión, reinicio y apagado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No usa variables de entorno propias. Respeta `$HOME` para localizar los
helpers instalados.

## Ejemplos

```bash
just desktop-settings-menu
~/.local/bin/desktop-settings-menu.sh power
```

## Protecciones de seguridad

- No requiere `sudo` para abrir el menú.
- Las acciones de suspensión, reinicio y apagado piden confirmación dentro de
  Rofi antes de ejecutarse.
- Synaptic se lanza mediante `synaptic-pkexec`, que delega la autenticación al
  agente Polkit de la sesión gráfica.

## Fallos conocidos

### `No se encontró rofi.`

**Causa:** Rofi no está instalado o no está en el `PATH`.

**Solución:** instala el perfil ThinkPad o `rofi` desde Debian.

## Changelog

### [Unreleased]

- `feat`: extrae el centro de control para compartirlo entre i3 y Openbox.
