---
title: validate_script_docs.py
description: Valida cobertura, estructura, frontmatter y enlaces de la documentación
tags:
  - referencia
  - desarrollo
  - documentación
---

# validate_script_docs.py

Comprueba que los scripts del repositorio estén documentados y que la estructura MkDocs sea coherente.

- **Ruta:** `scripts/dev/validate_script_docs.py`
- **SO requerido:** macOS, Linux
- **Dependencias:** Python 3 y la biblioteca estándar

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

Ejecuta el script desde cualquier ubicación dentro de un clon del repositorio. No necesita red, `sudo` ni dependencias externas.

## Uso

```bash
python3 scripts/dev/validate_script_docs.py
```

El proceso termina con código distinto de cero si encuentra errores.

## Opciones

No tiene opciones de línea de comandos.

## Variables de entorno

No usa variables de entorno.

## Ejemplos

```bash
python3 scripts/dev/validate_script_docs.py
make docs-check
```

## Fallos conocidos

### `Documentación inválida`

**Causa:** falta un documento, una sección, frontmatter, una ruta del catálogo o un enlace local.

**Solución:** corregir el documento indicado y volver a ejecutar el validador.

## Archivo .env

Este script no carga un archivo de configuración `.env`; la sección se conserva para declarar explícitamente esa ausencia.

## Changelog

### [Unreleased]

- **feat:** validar cobertura y estructura documental para MkDocs.
