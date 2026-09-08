---
title: thinkpad_config_guard_linux.sh
description: Biblioteca para registrar y proteger escrituras de la configuración ThinkPad.
tags:
  - biblioteca
  - thinkpad
  - configuración
---

# thinkpad_config_guard_linux.sh

Biblioteca interna que los instaladores ThinkPad cargan mediante `source` para
verificar el propietario declarado de un recurso y registrar cambios en una
bitácora privada. No se ejecuta directamente.

- **Ruta:** `scripts/lib/thinkpad_config_guard_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `sha256sum`, `awk`, `cp`, `chmod`

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

La biblioteca requiere el registro versionado del perfil ThinkPad cuando se
quiere aplicar la protección de propiedad.

Cada entrada del registro declara recurso, propietario, destino o bloque,
dependencias, validador, exclusiones y política. La biblioteca usa las dos
primeras columnas para impedir que otro instalador se adjudique el recurso; el
auditor presenta las demás columnas para revisión humana.

## Uso

Los usuarios no deben invocarla directamente. Los instaladores Rafex cargan la
biblioteca y declaran el registro antes de modificar sus recursos:

```bash
export RAFEX_THINKPAD_OWNERSHIP_REGISTRY="/ruta/al/thinkpad-ownership.tsv"
source scripts/lib/thinkpad_config_guard_linux.sh
```

## Opciones

No acepta opciones de línea de comandos.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `RAFEX_THINKPAD_OWNERSHIP_REGISTRY` | vacío | Registro TSV que relaciona recurso y propietario. Si falta, la biblioteca conserva compatibilidad y no bloquea. |
| `XDG_STATE_HOME` | `~/.local/state` | Base de la bitácora privada. |

## Ejemplos

```bash
# Consultar la evidencia que escriben los instaladores.
tail -n 20 "$HOME/.local/state/rafex/thinkpad-config/changes.jsonl"

# Generar el mapa que explica cada recurso y su propietario.
just thinkpad-config-audit --report
```

## Protecciones de seguridad

- La bitácora se crea con directorio `0700` y archivo `0600`.
- Registra hashes y rutas, no secretos ni contenido de la configuración.
- Si el registro declara otro propietario para un recurso, la escritura queda
  bloqueada y se registra como `blocked`.
- No usa `sudo` ni modifica configuraciones por sí misma.

## Fallos conocidos

### `recurso … pertenece a …`

**Causa:** un instalador intentó escribir un recurso asignado a otro
propietario en `thinkpad-ownership.tsv`.

**Solución:** ejecutar la receta propietaria indicada por el auditor; no
sobrescribir el recurso manualmente desde otro instalador.

## Changelog

### [Unreleased]

- **feat:** añade registro privado con hashes y protección de propietario para
  la estabilización ThinkPad.
