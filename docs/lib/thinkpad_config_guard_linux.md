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
bitácora privada. Después de una escritura exitosa conserva un snapshot de la
configuración instalada en el repositorio local de historial. No se ejecuta
directamente.

- **Ruta:** `scripts/lib/thinkpad_config_guard_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `sha256sum`, `awk`, `cp`, `chmod`, `git`, `flock`, `stat`

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
| `RAFEX_THINKPAD_OWNERSHIP_REGISTRY` | vacío | Registro TSV que relaciona recurso y propietario. Para cualquier escritura administrada es obligatorio; si falta, la biblioteca bloquea la operación. |
| `RAFEX_THINKPAD_HISTORY` | `~/.local/share/rafex-thinkpad` | Repositorio Git local que conserva únicamente snapshots de archivos instalados y su manifiesto. |
| `XDG_STATE_HOME` | `~/.local/state` | Base de la bitácora privada. |

## Ejemplos

```bash
# Consultar la evidencia que escriben los instaladores.
tail -n 20 "$HOME/.local/state/rafex/thinkpad-config/changes.jsonl"

# Generar el mapa que explica cada recurso y su propietario.
just thinkpad-config-audit --report

# Consultar el historial local de lo instalado.
git -C "$HOME/.local/share/rafex-thinkpad" log --oneline
```

## Protecciones de seguridad

- La bitácora se crea con directorio `0700` y archivo `0600`.
- Registra hashes y rutas, no secretos ni contenido de la configuración.
- Si el registro declara otro propietario para un recurso, la escritura queda
  bloqueada y se registra como `blocked`.
- `rafex_guard_record_write` actualiza el repositorio local de historial bajo
  `~/.local/share/rafex-thinkpad`; no clona el repositorio replicador ni hace
  `push` remoto.
- El snapshot solo admite rutas bajo `$HOME`, `/etc`, `/usr/local` y `/lib`, y mantiene
  el repositorio local con permisos `0700`.
- No modifica configuraciones por sí misma; para leer un archivo de sistema
  usa `sudo -n` únicamente si los permisos normales no bastan.

## Fallos conocidos

### `recurso … pertenece a …`

**Causa:** un instalador intentó escribir un recurso asignado a otro
propietario en `thinkpad-ownership.tsv`.

**Solución:** ejecutar la receta propietaria indicada por el auditor; no
sobrescribir el recurso manualmente desde otro instalador.

### `no se pudo registrar el historial local`

**Causa:** falta Git, `flock`, espacio o permisos para actualizar
`~/.local/share/rafex-thinkpad` después de una escritura.

**Solución:** revisar el error, conservar el respaldo creado y ejecutar el
auditor antes de continuar con otra instalación. La configuración ya escrita
no se considera plenamente registrada hasta que exista el snapshot.

## Changelog

### [Unreleased]

- **feat:** añade registro privado con hashes, snapshots y protección de
  propietario para la estabilización ThinkPad.

- **fix:** registra snapshots de archivos instalados en el repositorio local
  `rafex-thinkpad`, separado del repositorio replicador.

- **fix:** usa descriptores de archivo portables para serializar operaciones y
  permite que los escritores de i3 actualicen fragmentos sin competir por el
  archivo compuesto.
- **fix:** añade bootstrap explícito para recursos ausentes, sin permitir que
  un instalador suplante al propietario registrado.
