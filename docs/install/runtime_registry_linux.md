---
title: runtime_registry_linux.sh
description: Registro local de runtimes descargados por los instaladores del repositorio
tags:
  - instalación
  - runtimes
---

# runtime_registry_linux.sh

Biblioteca interna que mantiene el manifiesto de runtimes instalados manualmente.

- **Ruta:** `scripts/install/runtime_registry_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `awk`, `mktemp`

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

Se carga desde otros instaladores; no se ejecuta directamente.

## Uso

El registro se guarda en `~/.local/share/rafex-runtimes/registry.tsv`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `runtime_registry_upsert` | — | Inserta o actualiza una entrada. |
| `runtime_registry_remove` | — | Elimina una entrada concreta. |
| `runtime_registry_list` | — | Lista entradas por herramienta. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `XDG_DATA_HOME` | Entorno | Cambia la raíz del registro. |
| `HOME` | Entorno | Define el directorio de datos predeterminado. |

## Ejemplos

```bash
source scripts/install/runtime_registry_linux.sh
runtime_registry_list java
```

## Protecciones de seguridad

- Usa archivos temporales y reemplazo atómico.
- Mantiene el manifiesto con permisos privados.
- No descarga, instala ni elimina runtimes por sí mismo.

## Fallos conocidos

### Registro ausente

**Causa:** ningún instalador propio ha registrado un runtime.

**Solución:** ejecuta el instalador correspondiente.

## Changelog

### [Unreleased]

- **feat:** añadir registro compartido de runtimes manuales.
