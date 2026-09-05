---
title: update_opencode_unix.sh
description: Actualizar OpenCode local del perfil conservando sus dos binarios y respaldos
tags:
  - desarrollo
  - opencode
---

# update_opencode_unix.sh

Actualiza la instalación oficial local de OpenCode y sincroniza la copia usada
por el perfil. No realiza la primera instalación ni administra paquetes npm/Homebrew.

- **Ruta:** `scripts/dev/update_opencode_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** Bash, curl, herramientas Unix y OpenCode local instalado

---

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

El instalador `install_terminal_workstation_linux.sh --stage opencode` descarga
`https://opencode.ai/install`, lo ejecuta con `--no-modify-path` y copia
`~/.opencode/bin/opencode` a `~/.local/bin/opencode`. Si esta última copia existe,
omite la instalación: repetir esa etapa **no actualiza** OpenCode.

Este actualizador requiere ambos binarios ejecutables y propiedad del usuario.
Solo `--apply` necesita Internet. Cierra OpenCode antes de actualizarlo.
La fuente es el [instalador oficial de OpenCode](https://opencode.ai/install).
La CLI también ofrece [upgrade](https://opencode.ai/docs/cli/#upgrade), pero
actualizar una copia no garantiza sincronizar la otra creada por nuestro perfil.

## Uso

```bash
just update-opencode --check
just update-opencode --plan
just update-opencode --apply
just update-opencode --status
```

`--check` es la acción predeterminada. Las consultas muestran versiones locales;
no consultan cuál es la última release. Apply conserva respaldo de ambos binarios,
descarga el instalador, valida la versión y reemplaza atómicamente la copia activa.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba instalación local y conflictos de PATH; no actualiza. |
| `--plan` | — | Muestra destino y operación sin descargar ni actualizar. |
| `--status` | — | Muestra versiones de ambas copias. |
| `--apply` | — | Actualiza con el instalador oficial y sincroniza los binarios. |
| `--version X.Y.Z` | — | Selecciona una versión estable explícita; admite prefijo v. Puede bajar de versión. |
| `--help` | `-h` | Muestra ayuda. |

## Variables de entorno

| Variable | Uso |
|---|---|
| `HOME` | Directorio del usuario: instalaciones y respaldos. No cambiarlo para operar sobre otro usuario. |
| `PATH` | Detecta si otra instalación oculta las copias locales. |
| `VERSION` | Se elimina del entorno del instalador: solo `--version` decide la versión. |

No usa `.env`. Sin `--version`, el instalador oficial selecciona la última estable.

## Ejemplos

```bash
# Recomendado
just update-opencode --plan
just update-opencode --apply

# Seleccionar la versión que hayas verificado en las releases oficiales
just update-opencode --apply --version 1.0.180

# PATH explícito, conservando HOME del usuario
PATH="$HOME/.local/bin:$PATH" bash scripts/dev/update_opencode_unix.sh --status
```

## Protecciones de seguridad

- Sin sudo; rechaza ejecución como root, enlaces en las rutas administradas y
  binarios ajenos. Rechaza otra instalación de OpenCode anterior en PATH.
- Lock para evitar dos actualizaciones simultáneas. No detiene sesiones abiertas.
- Respaldo privado `~/.opencode/rafex-update-FECHA.XXXXXX/`: `original`, `active`
  y copia del instalador ejecutado. No se borra automáticamente.
- Ante error o señal capturable, intenta restaurar ambos binarios. Un corte de
  corriente o SIGKILL requiere recuperación manual desde esos respaldos.
- No modifica deliberadamente credenciales, MCP ni archivos de shell. Las
  consultas invocan `--version`; no se garantiza ausencia de efectos internos
  de una versión del programa.
- El instalador descargado ejecuta código del proveedor: HTTPS y `bash -n` no
  sustituyen una firma ni una auditoría. No se promete verificación criptográfica
  independiente de los binarios descargados.

Para revertir manualmente, con OpenCode cerrado, restaura `original` en
`~/.opencode/bin/opencode` y `active` en `~/.local/bin/opencode` con `install -m 755`,
usando la ruta exacta del respaldo mostrado. No uses sudo.

## Fallos conocidos

### `Falta binario local propio`

**Causa:** instalación incompleta o método distinto al del perfil.
**Solución:** revisa la etapa OpenCode del instalador del perfil. Si usas npm o
Homebrew, actualiza con ese gestor; este script no migra instalaciones.

### `Actualización bloqueada`

**Causa:** otra ejecución activa o interrupción no capturable.
**Solución:** confirma que no existe otra actualización, revisa/restaura los
respaldos si procede y elimina únicamente el directorio vacío
`~/.opencode/.rafex-update.lock` con `rmdir`.

### `Otra instalación precede en PATH`

**Causa:** un paquete o una ruta distinta oculta la instalación local.
**Solución:** decide qué instalación conservar; no se actualiza automáticamente
un paquete administrado por otro gestor.

## Changelog

### v1.0.0 — 2026-09-04

**feat:** actualización explícita macOS/Linux del método usado por el perfil,
con versiones seleccionables, bloqueo, respaldo y restauración ante errores.
