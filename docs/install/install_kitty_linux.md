---
title: install_kitty_linux.sh
description: Instala Kitty x86_64 desde el release oficial en el espacio del usuario.
tags:
  - instalación
  - kitty
  - terminal
---

# install_kitty_linux.sh

Instala Kitty `0.48.2` para la ThinkPad desde el artefacto Linux x86_64 del
release oficial de GitHub. No reemplaza el paquete Debian, no requiere `sudo`
y no inicia el terminal automáticamente.

- **Ruta:** `scripts/install/install_kitty_linux.sh`
- **SO requerido:** Linux (Debian, x86_64)
- **Dependencias:** `bash`, `curl`, `sha256sum`, `tar` con soporte xz, `file`, `stat`

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
kitty-0.48.2-x86_64.txz
https://github.com/kovidgoyal/kitty/releases/download/v0.48.2/kitty-0.48.2-x86_64.txz
SHA-256: 967a1958e7fc67b495d279c0963bcd1a0482097151817ce6506fabc822689af7
```

La instalación queda bajo `~/.local/share/rafex/kitty/0.48.2`. Los enlaces
`~/.local/bin/kitty`, `~/.local/bin/kitten` y el lanzador
`~/.local/share/applications/rafex-kitty.desktop` son administrados por este
script.

## Uso

```bash
just install-kitty --check
just install-kitty --plan
just install-kitty --apply
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
just install-kitty --status
```

Usando un archivo previamente descargado:

```bash
just install-kitty --apply --archive ~/Downloads/kitty-0.48.2-x86_64.txz
```

Comprobación directa del binario instalado:

```bash
~/.local/bin/kitty --version
~/.local/bin/kitten --version
```

## Protecciones de seguridad

- Solo acepta Linux `x86_64`, el nombre, URL y SHA-256 fijados.
- Verifica el checksum, la estructura tar.xz, las rutas internas y el tipo de
  cada entrada antes de extraer.
- Rechaza symlinks, nodos especiales, rutas absolutas y rutas con `..` dentro
  del artefacto.
- Extrae primero en un directorio temporal privado y publica después.
- No usa `sudo`, APT, `/usr`, servicios, autostart ni comandos remotos.
- No sobrescribe un directorio, enlace o lanzador no administrado.
- Si ya existe Kitty administrado con otro checksum, se detiene sin mezclar
  instalaciones.

## Fallos conocidos

### `no se encontró kitty-0.48.2-x86_64.txz`

**Causa:** el artefacto no está en los directorios de Descargas.

**Solución:** ejecuta `--apply` con Internet disponible o proporciona
`--archive /ruta/kitty-0.48.2-x86_64.txz`.

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

- **feat:** instalación rootless y verificable de Kitty `0.48.2` para Linux
  x86_64 desde el release oficial.
