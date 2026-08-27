---
title: wifi_toggle_interface_linux.sh
description: Alternancia entre interfaces Wi-Fi
tags:
  - red
---

# wifi_toggle_interface_linux.sh

Alterna entre WiFi interno y USB de forma interactiva. Útil en laptops con doble interfaz WiFi (ej. Broadcom interna + adaptador USB externo).

- **Ruta:** `scripts/network/wifi_toggle_interface_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`

______________________________________________________________________

## Uso

```sh
./scripts/network/wifi_toggle_interface_linux.sh
```

______________________________________________________________________

## Menú interactivo

```
1) Apagar WiFi interno, encender USB
2) Apagar WiFi USB, encender interno
3) Solo apagar WiFi interno
4) Solo encender WiFi interno
5) Mostrar estado
```

Detecta automáticamente qué interfaz es interna (drivers: `wl`, `b43`, `brcmfmac`, `iwlwifi`) y cuál es USB.

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

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-toggle.sh`.
