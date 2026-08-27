---
title: wifi_toggle_linux.sh
description: Alternar el radio Wi-Fi con NetworkManager
tags:
  - red
---

# wifi_toggle_linux.sh

Alterna el radio Wi‑Fi completo mediante NetworkManager, sin fijar el nombre de
la interfaz y sin usar `sudo`. Después confirma el estado real con una
notificación OSD y un icono de red activo o desactivado.

- **Ruta:** `scripts/network/wifi_toggle_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `nmcli`, `notify-send`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

El usuario debe tener permisos polkit/netdev para controlar NetworkManager.

## Uso

```sh
~/.local/bin/wifi-toggle.sh toggle
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `toggle` | — | Alterna el radio Wi-Fi. |
| `on` | — | Activa Wi-Fi. |
| `off` | — | Desactiva Wi-Fi. |

## Variables de entorno

Este script no requiere variables de entorno.

## Ejemplos

```sh
~/.local/bin/wifi-toggle.sh toggle
~/.local/bin/wifi-toggle.sh off
```

## Fallos conocidos

### `Insufficient privileges`

**Causa:** polkit no permite a la sesión controlar NetworkManager.
**Solución:** verificar el grupo `netdev` y la regla polkit de la migración.

### No aparece la notificación

**Causa:** no hay un daemon de notificaciones activo en la sesión i3.
**Solución:** comprobar `dunst` con `pgrep dunst` y recargar i3; el cambio de
Wi‑Fi puede confirmarse con `nmcli radio wifi`.

## Changelog

### [Unreleased]

**feat:** alternar Wi-Fi sin depender de `wlp2s0` u otra interfaz fija.
