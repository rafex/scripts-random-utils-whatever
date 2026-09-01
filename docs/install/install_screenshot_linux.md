---
title: install_screenshot_linux.sh
description: Instala y registra capturas X11 de pantalla completa, selección y ventana activa.
tags:
  - instalación
  - captura
  - thinkpad
---

# install_screenshot_linux.sh

Instala el backend `maim` y configura atajos de captura para i3 y Openbox.
Las imágenes se guardan en `~/Imágenes/CapturasDePantalla` y opcionalmente se
copian al portapapeles.

- **Ruta:** `scripts/install/install_screenshot_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `maim`, `slop`, `xclip`, `xprop`, `notify-send`; `sudo` solo durante `--apply`.

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

- Debian con candidatos APT para `maim`, `slop`, `xclip`, `x11-utils` y
  `libnotify-bin`.
- Una sesión X11 activa con `DISPLAY` definido.
- Ejecutar el instalador como usuario normal. La captura nunca requiere sudo.

## Uso

```bash
just install-screenshot --check
just install-screenshot --plan
just install-screenshot --apply
just install-screenshot --status
```

Atajos instalados:

| Atajo | Acción |
|---|---|
| `Mod+P` o `Print` | Pantalla completa |
| `Shift+Print` | Selección rectangular con el ratón |
| `Ctrl+Print` | Ventana activa |

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba los paquetes, helper y bloques sin escribir. |
| `--plan` | `--dry-run` | Muestra la instalación e integración previstas. |
| `--apply` | — | Instala dependencias, copia el helper y actualiza i3/Openbox. |
| `--status` | — | Muestra paquetes, rutas y atajos administrados. |
| `--help` | `-h` | Muestra la ayuda. |

El helper `screenshot.sh` admite `--full`, `--select`, `--window`, `--copy`,
`--output`, `--force`, `--status` y `--check`.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_PICTURES_DIR` | `~/Imágenes` | Directorio base para la carpeta de capturas. |
| `I3_CONFIG` | `~/.config/i3/config` | Configuración i3 a actualizar. |
| `OPENBOX_RC` | `~/.config/openbox/rc.xml` | Configuración Openbox a actualizar. |

No se leen archivos `.env` ni se guardan credenciales.

## Ejemplos

### Captura de pantalla completa

```bash
just screenshot --full
just screenshot --full --copy
```

### Selección y ventana activa

```bash
just screenshot --select
just screenshot --window --copy
```

### Salida explícita

```bash
just screenshot --select --output /tmp/seleccion.png
just screenshot --full --output ~/Imágenes/CapturasDePantalla/clase.png --force
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no capturan ni modifican archivos.
- El helper solo escribe bajo `HOME` o `/tmp` y rechaza enlaces simbólicos de
  salida.
- La salida se genera en un archivo temporal y se mueve atómicamente al
  finalizar la captura.
- No usa sudo, no inicia capturas de red y no accede a dispositivos internos.
- La captura de una pantalla puede incluir contraseñas, documentos o datos de
  terceros; revisa el contenido antes de compartirla.
- El instalador elimina el binding antiguo de `maim` antes de añadir su bloque
  administrado y respalda la configuración antes de cambiarla.

## Fallos conocidos

### `no existe DISPLAY`

**Causa:** se ejecutó desde SSH sin reenviar una sesión X11 real o desde una
terminal virtual.

**Solución:** ejecuta el helper dentro de i3/Openbox en la ThinkPad. `ssh -X`
  muestra el X local del cliente, no convierte la sesión remota en la pantalla
  física de la laptop.

### `no se pudo identificar la ventana activa`

**Causa:** el gestor de ventanas no publicó `_NET_ACTIVE_WINDOW` o no hay una
ventana activa.

**Solución:** usa `--full` o selecciona una ventana normal antes de repetir
`--window`.

### Se canceló la selección

**Causa:** se cerró `slop` o se pulsó Escape.

**Solución:** repite `just screenshot --select`; no se conserva un archivo
parcial.

## Changelog

### [Unreleased]

- **feat:** añadir capturas X11 completas, por selección y de ventana activa.
