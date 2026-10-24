---
title: thinkpad_hotspot_linux.sh
description: Activar y detener el hotspot THINKPAD_RAFEX de la ThinkPad
tags:
  - red
  - thinkpad
---

# thinkpad_hotspot_linux.sh

Activa y detiene el AP visible `THINKPAD_RAFEX`, compartiendo la conexión WWAN
activa de la ThinkPad mediante NetworkManager.

- **Ruta:** `scripts/network/thinkpad_hotspot_linux.sh`
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

Preparar el perfil y clave una vez:

```bash
just install-thinkpad-hotspot --set-key
just install-thinkpad-hotspot --apply
```

Antes de iniciar debe haber exactamente una conexión WWAN activa y una interfaz
Wi-Fi compatible con modo AP. El controlador no conecta ni desconecta el módem.
Se ejecuta como usuario normal y no usa `sudo`.

## Uso

```bash
just thinkpad-hotspot --status
just thinkpad-hotspot --start
just thinkpad-hotspot --stop
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra el estado del perfil y la ruta activa. |
| `--start` | — | Prioriza temporalmente WWAN y activa el AP. |
| `--stop` | — | Detiene el AP y restaura la ruta y Wi-Fi previas. |
| `--toggle` | — | Inicia o detiene según el estado actual. |
| `--remove` | — | Detiene y elimina solo el perfil administrado. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_STATE_HOME` | Cambia la raíz del estado temporal de la operación. |
| `XDG_RUNTIME_DIR` | Cambia la ubicación del bloqueo operativo. |

## Ejemplos

```bash
just thinkpad-hotspot --start
just thinkpad-hotspot --status
just thinkpad-hotspot --stop
just thinkpad-hotspot --toggle
```

Al activar el AP desde una sesión SSH sobre la Wi-Fi de la ThinkPad, la sesión
puede cortarse porque esa interfaz pasa a modo punto de acceso. Iniciar desde
la consola local evita esa desconexión.

## Protecciones de seguridad

- Solo opera el UUID del perfil independiente administrado por este instalador.
- Usa `flock` para impedir activaciones concurrentes y estado privado `0600` para recuperación.
- Prioriza temporalmente la WWAN y restaura sus métricas originales al detener.
- No conecta/desconecta WWAN, toca Ethernet, modifica rutas manuales ni cambia firewall.
- Rechaza Wi-Fi bloqueada, tarjetas sin modo AP o ausencia de una WWAN activa.
- No muestra ni transmite la clave WPA2.

## Fallos conocidos

### `se requiere exactamente una conexión WWAN activa`

**Causa:** OXXO Cel LTE no está conectado o hay más de una conexión móvil activa.
**Solución:** conectar el perfil OXXO Cel desde NetworkManager y repetir `--start`.

### `la ruta por defecto no quedó en WWAN`

**Causa:** NetworkManager no pudo aplicar la métrica temporal o la conexión móvil perdió conectividad.
**Solución:** el controlador restaura el estado anterior; revisar NetworkManager y repetir desde la consola local.

### `hay un estado anterior incompleto`

**Causa:** una activación previa terminó antes de completar el flujo.
**Solución:** ejecutar `just thinkpad-hotspot --stop` para intentar restaurar el estado guardado.

### La sesión SSH se desconecta

**Causa:** la interfaz Wi-Fi usada por SSH se convierte temporalmente en AP.
**Solución:** iniciar el hotspot desde la consola local; la conexión WWAN continúa como salida a Internet.

## Changelog

### [Unreleased]

- **feat:** controlar el AP visible `THINKPAD_RAFEX` con restauración de red.
