---
title: wifi_toggle_internal_linux.sh
description: Alternancia de radio Wi-Fi
tags:
  - red
---

# wifi_toggle_internal_linux.sh

Activa o desactiva la gestión de la interfaz WiFi interna (`wlp2s0`) con NetworkManager y muestra una notificación.

- **Ruta:** `scripts/network/wifi_toggle_internal_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`, `notify-send`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_toggle_internal_linux.sh
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `WIFI_TOGGLE_IFACE` | `wlp2s0` | Interfaz WiFi a controlar |

______________________________________________________________________

## Ejemplos

```sh
./scripts/network/wifi_toggle_internal_linux.sh

WIFI_TOGGLE_IFACE=wlan0 ./scripts/network/wifi_toggle_internal_linux.sh
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

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi.sh`.
