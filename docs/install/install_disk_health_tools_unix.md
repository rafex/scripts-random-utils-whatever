---
title: install_disk_health_tools_unix.sh
description: Instala smartmontools y fio para el diagnóstico de discos USB
tags:
  - install
  - hardware
  - almacenamiento
---

# install_disk_health_tools_unix.sh

Instala `smartmontools` (`smartctl`) y `fio`, requeridos por el diagnóstico de discos USB. Es idempotente y no modifica los discos.

- **Ruta:** `scripts/install/install_disk_health_tools_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`; Homebrew en macOS; un gestor compatible y `sudo` en Linux
- **Task runner:** `just` (recomendado)

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- macOS: Homebrew debe estar instalado.
- Linux: se admite APT, DNF, pacman, zypper o apk. `sudo` se usa cuando el script no se ejecuta como root.
- Se requiere conexión a Internet para descargar los paquetes.

El script detecta si `smartctl` o `fio` ya existen y solo instala lo que falta. En macOS usa Homebrew; en Linux usa el gestor detectado. No instala Homebrew ni realiza cambios en los discos.

## Uso

Desde la raíz del repositorio:

```sh
just install-disk-health-tools
```

La tarea puede solicitar la contraseña de `sudo` en Linux. Al terminar verifica que ambos comandos estén disponibles.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--help` | `-h` | Mostrar esta ayuda. |

## Variables de entorno

Este script no define ni consume variables de entorno propias. El gestor de paquetes puede respetar sus variables habituales.

## Ejemplos

Instalación recomendada:

```sh
just install-disk-health-tools
```

Ejecución directa:

```sh
bash scripts/install/install_disk_health_tools_unix.sh
```

Mostrar la ayuda:

```sh
just install-disk-health-tools --help
```

## Fallos conocidos

### `Homebrew no está instalado`

**Causa:** macOS no tiene Homebrew disponible en el `PATH`.
**Solución:** instala Homebrew desde su sitio oficial y vuelve a ejecutar la tarea.

### `no se encontró un gestor compatible`

**Causa:** la distribución Linux no ofrece APT, DNF, pacman, zypper ni apk.
**Solución:** instala `smartmontools` y `fio` con el gestor de paquetes de la distribución.

### `sudo es necesario para instalar paquetes`

**Causa:** el usuario no es root y no tiene `sudo` disponible.
**Solución:** ejecuta el script como root o configura `sudo` para la cuenta.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-10-07

**feat:** instala las dependencias del diagnóstico SMART y de escritura USB.

- Añade instalación idempotente de `smartmontools` y `fio` en macOS y Linux.
- Verifica los comandos instalados sin escribir en discos.
