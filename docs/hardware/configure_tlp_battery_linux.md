---
title: configure_tlp_battery_linux.sh
description: Configura límites de carga TLP 80/85 para prolongar la vida útil de la batería ThinkPad.
tags:
  - hardware
  - energia
  - thinkpad
---

# configure_tlp_battery_linux.sh

Configura TLP para comenzar a cargar al 80% y detener la carga al 85%. Los
umbrales se guardan en un drop-in administrado y se aplican inmediatamente.
Para la ThinkPad X1 Yoga el único dispositivo gestionado es `BAT0`; si el
sistema expone otra batería, se informa y se omite para no cambiar hardware
fuera de este perfil.

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
- Tener `BAT0` visible en `/sys/class/power_supply/`.
- TLP debe ser compatible con los umbrales de carga del firmware. La X1 Yoga
  usa la interfaz ThinkPad soportada por TLP.

La documentación de [TLP Battery Care](https://linrunner.de/tlp/settings/battery.html)
distingue entre el cambio temporal realizado por `tlp setcharge` y la
configuración persistente mediante `START_CHARGE_THRESH_BAT0` y
`STOP_CHARGE_THRESH_BAT0`.

El diagnóstico añade `/usr/local/sbin`, `/usr/sbin` y `/sbin` al `PATH` del
propio script. Esto permite localizar `tlp` y `tlp-stat` cuando se ejecuta
desde una shell SSH que no es de login; no cambia el `PATH` persistente del
usuario.

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

`--fullcharge` no cambia el archivo permanente 80/85; TLP restaura los
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

El contenido administrado por defecto es exactamente:

```text
# >>> rafex TLP battery managed >>>

# Umbrales conservadores para reducir ciclos y mantener la batería entre 80-85%.

START_CHARGE_THRESH_BAT0=80
STOP_CHARGE_THRESH_BAT0=85
```

La fuente versionada del perfil se encuentra en
`dotfiles/profiles/thinkpad-x1-yoga-1st/config/tlp/90-rafex-battery.conf`.

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

### `no se detectó la batería BAT0 administrada por este perfil`

**Causa:** no existe `BAT0` o el equipo expone únicamente una batería con otro
nombre.

**Solución:** ejecuta `ls /sys/class/power_supply/` y `tlp-stat -b`. No fuerces
un nombre distinto sin verificar la correspondencia del firmware.

### `tlp setcharge` no puede aplicar los umbrales

**Causa:** el firmware, el kernel o la versión de TLP no soportan control de
carga en ese equipo, o existe una configuración incompatible.

**Solución:** revisa `tlp-stat -b`, conserva el respaldo y no elimines el
drop-in hasta identificar la causa.

### La batería se queda en 85% aunque se ejecutó `--fullcharge`

**Causa:** `fullcharge` solicita el 100% temporalmente, pero los umbrales
configurados vuelven a aplicarse al reiniciar TLP o el equipo.

**Solución:** ejecuta `--fullcharge` justo antes de viajar y espera a que la
carga termine; no es necesario eliminar la configuración 80/85.

## Changelog

### [Unreleased]

- **feat:** añadir configuración persistente e idempotente de límites TLP 80/85.
- **feat:** añadir acción explícita `--fullcharge` para viajes.
- **fix:** detectar `tlp` correctamente desde shells SSH sin `/usr/sbin` en
  `PATH`.
- **fix:** administrar exclusivamente `BAT0` y versionar el drop-in exacto del
  perfil ThinkPad.
