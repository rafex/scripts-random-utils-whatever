---
title: screensaver_toggle_linux.sh
description: Control de protector de pantalla y DPMS
tags:
  - hardware
---

# screensaver_toggle_linux.sh

Activa o desactiva la espera de inactividad del protector de pantalla (X11). Opera sobre `xset` — Screen Saver + DPMS. No bloquea la pantalla inmediatamente: solo controla si el protector se activará tras N segundos sin actividad.

- **Ruta:** `scripts/hardware/screensaver_toggle_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** `xset`, `notify-send` (opcional para notificaciones)

______________________________________________________________________

## Uso

```sh
./scripts/hardware/screensaver_toggle_linux.sh <on|off|toggle|status> [opciones]
```

## Opciones

| Opción | Descripción |
|---|---|
| `on` | Activa la espera de inactividad (restaura xset s + dpms) |
| `off` | Desactiva la espera de inactividad (xset s off + xset -dpms) |
| `toggle` | Alterna entre on/off según el estado actual |
| `status` | Muestra el estado actual del protector |
| `--timeout <s>` | Segundos de inactividad antes del protector |
| `--display <d>` | DISPLAY X a usar (default: `:0` o `$DISPLAY`) |
| `--dry-run` | Muestra los comandos sin ejecutarlos |
| `-h, --help` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SS_TIMEOUT` | `600` | Tiempo de inactividad en segundos para que se active el protector |
| `SS_CYCLE` | `600` | Ciclo del Screen Saver |
| `SS_DPMS_S` | `600` | DPMS Standby en segundos |
| `SS_DPMS_M` | `600` | DPMS Suspend en segundos |
| `SS_DPMS_O` | `600` | DPMS Off en segundos |
| `SS_DRY_RUN` | `0` | Si es `1`, modo simulación (no ejecuta comandos) |

## Archivo de configuración

Al ejecutar `on`, el script persiste el timeout en `~/.config/screensaver-toggle.conf`:

```
SS_TIMEOUT=600
SS_CYCLE=600
SS_DPMS_S=600
SS_DPMS_M=600
SS_DPMS_O=600
```

Este archivo se lee automáticamente al iniciar el script, por lo que comandos posteriores
(como `toggle`) respetan el timeout guardado.

## Ejemplos

```sh
# Desactivar la espera de inactividad
./scripts/hardware/screensaver_toggle_linux.sh off

# Activar con timeout de 10 min (default)
./scripts/hardware/screensaver_toggle_linux.sh on

# Activar con 5 min de espera
./scripts/hardware/screensaver_toggle_linux.sh on --timeout 300

# Alternar entre on/off
./scripts/hardware/screensaver_toggle_linux.sh toggle

# Consultar estado actual
./scripts/hardware/screensaver_toggle_linux.sh status

# Usar un display X específico
./scripts/hardware/screensaver_toggle_linux.sh on --display :1

# Simular (sin ejecutar nada)
./scripts/hardware/screensaver_toggle_linux.sh on --dry-run

# Con variables de entorno
SS_TIMEOUT=300 ./scripts/hardware/screensaver_toggle_linux.sh on
```

### Forma recomendada (instalado en PATH)

Una vez copiado a `~/.local/bin/screensaver-toggle`:

```sh
screensaver-toggle off    # desactivar
screensaver-toggle on     # activar
screensaver-toggle toggle # alternar
screensaver-toggle status # consultar
```

______________________________________________________________________

## Fallos conocidos

### `xset: unable to open display ":0"`

**Causa:** El script se ejecutó desde una TTY o sesión SSH sin variable `DISPLAY` correcta.
**Solución:** Usa `--display :0` o asegúrate de que `$DISPLAY` apunte a la sesión X activa.

### `xset: unknown option`

**Causa:** `xset` no está instalado o la versión es muy antigua.
**Solución:** Instalar `x11-xserver-utils`: `sudo apt install x11-xserver-utils`.

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-07-31

**feat:** Script inicial para alternar protector de pantalla en X11.

- Subcomandos: `on`, `off`, `toggle`, `status`
- Control de xset Screen Saver + DPMS
- Notificaciones con `notify-send`
- Configuración persistente en `~/.config/screensaver-toggle.conf`
- Timeout configurable por flag o variable de entorno
- Modo `--dry-run`
