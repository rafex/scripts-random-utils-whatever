---
title: reconcile_runtimes_linux.sh
description: Audita y elimina instalaciones legacy creadas directamente por mise
tags:
  - instalación
  - runtimes
  - seguridad
---

# reconcile_runtimes_linux.sh

Audita el registro propio y las rutas legacy conocidas de mise. En `--apply`
reintegra los enlaces manuales en mise y corrige la selección global sin
descargar runtimes. Solo elimina con `--apply --purge-legacy` y después de
verificar reemplazos propios.

También informa de directorios reales encontrados dentro de los backends de
mise que no estén en la lista legacy explícita. Esos directorios quedan fuera
de toda eliminación automática.

- **Ruta:** `scripts/install/reconcile_runtimes_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `mise`, `awk`, `readlink`

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

Instala primero los reemplazos con `install-java-runtime`,
`install-node-runtime` e `install-build-runtime`.

## Uso

```bash
just reconcile-runtimes --check
just reconcile-runtimes --plan
just reconcile-runtimes --apply
just reconcile-runtimes --apply --purge-legacy
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita sin modificar. |
| `--plan` | `--dry-run` | Muestra la purga prevista sin modificar. |
| `--apply` | — | Reintegra el registro, corrige selecciones y recalcula shims. |
| `--purge-legacy` | — | Autoriza borrar solo rutas legacy explícitas. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Entorno | Define las rutas a auditar. |
| `XDG_DATA_HOME` | Entorno | Define la ubicación del registro propio. |

## Ejemplos

```bash
just reconcile-runtimes --check
just reconcile-runtimes --apply --purge-legacy
```

## Protecciones de seguridad

- `--check` y `--plan` son no destructivos.
- Sin `--purge-legacy` no elimina archivos.
- Solo opera sobre rutas legacy codificadas explícitamente.
- Exige un reemplazo registrado con el binario esperado.
- Comprueba que ningún runtime que se vaya a borrar siga siendo el activo.
- No toca otros directorios de `mise`.

## Fallos conocidos

### `falta reemplazo verificado`

**Causa:** todavía no se instaló manualmente el runtime sustituto.

**Solución:** ejecuta primero el instalador propio y repite `--check`.

## Changelog

### [Unreleased]

- **feat:** auditar y purgar runtimes legacy con autorización explícita.
