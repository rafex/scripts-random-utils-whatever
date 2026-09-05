---
title: picom_debian_linux.sh
description: Usa el Picom de Debian con la configuración visual Rafex sin compilar upstream.
tags:
  - sistema
  - picom
  - i3
---

# picom_debian_linux.sh

Materializa la configuración y los shaders versionados del perfil ThinkPad y
ejecuta exclusivamente `/usr/bin/picom`. No compila Picom, no instala paquetes
y no reemplaza el binario administrado por Debian.

- **Ruta:** `scripts/system/picom_debian_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `picom` en `/usr/bin/picom`, `pgrep`, `ps` y el helper `picom_toggle_linux.sh`.

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

Ejecutar como usuario normal dentro del checkout del repositorio. La
configuración se toma de:

```text
dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/picom.conf
dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/shaders/
```

Los destinos son `~/.config/picom/picom.conf` y
`~/.config/picom/shaders/`. La configuración usa GLX, transparencia moderada,
blur y sombras pequeñas; Conky, EWW, barras y ventanas de escritorio quedan
excluidos según las reglas del perfil.

## Uso

```bash
just picom-debian --check
just picom-debian --plan
just picom-debian --apply
just picom-debian --status
just picom-debian --reload
```

Después de `--apply`, `--reload` detiene la instancia actual y vuelve a iniciar
`/usr/bin/picom` con la configuración administrada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el binario Debian, las fuentes y los destinos sin escribir. |
| `--plan` | — | Muestra los archivos y comandos previstos sin escribir. |
| `--apply` | — | Copia de forma atómica la configuración y los cinco shaders; crea respaldos fechados si cambian. |
| `--status` | — | Muestra versión, archivos, shaders e instancia activa. |
| `--enable` | — | Inicia Picom usando `/usr/bin/picom` y `~/.config/picom/picom.conf`. |
| `--disable` | — | Detiene Picom y desactiva la preferencia de autoinicio de Openbox. |
| `--toggle` | — | Alterna Picom usando el binario Debian. |
| `--reload` | — | Detiene y vuelve a iniciar Picom para cargar la configuración actual. |
| `--replace-unmanaged` | — | Permite a `--apply` reemplazar un destino no administrado, conservando antes un respaldo fechado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio base de la configuración del usuario. |

El binario no se puede sustituir mediante `PICOM_BIN`: esta tarea está
diseñada para garantizar el uso de `/usr/bin/picom` de Debian.

## Ejemplos

```bash
# Flujo recomendado sin compilar upstream.
just picom-debian --check
just picom-debian --plan
just picom-debian --apply
just picom-debian --reload

# Revisar el origen usado y el estado de la instancia.
just picom-debian --status

# Recuperación rápida si GLX o blur producen artefactos.
just picom-debian --disable

# Migrar una configuración manual existente después de revisar el plan.
just picom-debian --apply --replace-unmanaged
just picom-debian --reload
```

## Protecciones de seguridad

- Solo `--apply` modifica `~/.config/picom`; no requiere `sudo`.
- `--check`, `--plan` y `--status` son de solo lectura.
- El helper rechaza ejecución como root.
- No modifica `/usr/bin/picom`, APT, i3, Openbox, Xorg, GRUB ni servicios del sistema.
- No sobrescribe una configuración no administrada: si un destino diferente no
  contiene el marcador del perfil ni coincide con la fuente versionada, se
  detiene.
- Para migrar una configuración manual existente se requiere indicar
  explícitamente `--replace-unmanaged`; el archivo anterior se conserva como
  respaldo fechado antes del reemplazo.
- Los reemplazos se hacen mediante archivos temporales y conservan respaldos
  fechados.
- `--reload` reinicia la instancia de Picom para que lea el archivo nuevo; no
  reinicia la sesión ni el equipo.

## Fallos conocidos

### `falta el Picom de Debian: /usr/bin/picom`

**Causa:** el paquete `picom` no está instalado en la ruta del sistema.

**Solución:** instala `picom` mediante APT y repite `just picom-debian --check`.

### `se rehúsa sobrescribir una configuración no administrada`

**Causa:** existe un `picom.conf` o shader distinto que no pertenece al perfil
Rafex.

**Solución:** conserva el archivo, respáldalo manualmente si corresponde y
decide explícitamente si deseas sustituirlo antes de repetir `--apply`.

### `GLX error` o artefactos con blur

**Causa:** el controlador Xorg o la GPU no soportan de forma estable la
combinación GLX/blur en esa sesión.

**Solución:** usa `just picom-debian --disable`; i3 seguirá funcionando sin el
compositor. Después puedes cambiar el shader a `neutral.glsl` y probar de nuevo.

## Changelog

### [Unreleased]

- **feat:** añadir una ruta explícita para usar Picom Debian v13 con la configuración Rafex.
- **fix:** evitar que la activación dependa de una compilación upstream en `~/.local/bin`.
