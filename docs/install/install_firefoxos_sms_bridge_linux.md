---
title: install_firefoxos_sms_bridge_linux.sh
description: Prepara el puente rootless de SMS entre la ThinkPad y un Firefox OS Flame.
tags:
  - instalación
  - firefox-os
  - sms
---

# install_firefoxos_sms_bridge_linux.sh

Instala o verifica Podman y el helper del puente local de SMS. No inicia el
servicio, no crea credenciales y no modifica el teléfono.

- **Ruta:** `scripts/install/install_firefoxos_sms_bridge_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-cache`, `dpkg-query`, `sudo` solo en `--apply`, `podman` y `python3`

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

Se requiere Debian o un derivado compatible, una sesión de usuario normal y
el repositorio completo. La instalación usa Podman rootless y conserva el
publicador Hola Mundo sin mezclar su estado.

## Uso

```bash
just install-firefoxos-sms-bridge --check
just install-firefoxos-sms-bridge --plan
just install-firefoxos-sms-bridge --apply
just install-firefoxos-sms-bridge --status
```

`--apply` puede instalar `podman` y `python3` mediante APT, copia el helper a
`~/.local/bin/firefoxos-sms-bridge.sh` y prepara el directorio privado de
estado. No inicializa el token de emparejamiento.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Verifica Debian, componentes, candidatos APT y Podman sin escribir. |
| `--plan` | `--dry-run` | Muestra paquetes y archivos que se prepararían, sin modificar nada. |
| `--apply` | — | Instala dependencias faltantes y prepara el helper y el estado privado. |
| `--status` | — | Muestra versiones y estado sin iniciar el puente. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_DATA_HOME` | `~/.local/share` | Base para el estado privado del puente. |
| `PATH` | Rutas del sistema | Se anteponen rutas estándar para localizar herramientas. |

No se leen archivos `.env` ni se aceptan secretos mediante variables de
entorno.

## Ejemplos

### Forma explícita/recomendada

```bash
just install-firefoxos-sms-bridge --check
just install-firefoxos-sms-bridge --plan
just install-firefoxos-sms-bridge --apply
```

### Verificar el resultado

```bash
just install-firefoxos-sms-bridge --status
~/.local/bin/firefoxos-sms-bridge.sh --status
```

### Iniciar el servicio después de instalar

```bash
just firefoxos-sms --serve-podman
just firefoxos-sms --status
```

### Repetir la instalación

```bash
just install-firefoxos-sms-bridge --apply
```

La operación conserva el helper si no cambió y no crea tokens ni contenedores
duplicados.

## Protecciones de seguridad

- `sudo` se usa únicamente para APT durante `--apply`.
- El instalador no inicia el contenedor ni modifica UFW, ADB, USBGuard o el Flame.
- El estado se crea con permisos `0700` y los archivos internos con `0600`.
- No se guardan claves en el repositorio ni en variables persistentes.
- Podman se ejecuta rootless; el servicio no requiere ni acepta `sudo`.

## Fallos conocidos

### `sin candidato APT: podman`

**Causa:** las fuentes Debian activas no ofrecen el paquete requerido.

**Solución:** revisa las fuentes Debian y vuelve a ejecutar `--check`; no se
descargan binarios externos automáticamente.

### `falta el helper del repositorio`

**Causa:** se ejecutó la tarea desde un checkout incompleto o antes de
sincronizar el repositorio.

**Solución:** ejecuta `git pull --ff-only` y repite `--check`.

### `ejecuta el instalador como usuario normal`

**Causa:** se invocó el instalador como root.

**Solución:** ejecútalo como `rafex`; el script solicita `sudo` solo cuando
instala paquetes.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.0.0 — 2026-09-02

- **feat:** prepara dependencias y estado privado para el puente SMS rootless.
