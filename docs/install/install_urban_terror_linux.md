---
title: install_urban_terror_linux.sh
description: Instala Urban Terror verificado en la cuenta del usuario
tags:
  - instalación
  - juegos
---

# install_urban_terror_linux.sh

Instala Urban Terror 4.3.4 desde el ZIP publicado por la página oficial en `~/Games/UrbanTerror`.

- **Ruta:** `scripts/install/install_urban_terror_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `unzip`, `zipinfo`, `md5sum`, `file`, `ldd`, `apt-get`, `sudo` solo para dependencias

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

- Debian `amd64`.
- Una sesión X11 con OpenGL para jugar.
- El archivo local esperado es `UrbanTerror434_full.zip`.

La página oficial publica para este archivo el MD5:

```text
9bf7f0092161391697d24f6b004a6c6b
```

La URL HTTPS usada es el mirror publicado por la página oficial: `https://mirror2.urbanterror.info/UrbanTerror434_full.zip`.

## Uso

El instalador busca primero en `~/Descargas`, `~/Downloads` y el directorio devuelto por `xdg-user-dir DOWNLOAD`. Si no encuentra el ZIP, `--apply` descarga la versión fijada desde la URL oficial publicada.

El ejecutable utilizado es `UrbanTerror43/Quake3-UrT.x86_64`. Se crean `~/.local/bin/urban-terror` y una entrada `.desktop` local.

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
just install-urban-terror --check
just install-urban-terror --plan
just install-urban-terror --apply
just install-urban-terror --status
```

Usando el ZIP ya descargado:

```bash
just install-urban-terror --apply --archive ~/Descargas/UrbanTerror434_full.zip
```

Actualizar una instalación administrada:

```bash
just install-urban-terror --apply --upgrade
```

Rollback:

```bash
just install-urban-terror --rollback
```

## Protecciones de seguridad

- Solo acepta el nombre, versión, raíz y MD5 fijados.
- Rechaza rutas absolutas, `..`, separadores inversos, symlinks y archivos especiales dentro del ZIP.
- No sobrescribe una carpeta o lanzador no administrado.
- Extrae en un directorio temporal y publica atómicamente.
- `sudo` se utiliza exclusivamente para dependencias APT.
- No ejecuta el updater con privilegios ni instala el binario i386.
- No inicia el juego automáticamente.

## Fallos conocidos

### `checksum md5 incorrecto`

**Causa:** el archivo no coincide con el ZIP oficial 4.3.4 o está incompleto.

**Solución:** proporciona el archivo oficial y repite `--check`; no fuerces la instalación.

### `dependencias faltantes`

**Causa:** falta alguna biblioteca gráfica o de audio del runtime Debian.

**Solución:** ejecuta `just install-urban-terror --apply` para instalar los candidatos detectados y revisa `--status`.

### `la instalación existente no está administrada`

**Causa:** ya existe `~/Games/UrbanTerror`, pero no fue creada por este instalador.

**Solución:** conserva esa instalación y elige otra ubicación manualmente solo después de modificar explícitamente el instalador; no se sobrescribe automáticamente.

## Changelog

### [Unreleased]
- Nueva instalación verificable y rootless de Urban Terror 4.3.4.

