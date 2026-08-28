---
title: scrape_node_runtime.py
description: Obtiene metadata oficial y checksum de Node.js para Linux
tags:
  - instalación
  - nodejs
  - referencia
---

# scrape_node_runtime.py

Consulta el índice oficial de Node.js y devuelve JSON para el instalador.

- **Ruta:** `scripts/install/scrape_node_runtime.py`
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

Requiere conectividad HTTPS a `nodejs.org`.

## Uso

```bash
python3 scripts/install/scrape_node_runtime.py --version lts
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--version` | — | `lts`, versión mayor o versión exacta. |
| `--architecture` | — | `x64` o `arm64`; por defecto detecta la máquina. |

## Variables de entorno

No usa variables especiales ni `.env`.

## Ejemplos

```bash
python3 scripts/install/scrape_node_runtime.py --version 24.20.0 --architecture x64
```

## Fallos conocidos

### No se encontró checksum

**Causa:** Node.js no publicó el archivo esperado.

**Solución:** revisa la versión y usa otra release oficial.

## Changelog

### [Unreleased]

- **feat:** consultar releases oficiales de Node.js con SHA-256.
