---
title: commons_deploy_verify_unix.sh
description: Librería Bash compartida para despliegue, verificación y lectura de PATH.toml
tags:
  - referencia
  - desarrollo
---

# commons_deploy_verify_unix.sh

Librería Bash que se debe cargar con `source`; no es un programa independiente.

- **Ruta:** `scripts/dev/commons_deploy_verify_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** Bash, `awk`, `find`, `sha256sum`, `ssh` y `scp` según la función usada

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

El repositorio debe conservar `PATH.toml` en su raíz, salvo que se indique otra ruta mediante `PATH_TOML`. Las funciones SSH requieren acceso y autenticación configurados en el host remoto.

## Uso

Se carga desde otro script:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/commons_deploy_verify_unix.sh"
```

El archivo termina con error si se ejecuta directamente para evitar confundirlo con un comando operativo.

## Opciones

No tiene opciones de línea de comandos. Expone funciones Bash para:

| Función | Descripción |
|---|---|
| `toml_get` | Lee un valor de una sección TOML |
| `toml_list_section` | Lista pares clave/valor de una sección |
| `toml_list_array` | Lista elementos de un array TOML |
| `ssh_target` | Construye `usuario@host` desde `PATH.toml` |
| `deploy_one` | Copia un script y verifica permisos remotos |
| `verify_one` | Compara hashes local y remoto |
| `verify_local_checksums` | Comprueba `SHA256SUMS` |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `PATH_TOML` | `PATH.toml` en la raíz | Archivo de configuración de hosts y mappings |

## Ejemplos

```bash
source scripts/dev/commons_deploy_verify_unix.sh
list_hosts
verify_local_checksums
```

## Fallos conocidos

### `este archivo se sourcea, no se ejecuta directamente`

**Causa:** se invocó la librería como programa.

**Solución:** cargarla con `source` desde `deploy_verify_unix.sh` o desde otro script compatible.

### No se encuentra un host o mapping

**Causa:** falta la sección correspondiente en `PATH.toml`.

**Solución:** revisar las secciones `[hosts.<nombre>]` y `[scripts]` antes de usar funciones SSH.

## Changelog

### [Unreleased]

- **docs:** documentar funciones compartidas, variables y dependencias.
