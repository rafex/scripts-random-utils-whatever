---
title: conky_status_linux.sh
description: Genera estados no sensibles para el panel Conky de la ThinkPad.
tags:
  - sistema
  - conky
  - monitorización
---

# conky_status_linux.sh

Genera las líneas dinámicas que utiliza Conky para mostrar red, energía,
temperaturas, audio, laboratorio y servicios de seguridad sin privilegios.

- **Ruta:** `scripts/system/conky_status_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `awk`; opcionales `nmcli`, `upower`, `sensors`, `wpctl`, `virsh`, `podman` y `systemctl`

---

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

Puede ejecutarse como usuario normal, con o sin X11. Si una herramienta o un
sensor no existe, devuelve `N/D` y conserva el resto del panel.

## Uso

```bash
just conky-status
~/.local/bin/conky-status.sh
```

El instalador de Conky copia este script a `~/.local/bin/conky-status.sh`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--section all` | `--all` | Imprime todas las secciones. Es el valor predeterminado. |
| `--network` | — | Estado Wi-Fi/WWAN, calidad y prioridad, sin SSID ni IP. |
| `--power` | — | Batería, fuente, consumo y límites TLP. |
| `--temperature` | — | CPU y NVMe; descarta lecturas imposibles. |
| `--audio` | — | Volumen y mute de la salida predeterminada. |
| `--lab` | — | KVM, VMs activas, Podman y runtimes disponibles. |
| `--security` | — | Estado resumido de UFW, Fail2ban, AppArmor, auditd, USBGuard y ClamAV. |
| `--check` | — | Comprueba herramientas sin abrir ni modificar una sesión gráfica. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `LC_ALL` | `C` | Se fuerza internamente para interpretar salidas de herramientas de forma estable. |

No usa `.env`, no almacena datos y no acepta credenciales.

## Ejemplos

### Todas las secciones

```bash
just conky-status
```

### Diagnosticar red y sensores

```bash
just conky-status --network
just conky-status --temperature
```

### Verificar dependencias

```bash
just conky-status --check
```

## Protecciones de seguridad

- No ejecuta `sudo`, escaneos, comandos AT ni acciones de red.
- No imprime SSID, BSSID, IP, IMEI, IMSI, APN, nombres de archivo ni secretos.
- No ejecuta `ufw` con privilegios; si no puede consultar su estado muestra `N/D`.
- No muestra temperaturas fuera de `-50°C` a `150°C`; las lecturas inválidas
  del NVMe se convierten en `N/D`.
- El resultado es informativo y no sustituye `just audit-thinkpad --status`.

## Fallos conocidos

### `CPU: N/D | NVMe: N/D`

**Causa:** `lm-sensors` no está instalado, no cargó un sensor compatible o el
hardware no expone esa lectura.

**Solución:** ejecuta `sensors`; el panel continuará funcionando sin inventar
temperaturas.

### `VMs activas: N/D`

**Causa:** `virsh` no está instalado o la conexión `qemu:///session` no está
disponible para el usuario.

**Solución:** comprueba `virsh -c qemu:///session list --all`; el panel no
inicia ni modifica máquinas virtuales.

## Changelog

### [Unreleased]

- `feat`: añade estados adaptados y filtrados para el panel Conky ThinkPad.
