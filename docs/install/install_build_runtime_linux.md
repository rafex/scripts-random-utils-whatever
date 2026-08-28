---
title: install_build_runtime_linux.sh
description: Descarga Maven o Gradle manualmente y los integra en mise
tags:
  - instalación
  - desarrollo
  - mise
---

# install_build_runtime_linux.sh

Instala Maven o Gradle en el espacio del usuario y registra la ruta mediante
mise sin utilizar su descargador.

- **Ruta:** `scripts/install/install_build_runtime_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, Python 3, `curl`, `tar`, `unzip`, `sha256sum`, `sha512sum`, `mise`

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

Debe existir mise para registrar el runtime externo.

## Uso

```bash
just install-build-runtime --tool maven --version 3.9.16 --apply
just install-build-runtime --tool gradle --version 9.7.1 --apply
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el runtime actual y el registro. |
| `--plan` | `--dry-run` | Consulta metadata sin modificar. |
| `--apply` | — | Descarga, verifica, instala e integra. |
| `--tool` | — | `maven` o `gradle`. |
| `--version` | — | `latest` o versión exacta. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Entorno | Define la raíz local. |
| `TMPDIR` | Entorno | Define temporales. |

## Ejemplos

```bash
just install-build-runtime --tool maven --version latest --plan
just install-build-runtime --tool gradle --version latest --apply
```

## Protecciones de seguridad

- Verifica SHA-512 para Maven y SHA-256 para Gradle.
- No usa sudo ni modifica instalaciones globales.
- No ejecuta `mise install`.
- Conserva el registro y usa enlaces estables `current-maven` y `current-gradle`.

## Fallos conocidos

### Binario no encontrado tras extraer

**Causa:** cambió la estructura del archivo oficial.

**Solución:** no se registra el runtime; revisa la metadata y reintenta.

## Changelog

### [Unreleased]

- **feat:** instalar Maven y Gradle desde fuentes oficiales.
