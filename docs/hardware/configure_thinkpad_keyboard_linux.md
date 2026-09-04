---
title: configure_thinkpad_keyboard_linux.sh
description: Configura el teclado latinoamericano de Debian, i3 y Openbox
tags:
  - hardware
  - teclado
  - thinkpad
---

# configure_thinkpad_keyboard_linux.sh

Configura `pc105` y español latinoamericano (`latam`), sin variante ni opciones
adicionales, en el sistema y las sesiones i3/Openbox del usuario.

- **Ruta:** `scripts/hardware/configure_thinkpad_keyboard_linux.sh`
- **SO requerido:** Linux (Debian, X11)
- **Dependencias:** Bash, Python 3, sudo, i3 si su configuración cambia, sh,
  setxkbmap (x11-xkb-utils) para aplicar en una sesión gráfica

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

Ejecutar como usuario normal en Debian. Las configuraciones i3/Openbox ausentes
se omiten. No instala paquetes. El idioma `es_MX.UTF-8` es independiente del
teclado y no se modifica.

## Uso

```bash
just configure-thinkpad-keyboard --check
just configure-thinkpad-keyboard --plan
just configure-thinkpad-keyboard --apply
just configure-thinkpad-keyboard --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Predeterminado; lectura, retorna 1 si requiere ajustes persistentes |
| `--plan` | — | Describe ajustes sin escribir ni solicitar sudo |
| `--status` | — | Reporta configuración persistente y consulta X11 cuando está disponible |
| `--apply` | — | Guarda respaldos, configura sistema y sesiones, aplica a X11 si existe DISPLAY |
| `--help` | `-h` | Ayuda |

## Variables de entorno

| Variable | Uso |
|---|---|
| `HOME` | Directorio del usuario normal que ejecuta el script |
| `XDG_CONFIG_HOME` | Directorio de configuraciones; prioridad sobre `$HOME/.config` |
| `DISPLAY` | Sesión gráfica a consultar o configurar; sin ella solo aplica persistencia |
| `XAUTHORITY` | Autorización de X11, gestionada por setxkbmap |

## Ejemplos

Uso explícito:

```bash
bash scripts/hardware/configure_thinkpad_keyboard_linux.sh --apply
```

Desde SSH, con autorización de la sesión gráfica del usuario:

```bash
DISPLAY=:0 XAUTHORITY="$HOME/.Xauthority" just configure-thinkpad-keyboard --apply
```

Los comandos históricos `setxkbmap es` y `setxkbmap -layout latam` se migran.
No admite archivos `.env`.

## Protecciones de seguridad

Solo usa sudo para respaldar y configurar `/etc/default/keyboard`.
Conserva las demás directivas de ese archivo y los permisos de los archivos
del usuario. Valida i3 y sintaxis de autostart antes de escribir. Rechaza enlaces
simbólicos y comandos setxkbmap personalizados que no puede migrar con certeza.
Las copias tienen sufijo `.bak-latam-FECHA`; repetir la aplicación no crea copias
si el contenido ya coincide. Una falla durante las escrituras puede dejar cambios
parciales: restaurar los respaldos indicados si fuera necesario.

No recarga todo i3/Openbox ni ejecuta sus autostarts. La consola de texto se
actualiza en el siguiente arranque. No reinicia automáticamente.

## Fallos conocidos

### La sesión cambia a español de España

**Causa:** los perfiles antiguos ejecutaban `setxkbmap es`, aunque Debian usaba `latam`.
**Solución:** aplicar el script para migrar las dos configuraciones de sesión.

### Comando setxkbmap personalizado

**Causa:** hay opciones no reconocidas en los archivos del usuario.
**Solución:** revisar el comando indicado antes de repetir la aplicación.

### No puede abrir DISPLAY

**Causa:** no existe acceso a la sesión X11 indicada.
**Solución:** ejecutar desde una terminal gráfica o proporcionar DISPLAY y
XAUTHORITY correctos. Para preparar solo la persistencia, ejecutar sin DISPLAY.

## Changelog

### v1.0.0 — 2026-09-04

**feat:** configuración reproducible de teclado pc105/latam con diagnóstico,
respaldo y migración de i3/Openbox.
