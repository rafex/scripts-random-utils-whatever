---
title: configure_tpm_blacklist_linux.sh
description: Bloquea de forma reversible la carga de módulos TPM en Debian.
tags:
  - hardware
  - tpm
  - seguridad
---

# configure_tpm_blacklist_linux.sh

Instala una regla administrada de `modprobe` para impedir la carga automática
de los módulos TPM en Debian y regenera los `initramfs` para los kernels
instalados.

- **Ruta:** `scripts/hardware/configure_tpm_blacklist_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `modprobe`, `update-initramfs`, `sudo`, `awk`, `grep`, `find`

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

- Debian con `modprobe`, `/etc/modprobe.d` y `initramfs-tools`.
- Una sesión de usuario normal con `sudo`; no se debe ejecutar el script como
  root.
- La contraseña de `sudo` para `--apply` o `--rollback`.

La regla administra `tpm`, `tpm_crb`, `tpm_tis` y `tpm_tis_core`. No cambia el
firmware UEFI, no borra claves TPM y no descarga un módulo que ya esté cargado.

## Uso

Desde la raíz del repositorio:

```bash
just configure-tpm-blacklist --check
just configure-tpm-blacklist --plan
just configure-tpm-blacklist --apply
sudo reboot
just configure-tpm-blacklist --status
```

Para volver al estado anterior:

```bash
just configure-tpm-blacklist --rollback
sudo reboot
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida Debian, modprobe, initramfs y conflictos sin escribir. |
| `--plan` | `--dry-run` | Muestra el archivo y la regeneración previstas sin escribir. |
| `--status` | — | Muestra la regla, módulos cargados y cantidad de respaldos. |
| `--apply` | — | Escribe la blacklist, regenera todos los initramfs y no reinicia. |
| `--rollback` | — | Restaura el respaldo administrado más reciente y regenera initramfs. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no acepta variables de entorno para cambiar el destino, los
módulos o la operación. Los destinos están fijados para evitar modificaciones
accidentales.

## Ejemplos

### Forma recomendada

```bash
just configure-tpm-blacklist --check
just configure-tpm-blacklist --plan
just configure-tpm-blacklist --apply
```

### Consultar sin cambios

```bash
just configure-tpm-blacklist --status
```

### Recuperación

```bash
just configure-tpm-blacklist --rollback
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- Solo `--apply` y `--rollback` solicitan `sudo`.
- El archivo es `/etc/modprobe.d/99-rafex-tpm-blacklist.conf`; si existe otro
  archivo con reglas TPM no administradas, el script se detiene.
- Cada aplicación guarda un respaldo fechado bajo
  `/var/backups/rafex-tpm-blacklist/`.
- Si la regeneración falla, el archivo previo se restaura y se intenta
  regenerar de nuevo.
- No se usa `modprobe -r`, no se modifica `/etc/default/grub`, no se cambia la
  configuración del firmware y no se reinicia automáticamente.

## Fallos conocidos

### `hay reglas TPM no administradas`

**Causa:** otro archivo de `/etc/modprobe.d` ya contiene `blacklist` o
`install` para un módulo TPM.

**Solución:** revisa la regla manual y decide explícitamente cómo combinarla;
el script no la sobrescribe.

### El módulo TPM continúa cargado después de `--apply`

**Causa:** la blacklist impide cargas futuras, pero no descarga módulos que ya
están activos en el kernel.

**Solución:** reinicia manualmente y consulta `/proc/modules` o `--status`.

### Se necesita TPM, `/dev/tpm*` o cifrado ligado al TPM

**Causa:** algunas funciones de cifrado, atestación, llaves de hardware y
arranque medido dependen del TPM/PTT.

**Solución:** ejecuta `--rollback` y reinicia. La blacklist no es necesaria
para corregir una batería, y debe considerarse una prueba de diagnóstico.

## Changelog

### [Unreleased]

- **feat:** añadir blacklist TPM reversible con respaldo y regeneración de
  initramfs.
