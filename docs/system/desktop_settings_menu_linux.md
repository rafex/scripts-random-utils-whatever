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
- **Dependencias:** `bash`, `python3`, `rofi`; las acciones seleccionadas requieren sus aplicaciones correspondientes.

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

Debe ejecutarse dentro de una sesión gráfica Xorg con `rofi` y `python3`
disponibles. Python se usa para escribir entradas JSONL válidas en el historial.

## Uso

```bash
desktop-settings-menu.sh
desktop-settings-menu.sh power
desktop-settings-menu.sh logout
desktop-settings-menu.sh suspend
desktop-settings-menu.sh hibernate
desktop-settings-menu.sh reboot
desktop-settings-menu.sh poweroff
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `all` | — | Abre el centro de control completo. |
| `power` | — | Muestra bloqueo, cerrar sesión, suspensión, hibernación, reinicio y apagado. |
| `logout` | — | Pide confirmación y termina la sesión gráfica actual. |
| `suspend` | — | Pide confirmación y suspende el equipo. |
| `hibernate` | — | Pide confirmación y comprueba `loginctl can-hibernate` antes de hibernar. |
| `reboot` | — | Pide confirmación y reinicia el equipo. |
| `poweroff` | — | Pide confirmación y apaga el equipo. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_STATE_HOME` | `~/.local/state` | Base donde guarda el historial de acciones. |
| `RAFEX_ACTION_SOURCE` | `desktop-settings-menu` | Origen de la acción; Ratmenu lo fija en `ratmenu`. |

Las acciones de energía y sesión se registran en
`${XDG_STATE_HOME:-$HOME/.local/state}/rafex/ratmenu-actions.jsonl`. Cada línea
JSON incluye hora UTC, origen, acción, comando, resultado, código de salida,
salida del comando y, si falla suspensión o hibernación, un diagnóstico de
logind, inhibidores y modos de suspensión. El directorio se crea con permisos
`0700` y el archivo con `0600`.

## Ejemplos

```bash
just desktop-settings-menu
~/.local/bin/desktop-settings-menu.sh power
```

## Protecciones de seguridad

- No requiere `sudo` para abrir el menú.
- Cerrar sesión, suspensión, hibernación, reinicio y apagado piden confirmación
  dentro de Rofi antes de ejecutarse.
- No se usa sudo desde el menú. systemd/logind aplica la política de la sesión.
- Las acciones de sesión y energía registran éxito, cancelación o fallo; las
  notificaciones de fallo incluyen la salida del comando y la ruta del log.
- Si `loginctl can-hibernate` devuelve `no`, hibernar solo muestra una
  notificación y no ejecuta cambios.
- Synaptic se lanza mediante `synaptic-pkexec`, que delega la autenticación al
  agente Polkit de la sesión gráfica.

## Fallos conocidos

### `No se encontró rofi.`

**Causa:** Rofi no está instalado o no está en el `PATH`.

**Solución:** instala el perfil ThinkPad o `rofi` desde Debian.

### `No se pudo terminar la sesión gráfica actual.`

**Causa:** la sesión no tiene un identificador logind utilizable y el window
manager no aceptó la orden de salida.

**Solución:** inicia el menú dentro de la sesión gráfica correcta y comprueba
`echo "$XDG_SESSION_ID"` y `loginctl session-status`.

### `No se pudo suspender el equipo` o `No se pudo hibernar el equipo`

**Causa:** logind o el comando de sistema rechazó la solicitud. El texto exacto
y el código de salida aparecen en la notificación y en el historial JSONL.

**Solución:** revisa el evento más reciente en
`~/.local/state/rafex/ratmenu-actions.jsonl`; los fallos de suspensión e
hibernación incluyen también capacidades, inhibidores y modos del kernel.

## Changelog

### [Unreleased]

- `feat`: extrae el centro de control para compartirlo entre i3 y Openbox.
- `feat`: registra acciones de sesión y energía, y muestra el error concreto si fallan.
