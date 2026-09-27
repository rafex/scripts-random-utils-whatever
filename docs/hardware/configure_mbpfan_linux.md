---
title: configure_mbpfan_linux.sh
description: Configura mbpfan y el control térmico del MacBook Pro
tags:
  - hardware
  - macbook
  - ventiladores
---

# configure_mbpfan_linux.sh

Instala y configura `mbpfan` para el perfil `macbook-pro-late2012`. Carga los
módulos `applesmc` y `coretemp`, instala una configuración conservadora y
habilita `mbpfan.service` para que el control responda automáticamente a la
carga del procesador.

- **Ruta:** `scripts/hardware/configure_mbpfan_linux.sh`
- **SO requerido:** Linux (Debian en MacBook Pro Intel)
- **Dependencias:** `bash`, `apt`, `dpkg-query`, `systemctl`, `sudo`, `modprobe`

______________________________________________________________________

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

- MacBook Pro Intel identificado por DMI como equipo Apple MacBook.
- Debian Trixie o compatible.
- `sudo` disponible para instalar el paquete, cargar módulos y habilitar el
  servicio.
- El kernel debe exponer los módulos `applesmc` y `coretemp`.
- No debe estar activo otro controlador como `macfanctld`, `fancontrol` o
  `thinkfan`.

Debian proporciona `mbpfan` como paquete nativo y el paquete incluye la unidad
`mbpfan.service`. Consulta el [paquete mbpfan de Debian](https://packages.debian.org/trixie/mbpfan)
y su [manual](https://manpages.debian.org/trixie/mbpfan/mbpfan.8.en.html).

## Uso

Comprobar el equipo y el estado actual:

```bash
just configure-mbpfan --check
```

Revisar el plan sin modificar el sistema:

```bash
just configure-mbpfan --plan
```

Instalar y habilitar el control térmico:

```bash
just configure-mbpfan --apply
```

Consultar el servicio:

```bash
just configure-mbpfan --status
systemctl status mbpfan.service --no-pager
```

Restaurar la configuración anterior:

```bash
just configure-mbpfan --rollback
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra modelo, módulos, paquete, configuración y servicio sin cambios |
| `--plan` | `--dry-run` | Muestra las acciones previstas sin escribir |
| `--status` | — | Consulta el estado actual sin escribir |
| `--apply` | — | Instala, configura, habilita y arranca `mbpfan.service` |
| `--rollback` | — | Restaura el respaldo más reciente de `/etc/mbpfan.conf` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

El script no utiliza variables de entorno para cambiar rutas, umbrales o el
servicio. La configuración versionada se encuentra en:

```text
dotfiles/profiles/macbook-pro-late2012/config/mbpfan.conf
```

Valores administrados:

```text
low_temp = 55
high_temp = 65
max_temp = 85
polling_interval = 1
```

No se fijan velocidades RPM manualmente; `mbpfan` usa los límites que publica
`applesmc` para el ventilador del equipo.

## Ejemplos

### Instalación del perfil

```bash
./dotfiles/install.sh --profile macbook-pro-late2012
just configure-mbpfan --apply
```

### Validación de módulos

```bash
lsmod | grep -E '^(applesmc|coretemp)'
find /sys/devices/platform -path '*/fan*_output' -print
```

### Diagnóstico del servicio

```bash
systemctl is-enabled mbpfan.service
systemctl is-active mbpfan.service
journalctl -u mbpfan.service -b --no-pager
```

## Protecciones de seguridad

- Solo permite aplicar en un equipo Apple MacBook identificado por DMI.
- Rechaza mezclar `mbpfan` con otro controlador activo de ventiladores.
- Conserva un respaldo root-only en `/var/backups/rafex-mbpfan/`.
- Escribe `/etc/mbpfan.conf` como `root:root` con permisos `0644`.
- No modifica BIOS, firmware, GRUB, voltajes, frecuencias ni límites de carga.
- No fija RPM arbitrariamente: respeta los límites publicados por `applesmc`.
- `--check`, `--plan` y `--status` no modifican el equipo.
- Si el servicio falla al arrancar, restaura la configuración anterior.

## Fallos conocidos

### `el equipo no coincide con el perfil MacBook Pro`

**Causa:** el script se ejecutó en ThinkPad, hardware no Apple o una máquina
virtual sin la identificación DMI del MacBook.

**Solución:** ejecuta el script únicamente en el MacBook Pro Late 2012.

### `applesmc no expone sysfs`

**Causa:** el módulo `applesmc` no existe, no pudo cargarse o el kernel no
expone sensores de ventilador.

**Solución:** revisa `modprobe applesmc`, `dmesg` y los archivos bajo
`/sys/devices/platform/applesmc.*`. No fuerces RPM sin validar el hardware.

### `controlador alternativo activo`

**Causa:** otro daemon intenta controlar los mismos ventiladores.

**Solución:** detén y deshabilita explícitamente el controlador alternativo,
valida su configuración y vuelve a ejecutar `--check` antes de usar `--apply`.

### `mbpfan.service no quedó activo`

**Causa:** el servicio no puede acceder a `applesmc`, la configuración no es
válida o falta un sensor térmico.

**Solución:** ejecuta `journalctl -u mbpfan.service -b --no-pager` y usa
`--rollback` si el problema empezó después de aplicar la configuración.

## Changelog

### [Unreleased]

- **feat:** añadir mbpfan al perfil MacBook Pro Late 2012 con servicio,
  módulos, configuración conservadora y rollback.
