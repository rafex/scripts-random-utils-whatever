---
title: connect_nas_linux.sh
description: Montaje de un NAS mediante CIFS
tags:
  - red
---

# connect_nas_linux.sh

Monta un recurso compartido CIFS/SMB (NAS) en `/mnt/nas` usando credenciales almacenadas en un archivo.

- **Ruta:** `scripts/network/connect_nas_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `sudo`, `mount.cifs`, `notify-send`

______________________________________________________________________

## Uso

```sh
./scripts/network/connect_nas_linux.sh
```

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `NAS_MOUNT_POINT` | `/mnt/nas` | Punto de montaje local |
| `NAS_SMB` | `//192.168.3.56/rafex` | Ruta UNC del recurso |
| `NAS_CREDENTIALS` | `/home/rafex/.smbcredentials` | Archivo de credenciales |
| `NAS_UID` | `1000` | UID del dueño |
| `NAS_GID` | `1000` | GID del grupo |

______________________________________________________________________

## Ejemplos

```sh
./scripts/network/connect_nas_linux.sh

NAS_SMB="//192.168.1.100/shared" NAS_MOUNT_POINT="/mnt/backup" \
  ./scripts/network/connect_nas_linux.sh
```

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

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/connect_nas.sh`.
