---
title: power_control_linux.sh
description: Acciones de energía y apagado en Linux
tags:
  - hardware
---

# power_control_linux.sh

Prepara comandos de energía en Debian y crea `powerctl` para apagar,
reiniciar, suspender, hibernar o bloquear desde terminal/i3.

- **Ruta:** `scripts/hardware/power_control_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `sudo`, `systemctl`, `loginctl`

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

- Debian Linux con systemd.
- `sudo` configurado para el usuario actual.
- Ejecutar como usuario normal, no como root.

En la ThinkPad los comandos ya existen en `/sbin`, pero la sesión SSH actual
no tenía `/sbin` en `PATH`. El script corrige ese PATH para futuras sesiones.

## Uso

```sh
just power-control --check
just power-control --plan
just power-control --apply
```

Después de cerrar sesión y volver a entrar:

```sh
powerctl off
powerctl reboot
powerctl suspend
powerctl hibernate
powerctl lock
```

También siguen disponibles los comandos nativos:

```sh
systemctl poweroff
systemctl reboot
systemctl suspend
systemctl hibernate
shutdown -h now
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica comandos y PATH sin modificar nada |
| `--plan` | — | Muestra paquetes y archivos previstos sin modificar nada |
| `--dry-run` | — | Alias de `--plan` |
| `--apply` | — | Instala dependencias y configura PATH/helper |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `POWER_PROFILE_FILE` | `~/.profile` | Archivo donde se agrega el PATH persistente |

## Ejemplos

### Forma recomendada

```sh
just power-control --apply
```

### Apagado con confirmación automática desde una acción controlada

```sh
POWERCTL_CONFIRM=yes powerctl off
```

### Diagnóstico

```sh
just power-control --check
```

### Ejecución directa

```sh
bash scripts/hardware/power_control_linux.sh --apply
```

## Protecciones de seguridad

- `--apply` solicita sudo mediante `sudo -v` cuando necesita instalar paquetes.
- El script de instalación nunca apaga, reinicia ni suspende la computadora.
- `powerctl off` pide confirmación interactiva salvo que se use explícitamente
  `POWERCTL_CONFIRM=yes`.
- Hace respaldos fechados de `.profile` y del helper existente.
- No modifica GRUB, fstab, particiones ni reglas de sudoers.
- Es idempotente y no duplica el bloque de PATH.

## Fallos conocidos

### `poweroff` aparece instalado pero `command not found`

**Causa:** Debian coloca el enlace en `/sbin` o `/usr/sbin`, y la sesión SSH
no tiene esos directorios en `PATH`.

**Solución:** ejecuta `just power-control --apply` y abre una nueva sesión.

### `Interactive authentication required`

**Causa:** la acción se ejecuta desde una sesión SSH sin una sesión gráfica
activa de logind.

**Solución:** ejecuta el comando desde i3 o permite que `powerctl` solicite
autorización mediante `sudo`.

### `hibernate` falla

**Causa:** no hay swap suficiente o la plataforma no permite hibernación.

**Solución:** usa `powerctl suspend` y revisa `swapon --show` antes de
configurar hibernación.

## Changelog

### [Unreleased]

- **feat:** comandos persistentes de energía y helper seguro `powerctl`.
