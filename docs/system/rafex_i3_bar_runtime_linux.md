---
title: rafex_i3_bar_runtime_linux.sh
description: Mantiene una única instancia administrada de Tint2 o Polybar en i3.
tags:
  - sistema
  - i3
  - tint2
  - polybar
---

# rafex_i3_bar_runtime_linux.sh

Runtime rootless utilizado por i3 para iniciar, detener y recargar las barras
externas del perfil Rafex.

- **Ruta:** `scripts/system/rafex_i3_bar_runtime_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `flock`, `pgrep`, `ps`; opcionales `tint2` y `polybar`.

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

Debe ejecutarse dentro de una sesión X11 con `DISPLAY`. El runtime es llamado
por `rafex-bar-active.conf`; no debe iniciarse como root.

## Uso

```bash
~/.local/bin/rafex-i3-bar-runtime.sh --sync tint2
~/.local/bin/rafex-i3-bar-runtime.sh --sync polybar
~/.local/bin/rafex-i3-bar-runtime.sh --sync i3bar
~/.local/bin/rafex-i3-bar-runtime.sh --reload
~/.local/bin/rafex-i3-bar-runtime.sh --stop
~/.local/bin/rafex-i3-bar-runtime.sh --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--sync <perfil>` | — | Detiene la barra externa opuesta e inicia/adopta la elegida. |
| `--reload` | — | Recarga la barra externa del perfil seleccionado. |
| `--stop` | — | Detiene solo los procesos registrados por Rafex. |
| `--status` | — | Muestra estado sin requerir `DISPLAY`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Ubicación de las configuraciones de barra. |
| `XDG_RUNTIME_DIR` | `/run/user/$UID` | Ubicación de lock y PID files. |
| `DISPLAY` | — | Pantalla X11 requerida para iniciar o recargar. |

No se usan archivos `.env`.

## Ejemplos

```bash
just i3-bar --set tint2
just i3-bar --status
just i3-bar --set polybar
just i3-bar --set i3bar
```

## Protecciones de seguridad

- Usa `flock` para evitar dos operaciones simultáneas.
- Registra PID files privados con permisos `0700`.
- Verifica que la línea de comandos del PID contenga la configuración esperada.
- Adopta como máximo una instancia que use la configuración Rafex; si hay varias, se detiene.
- El descriptor del lock no se hereda a Tint2 ni Polybar, para que las recargas
  posteriores no queden bloqueadas por la propia barra.
- Nunca mata procesos por nombre global ni usa sudo.
- No administra i3bar, porque i3 lo inicia y controla nativamente.

## Fallos conocidos

### `DISPLAY no está disponible`

**Causa:** se ejecutó el runtime desde una TTY, SSH sin entorno X11 o antes de iniciar sesión.

**Solución:** usa `just i3-bar` dentro de la sesión gráfica o aplica el cambio en la próxima sesión.

### `hay varias instancias externas usando una configuración Rafex`

**Causa:** una ejecución anterior dejó más de una instancia con la configuración administrada.

**Solución:** inspecciona `ps`, cierra manualmente la instancia duplicada y repite `--status`.

## Changelog

### [Unreleased]

- **feat:** añadir runtime idempotente con lock y PID files para barras externas de i3.
- **fix:** cerrar el descriptor del lock en los procesos hijos de Tint2 y
  Polybar.
