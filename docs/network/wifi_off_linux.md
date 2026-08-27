---
title: wifi_off_linux.sh
description: Desactivación de Wi-Fi
tags:
  - red
---

# wifi_off_linux.sh

Apaga interfaces WiFi (interna, USB o ambas) en Linux usando NetworkManager o rfkill.

- **Ruta:** `scripts/network/wifi_off_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con NetworkManager)
- **Dependencias:** `nmcli`, `rfkill` (opcional)

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_off_linux.sh [internal|usb|all|--help]
```

| Modo | Descripción |
|---|---|
| `internal` | Apaga solo la interfaz WiFi interna (`wlp2s0`) |
| `usb` | Apaga solo la interfaz WiFi USB (`wlxa047d76360c5`) |
| `all` | Apaga ambas interfaces (default) |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `WIFI_OFF_INTERNAL` | `wlp2s0` | Nombre de la interfaz WiFi interna |
| `WIFI_OFF_USB` | `wlxa047d76360c5` | Nombre de la interfaz WiFi USB |
| `WIFI_OFF_RFKILL` | `0` | Usar `rfkill block wifi` en lugar de nmcli (`1` = sí) |

______________________________________________________________________

## Ejemplos

```sh
# Apagar solo la WiFi interna
./scripts/network/wifi_off_linux.sh internal

# Apagar solo la USB
./scripts/network/wifi_off_linux.sh usb

# Apagar ambas
./scripts/network/wifi_off_linux.sh all

# Usar rfkill en lugar de nmcli
WIFI_OFF_RFKILL=1 ./scripts/network/wifi_off_linux.sh all

# Con interfaz personalizada
WIFI_OFF_INTERNAL=wlan0 ./scripts/network/wifi_off_linux.sh internal
```

______________________________________________________________________

## Cómo funciona

1. Si se usa el modo `nmcli` (default):
   - Desconecta la interfaz con `nmcli device disconnect`
   - La pone en modo no gestionado con `nmcli device set <iface> managed false`
1. Si se usa `rfkill` (`WIFI_OFF_RFKILL=1`):
   - Ejecuta `rfkill block wifi` que bloquea todas las radios WiFi a nivel kernel

______________________________________________________________________

## Fallos conocidos

### `Error: Device 'wlxa047d76360c5' not found`

La interfaz no coincide. Averiguar con:

```sh
nmcli device status | grep wifi
```

Y usar la variable de entorno:

```sh
WIFI_OFF_USB=wlxNUEVOID ./scripts/network/wifi_off_linux.sh usb
```

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial.
