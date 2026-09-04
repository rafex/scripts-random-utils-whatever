---
title: configure_initramfs_compression_linux.sh
description: Configura de forma reversible la compresión del initramfs en Debian
tags:
  - hardware
  - kernel
  - initramfs
---

# configure_initramfs_compression_linux.sh

Configura la compresión del `initramfs` de todos los kernels instalados.
Usa `zstd` por defecto y permite seleccionar `xz`, `lz4` o
`gzip`.

- **Ruta:** `scripts/hardware/configure_initramfs_compression_linux.sh`
- **SO requerido:** Linux (Debian con initramfs-tools)
- **Dependencias:** `bash`, `initramfs-tools`, `file`, `find`, `sudo`; `zstd`, `xz-utils` o `lz4` según la opción

El script no cambia la compresión de `vmlinuz`: esa propiedad pertenece a la
compilación del kernel (`CONFIG_KERNEL_XZ` o `CONFIG_KERNEL_ZSTD`).

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

- Debian con `/lib/modules` y `/boot` accesibles.
- `initramfs-tools`, `update-initramfs`, `mkinitramfs` y
  `lsinitramfs`.
- Configuración de cada kernel en `/boot/config-*`, con soporte integrado para
  el algoritmo elegido (`CONFIG_RD_ZSTD`, `CONFIG_RD_XZ`,
  `CONFIG_RD_LZ4` o `CONFIG_RD_GZIP`).
- `sudo` para `--apply` y `--rollback`.

Si falta la herramienta del algoritmo elegido, `--apply` instalará únicamente
el paquete correspondiente mediante APT: `zstd`, `xz-utils` o `lz4`.

## Uso

Desde la raíz del repositorio:

```bash
just configure-initramfs-compression --check
just configure-initramfs-compression --plan
just configure-initramfs-compression --status
just configure-initramfs-compression --apply --compression zstd
just configure-initramfs-compression --rollback --latest
```

Después de aplicar, reinicia manualmente y vuelve a consultar `--status`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--compression <algoritmo>` | — | Selecciona `zstd` (predeterminado), `xz`, `lz4` o `gzip`. |
| `--check` | — | Muestra estado sin modificar nada. |
| `--plan` | `--dry-run` | Valida prerrequisitos y muestra cambios previstos. |
| `--status` | — | Muestra la compresión efectiva y el formato de cada initramfs. |
| `--apply` | — | Instala la dependencia faltante, respalda y regenera todos los initramfs. |
| `--rollback` | — | Inicia una restauración; requiere `--latest`. |
| `--latest` | — | Selecciona el respaldo administrado más reciente para rollback. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no utiliza variables de entorno para seleccionar archivos,
algoritmos ni destinos. Las opciones de línea de comandos tienen toda la
configuración necesaria.

## Ejemplos

### Forma recomendada: Zstandard

```bash
just configure-initramfs-compression --plan --compression zstd
just configure-initramfs-compression --apply --compression zstd
```

### XZ cuando se prioriza el menor tamaño

```bash
just configure-initramfs-compression --plan --compression xz
just configure-initramfs-compression --apply --compression xz
```

### Diagnóstico sin privilegios

```bash
just configure-initramfs-compression --status
```

### Recuperación

```bash
just configure-initramfs-compression --rollback --latest
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no escriben en el sistema.
- `--apply` exige una invocación explícita y solicita `sudo` únicamente para
  APT, `/etc/initramfs-tools`, `/boot` y la regeneración de initramfs.
- Se respalda la configuración administrada y cada `initrd.img-*` antes de
  modificar cualquier archivo.
- Directivas `COMPRESS=` manuales que entren en conflicto detienen la operación
  y no se sobrescriben.
- Se valida el soporte `CONFIG_RD_*` de todos los kernels instalados.
- Si `update-initramfs` o `lsinitramfs` falla, se restaura automáticamente el
  respaldo creado en esa ejecución.
- No se modifican `vmlinuz`, GRUB, particiones, módulos ni parámetros de
  arranque.
- No se reinicia el equipo automáticamente.

## Fallos conocidos

### `falta CONFIG_RD_ZSTD=y` (o equivalente)

**Causa:** el kernel no tiene integrado el descompresor elegido o falta
`/boot/config-*` para verificarlo.

**Solución:** usa otro algoritmo soportado por todos los kernels instalados o
instala un kernel Debian que incluya ese soporte. El script no recompila el
kernel.

### `configuración manual conflictiva`

**Causa:** `initramfs.conf` o un archivo de `conf.d` ya establece otro valor de
`COMPRESS=`.

**Solución:** revisa y resuelve manualmente esa directiva; el script no la
sobrescribe para preservar configuraciones ajenas.

### La imagen conserva otra compresión después de `--apply`

**Causa:** `update-initramfs` no aplicó el drop-in o la detección de formato no
coincide con la herramienta instalada.

**Solución:** el script revierte automáticamente; revisa el diagnóstico y no
reinicies hasta resolverlo.

### El sistema no arranca después de un cambio manual

**Causa:** el initramfs seleccionado no es compatible con el kernel o quedó
dañado por una interrupción externa.

**Solución:** inicia un kernel anterior desde GRUB y ejecuta
`--rollback --latest`; no desconectes el equipo durante `update-initramfs`.

## Changelog

### [Unreleased]

- **feat:** añadir configuración reversible de initramfs con zstd, xz, lz4 y gzip.
