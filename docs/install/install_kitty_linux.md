---
title: install_kitty_linux.sh
description: Instala Kitty x86_64 desde el release oficial en el espacio del usuario.
tags:
  - instalación
  - kitty
  - terminal
---

# install_kitty_linux.sh

Instala Kitty `0.49.1` o consulta e instala el último release estable para la
ThinkPad desde el artefacto Linux x86_64 oficial de GitHub. No reemplaza el
paquete Debian, no requiere `sudo` y no inicia el terminal automáticamente.

- **Ruta:** `scripts/install/install_kitty_linux.sh`
- **SO requerido:** Linux (Debian, x86_64)
- **Dependencias:** `bash`, `curl`, `jq` (solo para `--update`), `sha256sum`, `tar` con soporte xz, `file`, `stat`

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

La ThinkPad debe ser Linux `x86_64` y tener conexión HTTPS para descargar el
release si no existe localmente. El instalador busca primero
`$XDG_DOWNLOAD_DIR`, el directorio de `xdg-user-dir DOWNLOAD`, `~/Descargas` y
`~/Downloads`.

El artefacto fijado es:

```text
kitty-0.49.1-x86_64.txz
https://github.com/kovidgoyal/kitty/releases/download/v0.49.1/kitty-0.49.1-x86_64.txz
SHA-256: 8cfd68ed484d9a32e4e389abffe1a0ec6e0fbd7be5c9ea1c4fa41b9ead4af791
```

La instalación queda bajo `~/.local/share/rafex/kitty/0.49.1`. Al actualizar
desde una versión instalada por este script, los enlaces administrados se
repuntan a la nueva versión y la anterior se conserva. Los enlaces
`~/.local/bin/kitty`, `~/.local/bin/kitten` y el lanzador
`~/.local/share/applications/rafex-kitty.desktop` son administrados por este
script.

## Uso

```bash
just install-kitty --check
just install-kitty --plan
just install-kitty --apply
just install-kitty --update
just install-kitty --status
```

Después de aplicar, abre Kitty con:

```bash
~/.local/bin/kitty
```

Si `~/.local/bin` ya está en `PATH`, también puedes usar:

```bash
kitty
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba entorno y artefacto local; no descarga ni instala. |
| `--plan` | — | Muestra versión, origen, checksum y destinos sin modificar. |
| `--apply` | — | Usa el archivo local o descarga, verifica y publica Kitty en `~/.local`. |
| `--update` | — | Consulta el último release estable y su digest en GitHub, descarga, verifica e instala esa versión. Requiere `jq`. |
| `--status` | — | Muestra instalación, enlaces y lanzador administrados. |
| `--archive <archivo>` | — | Usa un `.txz` local explícito en lugar de buscarlo en Descargas. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_DATA_HOME` | Cambia el árbol de datos; por defecto `~/.local/share`. |
| `XDG_DOWNLOAD_DIR` | Añade un directorio de búsqueda para el artefacto local. |

No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

Forma recomendada:

```bash
just install-kitty --check
just install-kitty --plan
just install-kitty --apply
just install-kitty --update
just install-kitty --status
```

Usando un archivo previamente descargado:

```bash
just install-kitty --apply --archive ~/Downloads/kitty-0.49.1-x86_64.txz
```

Comprobación directa del binario instalado:

```bash
~/.local/bin/kitty --version
~/.local/bin/kitten --version
```

## Protecciones de seguridad

- Solo acepta Linux `x86_64`, el nombre, URL y SHA-256 fijados para `--apply`.
- `--update` acepta únicamente tags estables `vMAJOR.MINOR.PATCH` y obtiene
  el digest del artefacto correspondiente desde la API oficial de GitHub.
- Verifica el checksum, la estructura tar.xz, las rutas internas y el tipo de
  cada entrada antes de extraer.
- Rechaza rutas absolutas y rutas con `..`; solo acepta el enlace relativo
  `lib/libslang-compiler.so` si apunta a su archivo hermano esperado.
- Extrae primero en un directorio temporal privado y publica después.
- No usa `sudo`, APT, `/usr`, servicios, autostart ni comandos remotos.
- No sobrescribe un directorio, enlace o lanzador no administrado.
- Si ya existe Kitty administrado con otro checksum, se detiene sin mezclar
  instalaciones.

## Fallos conocidos

### `no se encontró kitty-0.49.1-x86_64.txz`

**Causa:** el artefacto no está en los directorios de Descargas.

**Solución:** ejecuta `--apply` con Internet disponible o proporciona
`--archive /ruta/kitty-0.49.1-x86_64.txz`.

### `SHA-256 incorrecto`

**Causa:** el archivo está incompleto, fue modificado o no corresponde al
release fijado.

**Solución:** no fuerces la instalación; consigue nuevamente el artefacto
desde el release oficial y repite `--check`.

### `el destino ya existe y no es un enlace administrado`

**Causa:** `~/.local/bin/kitty`, `~/.local/bin/kitten` o el lanzador pertenece
a otra instalación o fue creado manualmente.

**Solución:** conserva ese archivo, renómbralo de forma manual si corresponde
y vuelve a ejecutar `--apply`. El script no lo sobrescribe.

### Kitty no aparece en `PATH`

**Causa:** `~/.local/bin` no está incluido en la sesión gráfica o shell.

**Solución:** ejecuta `~/.local/bin/kitty` o añade `~/.local/bin` al `PATH` de
tu sesión; el instalador no modifica automáticamente los archivos de shell.

## Changelog

### [Unreleased]

- **feat:** añade `--update` para descubrir e instalar el último release estable
  de Kitty con el digest publicado por GitHub.

### v1.1.0 — 2026-09-24

**feat:** actualiza Kitty a `0.49.1` y permite actualizar enlaces administrados.

- Verifica el SHA-256 publicado por GitHub para el release oficial x86_64.
- Conserva las instalaciones versionadas anteriores al actualizar.
