---
title: configure_tlp_battery_linux.sh
description: Configura límites de carga TLP 75/80 para prolongar la vida útil de la batería ThinkPad.
tags:
  - hardware
  - energia
  - thinkpad
---

# configure_tlp_battery_linux.sh

Configura TLP para comenzar a cargar al 75% y detener la carga al 80%. Los
umbrales se guardan en un drop-in administrado y se aplican inmediatamente.

- **Ruta:** `scripts/hardware/configure_tlp_battery_linux.sh`
- **SO requerido:** Linux (Debian con systemd y TLP)
- **Dependencias:** `bash`, `tlp`, `tlp-stat`, `systemctl`, `sudo`

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Ejecutar como usuario normal con permisos de `sudo`.
- Tener una batería `BAT0` o `BAT1` visible en `/sys/class/power_supply/`.
- TLP debe ser compatible con los umbrales de carga del firmware. La X1 Yoga
  usa la interfaz ThinkPad soportada por TLP.

La documentación de [TLP Battery Care](https://linrunner.de/tlp/settings/battery.html)
distingue entre el cambio temporal realizado por `tlp setcharge` y la
configuración persistente mediante `START_CHARGE_THRESH_BAT0` y
`STOP_CHARGE_THRESH_BAT0`.

## Uso

Desde la raíz del repositorio:

```bash
just configure-tlp-battery --check
just configure-tlp-battery --plan
just configure-tlp-battery --apply
```

Configuración recomendada para viajar, solo cuando necesites la capacidad
completa:

```bash
just configure-tlp-battery --fullcharge
```

`--fullcharge` no cambia el archivo permanente 75/80; TLP restaura los
umbrales configurados al reiniciarse o al volver a aplicar la configuración.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra batería, TLP y configuración sin modificar nada. |
| `--plan` | `--dry-run` | Muestra las acciones previstas sin modificar el sistema. |
| `--apply` | — | Instala TLP si falta, guarda el drop-in y aplica los umbrales. |
| `--fullcharge` | — | Solicita temporalmente carga hasta el 100%; requiere confirmación explícita mediante la opción. |
| `--start <porcentaje>` | — | Umbral de inicio; default `75`. |
| `--stop <porcentaje>` | — | Umbral de parada; default `80`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no utiliza variables de entorno ni archivos `.env`. La ruta
administrada es fija para evitar modificar una configuración de TLP equivocada:

```text
/etc/tlp.d/90-rafex-battery.conf
```

## Ejemplos

### Forma recomendada

```bash
just configure-tlp-battery --apply
```

### Umbrales personalizados

```bash
just configure-tlp-battery --apply --start 70 --stop 85
```

### Diagnóstico

```bash
just configure-tlp-battery --check
tlp-stat -b
```

### Carga completa temporal

```bash
just configure-tlp-battery --fullcharge
```

## Protecciones de seguridad

- `--check` y `--plan` no modifican el sistema ni solicitan `sudo`.
- `--apply` y `--fullcharge` solicitan credenciales únicamente mediante
  `sudo -v`; nunca leen ni guardan la contraseña.
- Se crea un respaldo en `/var/backups/rafex-tlp-battery/` antes de cambiar un
  drop-in existente.
- La configuración se escribe con propietario `root` y permisos `0644`.
- No modifica `fstab`, GRUB, particiones ni opciones `discard` del NVMe.
- No instala `power-profiles-daemon`, `auto-cpufreq` ni
  `laptop-mode-tools`.
- `--fullcharge` es una acción separada y no cambia permanentemente el límite.

## Fallos conocidos

### `no se detectó una batería ThinkPad compatible`

**Causa:** no existe `BAT0`/`BAT1` o el equipo expone un nombre de batería que
requiere una asignación específica de TLP.

**Solución:** ejecuta `ls /sys/class/power_supply/` y `tlp-stat -b`. No fuerces
un nombre distinto sin verificar la correspondencia del firmware.

### `tlp setcharge` no puede aplicar los umbrales

**Causa:** el firmware, el kernel o la versión de TLP no soportan control de
carga en ese equipo, o existe una configuración incompatible.

**Solución:** revisa `tlp-stat -b`, conserva el respaldo y no elimines el
drop-in hasta identificar la causa.

### La batería se queda en 80% aunque se ejecutó `--fullcharge`

**Causa:** `fullcharge` solicita el 100% temporalmente, pero los umbrales
configurados vuelven a aplicarse al reiniciar TLP o el equipo.

**Solución:** ejecuta `--fullcharge` justo antes de viajar y espera a que la
carga termine; no es necesario eliminar la configuración 75/80.

## Changelog

### [Unreleased]

- **feat:** añadir configuración persistente e idempotente de límites TLP 75/80.
- **feat:** añadir acción explícita `--fullcharge` para viajes.
