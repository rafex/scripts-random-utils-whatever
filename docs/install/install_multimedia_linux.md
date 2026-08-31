---
title: install_multimedia_linux.sh
description: Instala FFmpeg, codecs x264/x265, mpv, VLC y plugins GStreamer en Debian.
tags:
  - instalación
  - multimedia
  - thinkpad
---

# install_multimedia_linux.sh

Instala reproducción, codificación y plugins multimedia desde Debian. Incluye
FFmpeg con codecs adicionales, x264/x265, mpv, VLC y GStreamer para PipeWire.

- **Ruta:** `scripts/install/install_multimedia_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query; sudo solo durante `--apply`.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian con candidatos APT para los codecs y plugins seleccionados.
- PipeWire puede continuar instalado y administrado por el perfil; este script
  no reinicia ni reemplaza el servidor de audio.

## Uso

```bash
just install-multimedia --check
just install-multimedia --plan
just install-multimedia --apply
just install-multimedia --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Consulta paquetes y reproductores. |
| `--plan` | `--dry-run` | Muestra la instalación prevista. |
| `--apply` | — | Instala codecs, reproductores y plugins. |
| `--status` | — | Muestra el estado actual. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración.

## Ejemplos

```bash
just install-multimedia --apply
ffmpeg -hide_banner -codecs | grep -E '264|265|opus|vorbis'
mpv video.mp4
```

## Fallos conocidos

### `algún paquete multimedia no tiene candidato APT`

**Causa:** una fuente Debian no ofrece el paquete para la distribución activa.

**Solución:** revisa candidatos con `apt-cache policy`, habilita únicamente
fuentes Debian válidas y vuelve a ejecutar `--apply`.

## Changelog

### [Unreleased]

- **feat:** añadir multimedia reproducible con FFmpeg, VLC, mpv y GStreamer.
