---
title: configure_fstrim_linux.sh
description: Activa el mantenimiento TRIM periódico para SSD y NVMe en Debian
tags:
  - hardware
  - almacenamiento
---

# configure_fstrim_linux.sh

Activa el temporizador de systemd que ejecuta TRIM periódicamente sobre los
filesystems compatibles de la ThinkPad.

- **Ruta:** `scripts/hardware/configure_fstrim_linux.sh`
- **SO requerido:** Linux (Debian con systemd)
- **Dependencias:** `bash`, `systemctl`, `sudo`

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

- Debian ejecutando systemd.
- El paquete `util-linux`, que proporciona `fstrim.service` y
  `fstrim.timer`.
- Permisos de `sudo` para `--apply`.

## Uso

Desde la raíz del repositorio:

```bash
just configure-fstrim --check
just configure-fstrim --plan
just configure-fstrim --apply
just configure-fstrim --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el estado sin modificar nada. |
| `--plan` | `--dry-run` | Muestra las acciones previstas sin modificar. |
| `--apply` | — | Ejecuta `sudo systemctl enable --now fstrim.timer`. |
| `--status` | — | Muestra estado y próxima ejecución del timer. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no utiliza variables de entorno. La unidad gestionada es siempre
`fstrim.timer`.

## Ejemplos

### Forma recomendada

```bash
just configure-fstrim --apply
```

### Diagnóstico sin privilegios

```bash
just configure-fstrim --check
```

### Ejecución directa

```bash
bash scripts/hardware/configure_fstrim_linux.sh --status
```

### Verificación del filesystem raíz

```bash
findmnt /
lsblk -f
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`.
- No ejecuta `fstrim` inmediatamente; solo activa su calendario periódico.
- No modifica `fstab`, GRUB, particiones ni opciones de montaje.
- Es idempotente: repetir `--apply` no crea unidades ni configuraciones
  duplicadas.
- No configura manualmente el scheduler de I/O del NVMe.

## Fallos conocidos

### `fstrim.timer` no está disponible

**Causa:** falta `util-linux` o el sistema no está ejecutando systemd.

**Solución:** instala `util-linux` desde Debian y vuelve a ejecutar el
diagnóstico. En una instalación Debian estándar, `fstrim.timer` forma parte
del mantenimiento proporcionado por systemd/util-linux.

### `Interactive authentication required`

**Causa:** la sesión no puede obtener autorización para cambiar unidades
systemd.

**Solución:** ejecuta `--apply` desde una sesión local o verifica que `sudo`
esté configurado para el usuario `rafex`.

### El timer está activo pero no aparece un trim inmediato

**Causa:** este script no fuerza una ejecución manual; el servicio se ejecuta
en el siguiente momento programado por systemd.

**Solución:** consulta la próxima ejecución con `--status`. No es necesario
añadir `discard` permanente a `fstab`.

## Changelog

### [Unreleased]

- **feat:** añadir configuración idempotente de `fstrim.timer` para SSD y NVMe.
