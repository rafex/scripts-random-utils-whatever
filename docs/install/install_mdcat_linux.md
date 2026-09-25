---
title: install_mdcat_linux.sh
description: Instala mdcat x86_64 desde el release oficial en el espacio del usuario.
tags:
  - instalación
  - markdown
  - thinkpad
---

# install_mdcat_linux.sh

Instala `mdcat` para leer archivos Markdown en la terminal de una ThinkPad
Linux x86_64. Descarga el release oficial, valida su checksum BLAKE2b-512 y lo
instala en `~/.local` sin privilegios de administrador.

- **Ruta:** `scripts/install/install_mdcat_linux.sh`
- **SO requerido:** Linux x86_64
- **Dependencias:** `bash`, `curl`, `tar`, `b2sum`, `install`

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

Pensado para ThinkPad con Linux x86_64 y conexión HTTPS. No requiere Rust,
`sudo` ni una distribución específica. El release se fija en `mdcat 2.7.1`.

## Uso

```bash
just install-mdcat --check
just install-mdcat --plan
just install-mdcat --apply
just install-mdcat --status
```

Después de instalarlo, úsalo para mostrar Markdown:

```bash
mdcat README.md
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba plataforma, dependencias y estado instalado. |
| `--plan` | — | Muestra release y rutas sin modificar archivos. |
| `--apply` | — | Descarga, verifica e instala `mdcat` en `~/.local`. |
| `--status` | — | Muestra versión instalada y destino del enlace. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `HOME` | Determina `~/.local/bin` y, por defecto, el directorio de datos. |
| `XDG_DATA_HOME` | Cambia la raíz de datos; por defecto `~/.local/share`. |
| `TMPDIR` | Cambia dónde se preparan las descargas temporales. |
| `PATH` | Se consulta para avisar si `~/.local/bin` no está disponible. |

No se leen argumentos de configuración ni archivos `.env`.

## Ejemplos

Forma recomendada:

```bash
just install-mdcat --check
just install-mdcat --plan
just install-mdcat --apply
```

Invocación directa:

```bash
bash scripts/install/install_mdcat_linux.sh --apply
```

Con un directorio de datos XDG personalizado:

```bash
XDG_DATA_HOME="$HOME/.local/share" just install-mdcat --apply
```

## Protecciones de seguridad

- Solo admite Linux x86_64 y usa el release fijado `mdcat 2.7.1` de `swsnr/mdcat`.
- Descarga únicamente por HTTPS y compara el artefacto con `B2SUMS.txt` oficial.
- Instala bajo el directorio del usuario; no ejecuta `sudo`, APT ni servicios.
- Conserva archivos y enlaces existentes que no administra. Rechaza un destino
  de versión ya existente para evitar sobrescribirlo.

## Fallos conocidos

### `este instalador requiere Linux` o `mdcat está configurado para ThinkPad x86_64`

**Causa:** el sistema o la arquitectura no coincide con el binario publicado.

**Solución:** ejecútalo en Linux x86_64; el script no instala en macOS ni ARM.

### `BLAKE2b-512 incorrecto; se cancela la instalación`

**Causa:** la descarga está incompleta o no coincide con el checksum publicado.

**Solución:** vuelve a intentar con conexión HTTPS estable. No fuerces la
instalación del archivo descargado.

### `~/.local/bin` no está en PATH

**Causa:** el directorio local de ejecutables no está incluido en el entorno.

**Solución:** ejecuta `~/.local/bin/mdcat` o añade `~/.local/bin` al `PATH` de
la shell.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.0.0 — 2026-09-25

**feat:** añade instalador local de mdcat para ThinkPad Linux x86_64.

- Verifica el checksum BLAKE2b-512 del release oficial.
- Añade modos de comprobación, plan, instalación y estado.
