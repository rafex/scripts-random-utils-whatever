---
title: install_restic_backup_linux.sh
description: Instala Restic y Secret Service para respaldos cifrados de usuario
tags:
  - instalación
  - restic
  - backup
---

# install_restic_backup_linux.sh

Instala las herramientas necesarias para los respaldos incrementales de la
ThinkPad. No inicializa repositorios, no monta discos y no crea timers.

- **Ruta:** `scripts/install/install_restic_backup_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `apt-get`, `apt-cache`, `dpkg-query`, `sudo`

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

Debian o un derivado compatible con `apt-get`. La instalación de paquetes
requiere `sudo`; la contraseña no se guarda ni se procesa por el script.

Los paquetes son:

```text
restic libsecret-tools gnome-keyring
```

`libsecret-tools` proporciona `secret-tool`, que permite guardar las claves en
GNOME Keyring mediante Secret Service.

## Uso

Desde la raíz del repositorio:

```bash
just install-restic-backup --check
just install-restic-backup --plan
just install-restic-backup --apply
just install-restic-backup --status
```

Después de instalar, usa
`just backup-thinkpad-restic --init --profile recovery` para crear el primer
repositorio. La inicialización es deliberadamente independiente de este
instalador.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquetes y candidatos sin escribir. |
| `--plan` | `--dry-run` | Muestra los paquetes previstos sin modificar el sistema. |
| `--apply` | — | Instala los paquetes con `sudo`; no inicializa Restic. |
| `--status` | — | Muestra paquetes, versiones y disponibilidad de Secret Service. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este instalador no usa variables de entorno para credenciales ni para cambiar
el destino. Los argumentos de la tarea Just tienen prioridad porque se pasan
directamente al script.

| Variable | Predeterminado | Descripción |
|---|---|---|
| `PATH` | El del proceso | El script antepone rutas administrativas estándar para localizar APT. |

## Ejemplos

Instalación recomendada:

```bash
just install-restic-backup --apply
```

Comprobar sin instalar:

```bash
just install-restic-backup --check
```

Consultar el estado:

```bash
just install-restic-backup --status
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no requieren `sudo` ni escriben archivos.
- `--apply` solicita `sudo` únicamente para APT.
- No se inicializan repositorios ni se generan claves automáticamente.
- No se montan, formatean ni modifican discos.
- No se guardan contraseñas en archivos, argumentos, logs ni Git.

## Fallos conocidos

### `sin candidato APT`

**Causa:** las fuentes configuradas no ofrecen uno de los paquetes.

**Solución:** revisa las fuentes Debian y vuelve a ejecutar
`just install-restic-backup --plan`. El script no añade repositorios externos.

### `secret-tool no está disponible después de aplicar`

**Causa:** la instalación de `libsecret-tools` no terminó o el sistema no se
actualizó correctamente.

**Solución:** ejecuta `just install-restic-backup --status` y revisa el estado
de APT. No inicialices repositorios hasta que `secret-tool` esté disponible.

### Keyring bloqueado

**Causa:** Secret Service no está desbloqueado en la sesión gráfica.

**Solución:** abre la sesión gráfica, desbloquea GNOME Keyring y vuelve a usar
el runner Restic. El instalador no intenta desbloquearlo ni guarda la clave en
otro lugar.

## Changelog

### [Unreleased]

- **feat:** añadir instalación separada de Restic, `secret-tool` y GNOME Keyring.

