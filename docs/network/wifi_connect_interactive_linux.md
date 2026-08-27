---
title: wifi_connect_interactive_linux.sh
description: Conexión interactiva a redes Wi-Fi
tags:
  - red
---

# wifi_connect_interactive_linux.sh

Conecta a una red WiFi con selección interactiva de red e interfaz. Soporta modo directo con flags `-s` (SSID) y `-b` (BSSID) para uso no interactivo.

- **Ruta:** `scripts/network/wifi_connect_interactive_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_connect_interactive_linux.sh [opciones]
```

______________________________________________________________________

## Opciones

| Opción | Descripción |
|---|---|
| `-i, --iface <iface>` | Interfaz WiFi (por defecto: primera encontrada) |
| `-s, --ssid <ssid>` | Conectar directo al SSID (usa `$WIFI_PASS`) |
| `-b, --bssid <mac>` | Conectar directo al BSSID (usa `$WIFI_PASS`) |
| `-h, --help` | Mostrar ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Descripción |
|---|---|
| `WIFI_PASS` | Contraseña para modo directo con `-s` o `-b` |

______________________________________________________________________

## Ejemplos

```sh
# Modo interactivo
./scripts/network/wifi_connect_interactive_linux.sh

# Modo directo
WIFI_PASS=<WIFI_PASSWORD> ./scripts/network/wifi_connect_interactive_linux.sh -s MiRed

# Con interfaz específica
./scripts/network/wifi_connect_interactive_linux.sh -i wlp2s0
```

Cuando se selecciona una interfaz, el script conserva los perfiles que ya
están activos. Si el mismo SSID ya está conectado en otra interfaz, crea una
copia del perfil para la nueva interfaz en lugar de desconectar la conexión
existente. Esto permite usar simultáneamente la WiFi interna y un adaptador
USB, incluso con el mismo SSID.

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

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

**fix:** conservar conexiones activas y crear perfiles por interfaz para el mismo SSID.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-connect.sh`.
