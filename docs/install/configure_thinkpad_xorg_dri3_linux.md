---
title: configure_thinkpad_xorg_dri3_linux.sh
description: Instala una configuración Xorg explícita de modesetting, glamor y PageFlip para la ThinkPad X1 Yoga
tags:
  - linux
  - thinkpad
  - xorg
  - dri3
---

# configure_thinkpad_xorg_dri3_linux.sh

Instala de forma reversible una configuración Xorg específica para la
ThinkPad X1 Yoga de primera generación. Usa el driver `modesetting` sobre
`i915`, aceleración `glamor` y `PageFlip on`, que deja explícito el camino de
presentación DRI3 esperado.

- **Ruta:** `scripts/install/configure_thinkpad_xorg_dri3_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `sudo`, `awk`, `basename`, `cmp`, `cp`, `date`, `grep`, `install`, `readlink`, `sort`, `tail`

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

- ThinkPad con GPU Intel y driver DRM `i915`.
- Sesión Xorg; Wayland no utiliza esta configuración.
- `sudo` para `--apply` y `--rollback`.
- El perfil del repositorio debe conservar el archivo:
  `dotfiles/profiles/thinkpad-x1-yoga-1st/config/X11/xorg.conf.d/20-thinkpad-modesetting.conf`.

La configuración de la MacBook no se reutiliza. La Mac usa el DDX `intel`,
mientras que la ThinkPad se mantiene con `modesetting`, que trabaja sobre KMS
y ofrece `glamor` y page-flipping DRI3. El manual del driver documenta
`AccelMethod "glamor"` y `PageFlip` como opciones propias de `modesetting`:
[modesetting(4)](https://man.archlinux.org/man/modesetting.4).

## Uso

Desde la raíz del repositorio:

```bash
just configure-thinkpad-xorg-dri3 --check
just configure-thinkpad-xorg-dri3 --plan
just configure-thinkpad-xorg-dri3 --apply
just configure-thinkpad-xorg-dri3 --status
```

El archivo instalado es:

```text
/etc/X11/xorg.conf.d/20-thinkpad-modesetting.conf
```

Xorg lo leerá en el próximo reinicio de la sesión gráfica. El instalador no
reinicia LightDM, no cierra la sesión y no interrumpe la sesión Xorg actual.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra driver DRM, archivo instalado y conflictos sin escribir ni usar sudo. |
| `--plan` | `--dry-run` | Muestra validaciones y cambios previstos sin modificar archivos. |
| `--apply` | — | Respalda e instala el archivo como `root:root`, con modo `0644`. |
| `--status` | — | Muestra el estado actual sin solicitar sudo. |
| `--rollback` | — | Restaura el respaldo más reciente creado por este script. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El script no admite variables de entorno ni archivos `.env` para seleccionar
el destino. El archivo se mantiene fijo en `/etc/X11/xorg.conf.d/` para evitar
que una variable accidental apunte a una ruta sensible o no validada.

## Ejemplos

Comprobar sin cambios:

```bash
just configure-thinkpad-xorg-dri3 --check
```

Revisar y aplicar desde la ThinkPad:

```bash
just configure-thinkpad-xorg-dri3 --plan
just configure-thinkpad-xorg-dri3 --apply
```

Después de cerrar y volver a iniciar la sesión Xorg:

```bash
grep -E 'modesetting|PageFlip|glamor' /var/log/Xorg.0.log
glxinfo -B
```

Para restaurar el último respaldo y después reiniciar la sesión Xorg:

```bash
just configure-thinkpad-xorg-dri3 --rollback
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no escriben archivos ni solicitan sudo.
- `--apply` solo modifica `/etc/X11/xorg.conf.d/20-thinkpad-modesetting.conf`.
- Antes de reemplazar un archivo administrado se crea un respaldo en
  `/var/backups/rafex-thinkpad-xorg/`.
- Si existe un archivo con el mismo nombre que no tiene los marcadores Rafex,
  el script se detiene y no lo sobrescribe.
- Si detecta otro archivo Xorg con un driver de GPU explícito, exige revisión
  manual para evitar dos políticas contradictorias.
- Solo aplica cuando el driver DRM del equipo es `i915`.
- No modifica `xorg.conf`, Mesa, DRI del kernel, GRUB, el kernel, Picom,
  monitores ni la configuración de energía.
- No reinicia LightDM ni ejecuta un cierre de sesión automático.

## Fallos conocidos

### `se esperaba driver DRM i915`

**Causa:** el equipo no expone `i915` como driver DRM o se ejecutó el script en
otra máquina.

**Solución:** no fuerces esta configuración. Revisa `lspci -k`,
`/sys/class/drm/card0/device/driver` y usa la configuración correspondiente al
hardware real.

### `existe y no está administrado`

**Causa:** ya existe una configuración manual en la ruta destino.

**Solución:** revísala y decide manualmente si debe conservarse. El instalador
no la sobrescribe de forma silenciosa.

### `hay configuraciones de GPU no administradas en conflicto`

**Causa:** otro archivo de `/etc/X11/xorg.conf` o `xorg.conf.d` fija `intel`,
`modesetting` u otro driver de vídeo.

**Solución:** elimina o documenta el conflicto manualmente, sin borrar
archivos a ciegas, y repite `--check`.

### `la configuración no cambia en la sesión actual`

**Causa:** Xorg solo lee el archivo al iniciar el servidor X.

**Solución:** cierra y vuelve a iniciar la sesión gráfica. No hace falta
reiniciar el equipo completo.

## Changelog

### [Unreleased]

- **feat:** añadir configuración explícita de `modesetting`, `glamor` y
  `PageFlip on` para la ThinkPad.
- **feat:** añadir respaldos y rollback sin reiniciar LightDM automáticamente.

### v1.0.0 — 2026-09-01

**feat:** primera versión del instalador Xorg explícito para la ThinkPad.
