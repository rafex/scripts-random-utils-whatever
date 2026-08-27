---
title: configure_sudo_linux.sh
description: Configuración segura de sudo para un usuario Linux
tags:
  - instalación
---

# configure_sudo_linux.sh

Instala y configura `sudo` para un usuario normal en una instalación Debian
recién instalada. Está diseñado para ejecutarse una vez como `root` mediante
`su -`.

- **Ruta:** `scripts/install/configure_sudo_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `getent`, `id`, `usermod`, `visudo`

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

- Debian Linux con `apt-get`.
- Ejecutar `--apply` desde una shell root obtenida con `su -`.
- El usuario objetivo debe existir y no puede ser `root`.
- El script no necesita ni acepta una contraseña como argumento, variable o
  archivo.

## Uso

Desde la ThinkPad, después de clonar el repositorio, revisa el estado como el
usuario normal:

```sh
just configure-sudo --user rafex --check
```

Si falta `sudo`, entra a root y aplica la configuración:

```sh
su -
cd /home/rafex/scripts-random-utils-whatever
just configure-sudo --user rafex --apply
exit
```

Cierra la sesión de `rafex` y vuelve a entrar. Luego valida:

```sh
sudo -v
id -nG
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--user <usuario>` | — | Usuario normal que recibirá sudo |
| `--check` | — | Diagnostica sin modificar nada |
| `--plan` | — | Muestra cambios previstos sin modificar nada |
| `--dry-run` | — | Alias de `--plan` |
| `--apply` | — | Instala y configura sudo; requiere root |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SUDO_TARGET_USER` | usuario actual | Usuario objetivo si no se usa `--user` |

La opción `--user` tiene prioridad sobre `SUDO_TARGET_USER`. No se aceptan
contraseñas por variables de entorno.

## Ejemplos

### Forma explícita recomendada

```sh
su -
cd /home/rafex/scripts-random-utils-whatever
just configure-sudo --user rafex --apply
```

### Diagnóstico sin cambios

```sh
just configure-sudo --user rafex --check
```

### Plan sin cambios

```sh
just configure-sudo --user rafex --dry-run
```

### Ejecución directa sin Just

```sh
su -
bash /home/rafex/scripts-random-utils-whatever/scripts/install/configure_sudo_linux.sh \
  --user rafex --apply
```

## Protecciones de seguridad

- `--apply` exige `EUID=0`; no intenta elevar privilegios de forma implícita.
- La contraseña de root la gestiona `su`; el script nunca la lee ni la
  almacena.
- La configuración usa el grupo Debian `sudo`, no una regla individual con
  privilegios más amplios.
- Si falta la regla estándar `%sudo`, crea `/etc/sudoers.d/90-sudo-group` con
  permisos `0440`.
- Valida toda la configuración con `visudo -c` antes de terminar.
- Es idempotente y crea respaldos fechados si debe reemplazar una regla local.

## Fallos conocidos

### `--apply debe ejecutarse como root`

**Causa:** todavía no existe `sudo`, por lo que el usuario normal no puede
elevar privilegios.

**Solución:** ejecuta `su -` y vuelve a lanzar la etapa `--apply`.

### `el usuario no existe`

**Causa:** el nombre pasado con `--user` no está registrado en `/etc/passwd`.

**Solución:** verifica `getent passwd rafex` y usa el nombre real de la cuenta.

### `la configuración de sudoers no es válida`

**Causa:** existe una regla previa con sintaxis incorrecta.

**Solución:** revisa el archivo indicado por `visudo -c`, corrige o restaura
el respaldo `.bak.YYYYMMDD_HHMMSS` y vuelve a ejecutar el diagnóstico.

## Changelog

### [Unreleased]

- **feat:** bootstrap idempotente de `sudo` y grupo `sudo` para Debian.
