---
title: flight_mode_toggle_linux.sh
description: Alternar Wi-Fi, WWAN y Bluetooth como modo avión
tags:
  - red
  - bluetooth
---

# flight_mode_toggle_linux.sh

Activa o desactiva los radios de red administrados por NetworkManager y
Bluetooth desde una sesión i3.

- **Ruta:** `scripts/network/flight_mode_toggle_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `nmcli`, `bluetoothctl` opcional, `notify-send`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

NetworkManager debe estar activo. WWAN y Bluetooth se omiten si no existen.

## Uso

```sh
~/.local/bin/flight-mode-toggle.sh toggle
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `toggle` | — | Activa modo avión si algún radio está encendido. |
| `on` | — | Activa Wi-Fi, WWAN y Bluetooth. |
| `off` | — | Desactiva Wi-Fi, WWAN y Bluetooth. |

## Variables de entorno

Este script no requiere variables de entorno.

## Ejemplos

```sh
~/.local/bin/flight-mode-toggle.sh toggle
~/.local/bin/flight-mode-toggle.sh off
```

## Fallos conocidos

### `bluetoothctl power` falla

**Causa:** Bluetooth no está disponible o está bloqueado por hardware.
**Solución:** comprobar `bluetoothctl show` y el interruptor físico de la laptop.

## Changelog

### [Unreleased]

**feat:** añadir modo avión controlable desde i3.
