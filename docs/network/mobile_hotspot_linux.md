---
title: mobile_hotspot_linux.sh
description: Activar y detener el AP móvil Rafex sin sudo
tags:
  - red
  - thinkpad
---

# mobile_hotspot_linux.sh

Activa una red Wi-Fi oculta `internet-movil` usando la conexión WWAN activa de
la ThinkPad como salida a Internet.

- **Ruta:** `scripts/network/mobile_hotspot_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `nmcli`, `iw`, `rfkill`, `ip`, `flock`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

Preparar primero el perfil:

```bash
just install-mobile-hotspot --apply
```

Debe existir exactamente una conexión WWAN activa y una interfaz Wi-Fi con modo
AP. El helper se ejecuta como usuario normal y no utiliza `sudo`.

## Uso

```bash
just mobile-hotspot --status
just mobile-hotspot --start
just mobile-hotspot --stop
```

La clave WPA2 se lee desde `~/.config/rafex/mobile-hotspot.conf` y nunca se
imprime.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra si el perfil existe y está activo. |
| `--start` | — | Prioriza temporalmente WWAN y activa el AP. |
| `--stop` | — | Detiene el AP y restaura la ruta y Wi-Fi previas. |
| `--toggle` | — | Ejecuta `--start` o `--stop` según el estado actual. |
| `--remove` | — | Detiene y elimina solo el perfil administrado. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_STATE_HOME` | Cambia la raíz del estado temporal. |
| `XDG_RUNTIME_DIR` | Cambia la ubicación del bloqueo operativo. |

## Ejemplos

```bash
just mobile-hotspot --start
just mobile-hotspot --status
just mobile-hotspot --stop
just mobile-hotspot --toggle
```

Si se inicia desde SSH sobre la Wi-Fi de la ThinkPad, la sesión puede cortarse
porque esa interfaz se desconecta para convertirse en AP. Se recomienda iniciar
la operación desde la consola local.

## Protecciones de seguridad

- Solo opera el UUID guardado del perfil Rafex.
- Usa `flock` para impedir activaciones concurrentes.
- Guarda métricas WWAN y el UUID de la Wi-Fi previa en estado privado `0600`.
- Prioriza WWAN temporalmente con métrica `25` y restaura los valores originales.
- No toca Ethernet ni modifica rutas con `ip route`.
- No modifica UFW, nftables, Polkit ni la configuración persistente del módem.
- Rechaza tarjetas sin modo AP, Wi-Fi bloqueada o ausencia de WWAN activa.
- No ejecuta comandos recibidos desde el usuario ni imprime secretos.

## Fallos conocidos

### `la ruta por defecto no quedó en WWAN`

**Causa:** NetworkManager no pudo reaplicar la métrica temporal o la conexión
móvil perdió conectividad.
**Solución:** el helper restaura el estado anterior; revisar NetworkManager y
repetir desde la consola local.

### `hay un estado anterior incompleto`

**Causa:** una activación previa terminó antes de completar el flujo.
**Solución:** ejecutar `just mobile-hotspot --stop`; si no se restaura, revisar
el estado mostrado y reconectar manualmente la Wi-Fi desde NetworkManager.

### La sesión SSH se desconecta

**Causa:** la Wi-Fi usada por SSH fue convertida temporalmente en AP.
**Solución:** ejecutar `--start` localmente. La conexión WWAN seguirá siendo el
upstream del AP.

## Changelog

### [Unreleased]

**feat:** activar AP móvil oculto con restauración transaccional de red.
