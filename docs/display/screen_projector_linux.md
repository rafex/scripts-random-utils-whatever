---
title: screen_projector_linux.sh
description: Control seguro de pantalla interna, monitor externo y proyector en Xorg
tags:
  - pantallas
  - proyector
---

# screen_projector_linux.sh

Controla la pantalla interna y el primer monitor externo conectado. Está pensado
para la tecla de proyector de la ThinkPad y no requiere `sudo`.

- **Ruta:** `scripts/display/screen_projector_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `flock`, `notify-send` opcional

______________________________________________________________________

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

Debe ejecutarse desde una sesión gráfica Xorg de i3 con `DISPLAY` disponible.
Los nombres de salida se detectan con `xrandr`; no se asumen `LVDS1` ni `HDMI1`.

## Uso

```sh
~/.local/bin/screen-projector.sh --mode next
~/.local/bin/screen-projector.sh --check
```

En el perfil ThinkPad, `XF86Display` ejecuta `--mode next` y recorre:
`internal → extend → mirror → internal`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | `--status` | Muestra salidas y estado sin cambiar Xorg. |
| `--plan` | `--dry-run` | Muestra el `xrandr` previsto sin aplicarlo. |
| `--apply` | — | Aplica el modo solicitado y guarda el estado. |
| `--mode internal` | — | Deja activa solo la pantalla interna. |
| `--mode extend` | — | Coloca el externo a la derecha. |
| `--mode mirror` | — | Duplica la pantalla interna; escala si los modos difieren. |
| `--mode next` | — | Cicla el modo para la tecla de proyector. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SCREEN_INTERNAL` | Detección `eDP`, `LVDS` o `DSI` | Fija la salida interna. |
| `SCREEN_EXTERNAL` | Primer `HDMI`, `DP`, `DVI`, `VGA`, `DisplayPort` o `USB-C` | Fija la salida externa. |
| `XDG_STATE_HOME` | `~/.local/state` | Directorio del estado y lock del controlador. |

Prioridad: opciones CLI, después variables de entorno y finalmente detección
automática. Los archivos de estado solo recuerdan el último modo elegido.

## Ejemplos

### Forma explícita recomendada

```sh
~/.local/bin/screen-projector.sh --apply --mode extend
```

### Ciclo de la tecla de proyector

```sh
~/.local/bin/screen-projector.sh --apply --mode next
```

### Validar nombres reales de salidas

```sh
~/.local/bin/screen-projector.sh --check
```

### Fijar un adaptador concreto

```sh
SCREEN_INTERNAL=eDP-1 SCREEN_EXTERNAL=HDMI-1 \
  ~/.local/bin/screen-projector.sh --apply --mode mirror
```

## Protecciones de seguridad

- No usa `sudo`, no modifica `xorg.conf`, `fstab`, GRUB ni particiones.
- Usa `flock` para impedir dos cambios simultáneos.
- Solo apaga otras salidas conectadas al cambiar de modo; no toca dispositivos
  de entrada ni servicios del sistema.
- Mantiene un estado por usuario, no una configuración global.

## Fallos conocidos

### `Can't open display`

**Causa:** se ejecutó desde SSH sin la sesión Xorg local.
**Solución:** ejecutarlo desde Alacritty/i3 o proporcionar correctamente la
sesión X; la tecla de proyector ya se ejecuta dentro de i3.

### El espejo falla con modos distintos

**Causa:** el proyector no ofrece la resolución de la pantalla interna.
**Solución:** el script intenta `--scale-from`; si el adaptador no lo admite,
usa `--mode extend` o fija manualmente una resolución común con `xrandr`.

### `XF86Display` no aparece al pulsar Fn

**Causa:** firmware o mapa de teclado publica otro keysym.
**Solución:** comprobarlo en la sesión gráfica con `xev -event keyboard` y
añadir el keysym real al perfil i3.

## Changelog

### [Unreleased]

**feat:** controlador unificado para tecla de proyector, espejo y extensión.

- Detección dinámica de salidas ThinkPad.
- Compatibilidad con los nombres históricos `screen-*.sh`.
