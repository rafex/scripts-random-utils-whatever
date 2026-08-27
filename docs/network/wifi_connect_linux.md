---
title: wifi_connect_linux.sh
description: Conexión a redes Wi-Fi mediante NetworkManager
tags:
  - red
---

# wifi_connect_linux.sh

Conecta a una red WiFi usando NetworkManager (`nmcli`). Solicita la contraseña de forma interactiva si no se pasa por argumento.

- **Ruta:** `scripts/network/wifi_connect_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con NetworkManager)
- **Dependencias:** `nmcli`, `NetworkManager`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_connect_linux.sh <SSID> [password]
```

| Argumento | Descripción |
|---|---|
| `SSID` | Nombre de la red WiFi (obligatorio) |
| `password` | Contraseña (opcional; si se omite se pide interactivamente) |

______________________________________________________________________

## Variables de entorno

| Variable | Descripción |
|---|---|
| `WIFI_PASSWORD` | Contraseña de la red WiFi (alternativa al argumento o prompt) |

______________________________________________________________________

## Ejemplos

```sh
# Con contraseña por argumento
./scripts/network/wifi_connect_linux.sh MiRed <WIFI_PASSWORD>

# Pedirá la contraseña interactivamente
./scripts/network/wifi_connect_linux.sh MiRed

# Con contraseña por variable de entorno
WIFI_PASSWORD=<WIFI_PASSWORD> ./scripts/network/wifi_connect_linux.sh MiRed

# Red con espacios en el nombre
./scripts/network/wifi_connect_linux.sh "Mi WiFi" contraseña
```

______________________________________________________________________

## Validaciones previas

Antes de conectar el script verifica:

1. `nmcli` está instalado
1. `NetworkManager` está corriendo (`systemctl is-active`)
1. El WiFi no está bloqueado a nivel radio — si lo está, lo activa automáticamente

______________________________________________________________________

## Fallos conocidos

### `Error: No network with SSID 'X' found.`

La red no está en rango. Escanear primero:

```sh
./scripts/network/wifi_scan_linux.sh
```

### `Error: Connection activation failed: (7) Secrets were required but not provided.`

Contraseña incorrecta o faltante. Reintentar con la contraseña correcta.

### `Error: nmcli no está instalado`

Instalar NetworkManager:

```sh
sudo apt install network-manager
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
