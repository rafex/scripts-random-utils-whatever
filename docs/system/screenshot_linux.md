---
title: screenshot_linux.sh
description: Captura pantalla completa, selección o ventana activa en X11.
tags:
  - sistema
  - captura
  - x11
---

# screenshot_linux.sh

Realiza capturas locales de X11 con `maim`, las guarda como PNG y puede
copiarlas al portapapeles con `xclip`.

- **Ruta:** `scripts/system/screenshot_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `maim`, `xprop`; `slop`, `xclip` y `notify-send` son opcionales según la acción.

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

Instala el backend y los atajos con:

```bash
just install-screenshot --apply
```

La captura necesita ejecutarse dentro de la sesión X11 local. No requiere
sudo.

## Uso

```bash
just screenshot --full
just screenshot --select
just screenshot --window
```

La carpeta predeterminada es `~/Imágenes/CapturasDePantalla`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--full` | — | Captura toda la pantalla; es el modo predeterminado. |
| `--select` | `--area` | Permite seleccionar un rectángulo con el ratón mediante `slop`. |
| `--window` | `--active-window` | Captura la ventana activa publicada por el gestor X11. |
| `--copy` | `--clipboard` | Copia también el PNG al portapapeles con `xclip`. |
| `--output <archivo.png>` | `-o` | Cambia la salida; solo bajo HOME o `/tmp`. |
| `--force` | — | Permite reemplazar una salida existente. |
| `--status` | `--check` | Muestra dependencias y DISPLAY sin capturar. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_PICTURES_DIR` | `~/Imágenes` | Base para el directorio de capturas. |
| `DISPLAY` | el de la sesión | Servidor X11 que se capturará. |
| `TMPDIR` | `/tmp` | Solo se usa como base si la herramienta necesita temporales. |

## Ejemplos

```bash
just screenshot --full
just screenshot --select --copy
just screenshot --window --output /tmp/ventana.png
just screenshot --status
```

## Protecciones de seguridad

- El helper no ejecuta sudo y no inicia procesos de captura de red.
- Solo escribe bajo `HOME` o `/tmp`, rechaza enlaces simbólicos y no sobrescribe
  salidas sin `--force`.
- La imagen se produce en un temporal y se mueve al destino solo tras
  completarse correctamente.
- Una captura puede contener información confidencial. Revisa el PNG y el
  portapapeles antes de compartirlo.

## Fallos conocidos

### `maim no produjo una imagen`

**Causa:** se canceló una selección, la sesión no permite capturar o el
servidor X11 no respondió.

**Solución:** prueba `just screenshot --full`, verifica `DISPLAY` y repite la
selección desde la sesión gráfica local.

### `la salida ya existe`

**Causa:** el helper protege los archivos existentes.

**Solución:** usa otro nombre o `--force` de forma explícita.

## Changelog

### [Unreleased]

- **feat:** añadir helper de capturas X11 con salida segura y copia opcional.
