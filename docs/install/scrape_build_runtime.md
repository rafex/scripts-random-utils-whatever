---
title: scrape_build_runtime.py
description: Obtiene metadata oficial y checksum de Maven o Gradle
tags:
  - instalación
  - java
  - referencia
---

# scrape_build_runtime.py

Consulta fuentes oficiales de Apache Maven y Gradle y devuelve JSON.

- **Ruta:** `scripts/install/scrape_build_runtime.py`
- **SO requerido:** Linux
- **Dependencias:** Python 3 estándar, red HTTPS

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

Requiere acceso HTTPS a Apache Archive o Gradle Services.

## Uso

```bash
python3 scripts/install/scrape_build_runtime.py --tool maven --version latest
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--tool` | — | `maven` o `gradle`. |
| `--version` | — | `latest` o versión exacta. |

## Variables de entorno

No usa variables especiales ni `.env`.

## Ejemplos

```bash
python3 scripts/install/scrape_build_runtime.py --tool gradle --version 9.7.1
```

## Fallos conocidos

### Metadata oficial no disponible

**Causa:** el release fue retirado o cambió el formato de publicación.

**Solución:** consulta otra versión publicada oficialmente.

## Changelog

### [Unreleased]

- **feat:** consultar Maven y Gradle con checksums oficiales.
