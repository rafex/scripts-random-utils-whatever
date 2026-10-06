---
title: install_reco_linux.sh
description: Compila Reco desde su repositorio oficial e instala en el espacio del usuario.
tags:
  - instalación
  - audio
  - reco
---

# install_reco_linux

Descarga Reco desde el repositorio oficial, compila el código nativo con Meson e instala la aplicación en el prefijo local del usuario.

- **Ruta:** `scripts/install/install_reco_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `git`, `sudo`, APT, Meson, Ninja, Vala, Blueprint Compiler, GTK 4, libadwaita, GStreamer, libgee, GLib, gettext, pkg-config

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

- Debian con APT y conexión a Internet.
- Ejecutar como usuario normal. `sudo` se utiliza para dependencias APT; Reco se instala en `~/.local`.
- El repositorio oficial compila con Meson. Los wraps del proyecto descargan versiones fijadas de `libryokucha` y `live-chart`.

## Uso

`just install-reco --apply` instala los paquetes de compilación y ejecución, clona la rama `main` de GitHub, compila con Meson y publica el binario y el lanzador de escritorio en `~/.local`.

`just install-reco --update` actualiza el checkout existente con un fast-forward y vuelve a compilar e instalar. Si todavía no existe, lo clona primero. Los cambios rastreados locales bloquean la actualización para evitar sobrescribir trabajo.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra dependencias y estado local sin modificar nada. |
| `--plan` | `--dry-run` | Muestra los pasos de instalación o actualización. |
| `--apply` | — | Instala dependencias, descarga, compila e instala Reco. |
| `--update` | — | Avanza `main` mediante fast-forward y recompila; clona si aún no existe. |
| `--status` | — | Muestra commit, rama, binario y lanzador de escritorio. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos CLI seleccionan la acción. Estas variables cambian las rutas de instalación:

| Variable | Predeterminado | Descripción |
|---|---|---|
| `RECO_SOURCE_DIR` | `$XDG_DATA_HOME/src/reco` o `~/.local/share/src/reco` | Checkout administrado por el instalador. |
| `RECO_PREFIX` | `~/.local` | Prefijo local de instalación. |
| `XDG_DATA_HOME` | `~/.local/share` | Base usada para el checkout si no se define `RECO_SOURCE_DIR`. |

## Ejemplos

Forma recomendada:

```bash
just install-reco --check
just install-reco --plan
just install-reco --apply
```

Actualizar Reco después:

```bash
just install-reco --update
```

Usar un checkout y prefijo distintos:

```bash
RECO_SOURCE_DIR="$HOME/src/reco" RECO_PREFIX="$HOME/.local" just install-reco --apply
```

## Protecciones de seguridad

- Verifica que un checkout existente use el remoto oficial y la rama `main` antes de actualizarlo.
- Se detiene si hay cambios rastreados en el checkout; no ejecuta `reset --hard` ni descarta modificaciones.
- Instala archivos de Reco en el prefijo del usuario. Solo la instalación de dependencias del sistema usa `sudo`.

## Fallos conocidos

### `hay cambios rastreados sin guardar`

**Causa:** hay cambios locales preparados o sin preparar en el checkout.
**Solución:** conserva los cambios en un commit o copia el checkout y vuelve a ejecutar `--update`.

### `el checkout tiene un remoto inesperado` o `no está en la rama main`

**Causa:** la ruta configurada ya contiene otro repositorio o una rama diferente.
**Solución:** define `RECO_SOURCE_DIR` a una ruta vacía para clonar el repositorio oficial en una ubicación separada.

### Meson no encuentra `libryokucha` o `livechart`

**Causa:** el equipo no pudo descargar los subproyectos fijados por los wraps de Reco.
**Solución:** confirma la conexión con GitHub y reintenta `just install-reco --update`.

### `libryokucha.so: cannot open shared object file`

**Causa:** el ejecutable no tiene configurada la ruta del prefijo local de bibliotecas.
**Solución:** ejecuta `just install-reco --apply` para volver a compilar con RPATH al `libdir` de Meson.

## Changelog

### [Unreleased]

### v1.0.1 — 2026-10-06

**fix:** compilar desde el checkout y enlazar dependencias del prefijo local.

- Configurar Meson con la ruta del checkout clonado y enlazar bibliotecas instaladas en `~/.local` mediante RPATH.
- Validar en `--status` que el ejecutable no tenga bibliotecas compartidas faltantes.

### v1.0.0 — 2026-10-06

**feat:** compilar Reco nativamente desde su repositorio oficial.

- Instalar dependencias Debian y publicar Reco en `~/.local`.
- Añadir actualización segura por fast-forward mediante `--update`.
