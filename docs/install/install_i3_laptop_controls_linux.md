---
title: install_i3_laptop_controls_linux.sh
description: Instalar toggles y atajos multimedia para i3
tags:
  - instalación
  - i3
---

# install_i3_laptop_controls_linux.sh

Instala utilidades y configura atajos para volumen, micrófono, Wi‑Fi, modo
avión, búsqueda Rofi y un centro de control completo para i3.

- **Ruta:** `scripts/install/install_i3_laptop_controls_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con APT)
- **Dependencias:** `bash`, `apt-get`, `sudo`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

Ejecutar desde el repositorio como usuario normal con permisos `sudo`.

## Uso

```sh
just install-i3-laptop-controls --check
just install-i3-laptop-controls --plan
just install-i3-laptop-controls --apply
```

El bloque i3 añade `XF86AudioMicMute`, `XF86WLAN`, `XF86RFKill`,
`XF86Search`, `XF86Explorer`, `XF86WakeUp` y `XF86Tools`. `XF86Tools` abre el
centro de control completo; `XF86WakeUp` abre solo energía y sesión.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el modo de uso sin cambios. |
| `--plan` | `--dry-run` | Muestra paquetes y archivos que cambiarían. |
| `--apply` | — | Instala paquetes, helpers y el bloque i3. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `I3_CONTROLS_CONFIG` | `~/.config/i3/config` | Configuración i3 a modificar. |

## Ejemplos

```sh
just install-i3-laptop-controls --apply
I3_CONTROLS_CONFIG="$HOME/.config/i3/config" \
  just install-i3-laptop-controls --plan
```

## Protecciones de seguridad

- Solicita autorización mediante `sudo -v`; nunca lee ni guarda la contraseña.
- Respaldа el archivo i3 y cada helper antes de reemplazarlo.
- Usa un bloque administrado idempotente y no duplica atajos.
- No modifica particiones, `fstab`, GRUB ni archivos de contraseñas.

## Fallos conocidos

### `justfile does not contain recipe install-i3-laptop-controls`

**Causa:** el repositorio de la ThinkPad no se ha actualizado con esta versión.
**Solución:** ejecutar `git pull --ff-only` después de sincronizar el commit.

## Changelog

### [Unreleased]

**feat:** instalador de controles multimedia y utilidades de i3.
