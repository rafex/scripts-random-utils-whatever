---
title: wifi_reset_linux.sh
description: Reinicio del controlador Wi-Fi
tags:
  - red
---

# wifi_reset_linux.sh

Recarga el driver WiFi `wl` (Broadcom) y reinicia la radio WiFi con `nmcli`.

- **Ruta:** `scripts/network/wifi_reset_linux.sh`
- **SO requerido:** Linux (con driver Broadcom wl)
- **Dependencias:** `sudo`, `modprobe`, `nmcli`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_reset_linux.sh
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

## Variables de entorno

No se requieren variables adicionales fuera de las indicadas en esta documentación.

## Ejemplos

Consulta los ejemplos de uso incluidos en las secciones anteriores y ejecuta primero un modo de diagnóstico cuando exista.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-reset.sh`.
