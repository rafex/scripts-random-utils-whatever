---
title: install_xonotic_linux.sh
description: Instala Xonotic verificado en la cuenta del usuario
tags:
  - instalación
  - juegos
---

# install_xonotic_linux.sh

Instala Xonotic 0.8.6 desde el ZIP oficial en `~/Games/Xonotic`, sin ejecutar el juego como root.

- **Ruta:** `scripts/install/install_xonotic_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `unzip`, `zipinfo`, `sha512sum`, `file`, `ldd`, `apt-get`, `sudo` solo para dependencias

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

- Debian `amd64` con una sesión gráfica X11 para validar OpenGL.
- Xonotic 0.8.6 requiere OpenGL compatible y bibliotecas SDL2, Vorbis, cURL y PNG.
- El archivo local esperado es `xonotic-0.8.6.zip`.

La suma SHA-512 oficial fijada es:

```text
cb39879e96f19abb2877588c2d50c5d3e64dd68153bec3dd1bebedf4d765e506afa419c28381d7005aed664cb1a042571c132b5b319e4308cab67745d996c2a6
```

## Uso

El instalador busca primero en `~/Descargas`, `~/Downloads` y el directorio devuelto por `xdg-user-dir DOWNLOAD`. Si no encuentra el ZIP, `--apply` lo descarga desde `https://dl.xonotic.org/xonotic-0.8.6.zip`.

El destino de juego es `~/Games/Xonotic`. También se crean `~/.local/bin/xonotic` y una entrada `.desktop` local.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Verifica entorno, ZIP local, checksum y dependencias sin escribir. |
| `--plan` | `--dry-run` | Muestra el plan sin descargar, instalar ni publicar. |
| `--apply` | — | Descarga si hace falta, instala dependencias y publica el juego. |
| `--upgrade` | — | Permite reemplazar una instalación administrada con respaldo. |
| `--archive <archivo>` | — | Usa un ZIP local explícito. |
| `--status` | — | Muestra versión, instalación, dependencias y OpenGL. |
| `--rollback` | — | Restaura el último respaldo de una actualización administrada. |

## Variables de entorno

No requiere variables de entorno. `--archive` tiene prioridad sobre la búsqueda en Descargas.

## Ejemplos

Forma explícita recomendada:

```bash
just install-xonotic --check
just install-xonotic --plan
just install-xonotic --apply
just install-xonotic --status
```

Usando un archivo específico:

```bash
just install-xonotic --apply --archive ~/Descargas/xonotic-0.8.6.zip
```

Actualizar una instalación administrada:

```bash
just install-xonotic --apply --upgrade
```

Rollback:

```bash
just install-xonotic --rollback
```

## Protecciones de seguridad

- Solo acepta el nombre, versión y checksum fijados.
- Rechaza rutas absolutas, `..`, separadores inversos, symlinks y archivos especiales dentro del ZIP.
- No sobrescribe una carpeta o lanzador no administrado.
- Extrae en un directorio temporal y publica atómicamente.
- `sudo` se utiliza exclusivamente para dependencias APT.
- No instala Vulkan, no crea servicios y no inicia el juego automáticamente.
- Las configuraciones del juego quedan fuera del repositorio de configuraciones ThinkPad.

## Fallos conocidos

### `checksum sha512 incorrecto`

**Causa:** el ZIP está incompleto, fue alterado o corresponde a otra versión.

**Solución:** elimina únicamente el archivo descargado incorrecto y proporciona el ZIP oficial 0.8.6; no fuerces la instalación.

### `dependencias faltantes`

**Causa:** el sistema no tiene alguna biblioteca gráfica o de audio requerida.

**Solución:** ejecuta `just install-xonotic --apply` para instalar los candidatos Debian detectados y repite `--status`.

### `opengl=pendiente`

**Causa:** el comando se ejecutó fuera de una sesión gráfica o sin `DISPLAY`.

**Solución:** ejecuta `--status` desde i3/Openbox con X11 activo.

## Changelog

### [Unreleased]
- Nueva instalación verificable y rootless de Xonotic 0.8.6.

