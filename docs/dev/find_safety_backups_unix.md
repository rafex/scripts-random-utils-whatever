---
title: find_safety_backups_unix.sh
description: Encuentra y borra respaldos .bak.<fecha> colocados junto a configs
tags:
  - mantenimiento
  - limpieza
  - respaldos
---

# find_safety_backups_unix.sh

Encuentra los respaldos `<archivo>.bak.<fecha>` que otros scripts de este
repositorio dejan junto al archivo que van a sobrescribir (antes de instalar
o configurar algo), y permite borrarlos todos de una vez o uno por uno con
un selector interactivo. No toca ningún otro mecanismo de respaldo del
repositorio (ver "Fallos conocidos").

- **Ruta:** `scripts/dev/find_safety_backups_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** Bash, `find`, `sed`, `stat`, `awk`; `sudo` para leer y
  para borrar hallazgos de sistema (`--include-system`, con o sin `--apply`)

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

Ninguno especial. `sudo` hace falta en cuanto se usa `--include-system` (o
`--roots` con una ruta fuera de `$HOME`): tanto para poder leer
subdirectorios de `/etc` con permisos restringidos (`/etc/ssl/private`,
`/etc/audit`, etc.) como, más adelante, para borrar lo encontrado.

## Uso

```bash
just find-safety-backups --check
just find-safety-backups --plan --include-system
just find-safety-backups --apply --all
just find-safety-backups --apply
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita sin modificar (default). |
| `--plan` | `--dry-run` | Igual que `--check`, mostrando qué se borraría. |
| `--apply` | — | Habilita el borrado. Sin `--all`, entra al selector interactivo. |
| `--all` | — | Junto con `--apply`, borra todo lo encontrado sin interacción. |
| `--include-system` | — | Agrega `/etc` a las raíces de búsqueda. |
| `--roots DIR[,DIR...]` | — | Reemplaza la lista completa de raíces de búsqueda. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Entorno | Define la raíz de búsqueda por defecto (usuario). |

No se usa `.env` ni se aceptan credenciales.

## Ejemplos

### Auditoría explícita

```bash
just find-safety-backups --check
```

### Con rutas de sistema (requiere sudo para leer y para borrar)

```bash
just find-safety-backups --plan --include-system
```

### Borrado total

```bash
just find-safety-backups --apply --all
```

### Selector interactivo (uno por uno)

```bash
just find-safety-backups --apply
```

Cada hallazgo aparece numerado. Se puede escribir un índice (`2`), una
lista o rango (`1,3` / `1-3`), `todo`/`a` para seleccionar todos los
restantes, o `q`/`salir` para terminar sin más cambios. Cada selección pide
confirmación (`[y/N]`) antes de borrar.

### Raíces personalizadas

```bash
just find-safety-backups --check --roots /mnt/home-viejo,/mnt/etc-viejo
```

## Protecciones de seguridad

- `--check` y `--plan` nunca modifican nada.
- Sin `--apply` no se borra nada; `--all` sin `--apply` se rechaza.
- Solo borra rutas cuyo nombre coincide exactamente con uno de los dos
  formatos de timestamp conocidos (`.bak.YYYYMMDD_HHMMSS[.N]` o
  `.bak-YYYYMMDD-HHMMSS.XXXXXX`); nunca un `rm -rf` de algo encontrado por
  un glob genérico. El nombre se revalida justo antes de cada borrado.
- Por defecto solo recorre `~/.config` y `~/.local/share` completos, más
  `$HOME` a un solo nivel (dotfiles directos como `.bashrc.bak.<fecha>`) —
  nunca baja dentro de árboles de proyecto arbitrarios que existan en el
  home, que es donde vive un colocado siempre según el catálogo de este
  repositorio.
- Excluye siempre (incluso con `--roots`) las raíces dedicadas de otros
  mecanismos de respaldo, fuera de alcance de este script: `/var/backups`,
  `~/.local/state/rafex/backups`, `~/.opencode/rafex-update-*`, además de
  árboles conocidos irrelevantes o con permisos restringidos
  (`~/.local/share/containers`, `~/.local/share/npm-global`,
  `~/.local/share/rafex/eww`, `~/.cache`, `~/.cargo`, `~/.rustup`,
  `~/.npm`, `~/.git`, `node_modules`).
- Nunca se ejecuta como root. `sudo` se usa únicamente para rutas de
  sistema (`--include-system`, o una raíz de `--roots` fuera de `$HOME`):
  tanto para listarlas (`find`, `stat`, comprobar si el original existe)
  como para borrar. Las raíces de usuario (`~/.config`, `~/.local/share`,
  `$HOME`) nunca invocan `sudo`.
- Un respaldo cuyo archivo original ya no existe se sigue considerando
  igual de seguro de borrar (se informa como "ausente", nunca bloquea el
  borrado).

## Fallos conocidos

### `raíz no existe: <ruta>`

**Causa:** una ruta pasada con `--roots` no existe, o `/etc` no está
presente (inusual).

**Solución:** es solo una advertencia; el script continúa con el resto de
las raíces. Verifica la ruta si el resultado no es el esperado.

### Este script no toca los directorios dedicados de rollback ni los volcados de /tmp

**Causa:** por diseño. El repositorio también crea, en otros scripts,
directorios dedicados de respaldo (`/var/backups/rafex-*/`,
`~/.local/state/rafex/backups/*/`, `~/.opencode/rafex-update-*/`) y volcados
de diagnóstico en `/tmp` (`podman-cleanup-*`, `disk-usage-*`). Ninguno de
esos es un respaldo `.bak.<fecha>` colocado, y quedan explícitamente fuera
de alcance de este script (ver exclusiones duras arriba).

**Solución:** no aplica; son mecanismos distintos que, si se necesita,
tendrían su propia herramienta de limpieza.

### `find: '/etc/...': Permiso denegado` con `--include-system --plan`/`--check`

**Causa (corregida):** versiones anteriores solo pedían `sudo` para
*borrar* hallazgos de sistema; la búsqueda (`find`) y la lectura de
metadatos (`stat`, comprobación del original) corrían siempre sin
privilegios, así que subdirectorios restringidos de `/etc`
(`/etc/ssl/private`, `/etc/audit`, `/etc/libvirt/secrets`, etc.) se
saltaban en silencio con "Permiso denegado", sin pedir nunca la
contraseña.

**Solución:** desde esta versión, cualquier raíz fuera de `$HOME`
(`--include-system` o `--roots` con una ruta de sistema) pide `sudo -v`
por adelantado y usa `sudo` también para `find`/`stat`/comprobar el
original, para poder leer esas rutas restringidas.

## Changelog

### [Unreleased]

- **feat:** localizar y borrar en bloque o interactivamente los respaldos
  `.bak.<fecha>` colocados junto a archivos de configuración, en rutas de
  usuario y (opcionalmente) del sistema.
- **fix:** `--include-system` (o `--roots` fuera de `$HOME`) ahora usa
  `sudo` también para leer (`find`, `stat`, comprobar el original), no
  solo para borrar — antes fallaba en silencio con "Permiso denegado" en
  subdirectorios restringidos de `/etc` y nunca pedía la contraseña.
