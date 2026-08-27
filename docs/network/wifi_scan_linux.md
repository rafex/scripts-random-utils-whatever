---
title: wifi_scan_linux.sh
description: Escaneo de redes Wi-Fi
tags:
  - red
---

# wifi_scan_linux.sh

Escanea y muestra redes WiFi disponibles usando NetworkManager.

- **Ruta:** `scripts/network/wifi_scan_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con NetworkManager)
- **Dependencias:** `nmcli`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_scan_linux.sh
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `WIFI_SCAN_MAX` | `50` | Máximo de redes a mostrar en la salida |

______________________________________________________________________

## Ejemplos

```sh
# Escaneo normal
./scripts/network/wifi_scan_linux.sh

# Mostrar solo 10 redes
WIFI_SCAN_MAX=10 ./scripts/network/wifi_scan_linux.sh
```

______________________________________________________________________

## Salida

```
  → Escaneando redes WiFi...

SSID              SEGURIDAD  SEÑAL%  BARRAS  CANAL
MiRed             WPA2       85      ▂▄▆█    6
CasaVecina        WPA2       45      ▂▄__     11
WiFi-Abierto      --         30      ▂___     1

  ✓ Total: 12 redes detectadas.
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

**feat:** versión inicial.
