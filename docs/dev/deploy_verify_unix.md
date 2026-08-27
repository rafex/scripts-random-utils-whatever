---
title: deploy_verify_unix.sh
description: Script de despliegue y verificación remota de scripts
tags:
  - desarrollo
---

# deploy_verify_unix.sh

Deploya scripts del repo a hosts remotos y verifica checksums SHA256. Usa `find` + `xargs` con procesamiento paralelo (`-P4`).

- **Ruta:** `scripts/dev/deploy_verify_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `ssh`, `scp`, `sha256sum`, `bash` 4+

______________________________________________________________________

## Requisitos

- `PATH.toml` en la raíz del repo (mapeo de scripts → nombres remotos + hosts)
- `SHA256SUMS` generado por `make checksums`
- Conexión SSH configurada a los hosts (`.ssh/config` o IP directa)
- `scripts/dev/commons_deploy_verify_unix.sh` en el mismo directorio (source)

______________________________________________________________________

## Uso

```sh
./scripts/dev/deploy_verify_unix.sh [opciones]
```

## Opciones

| Opción | Descripción |
|---|---|
| `--deploy-verify <host> [script...]` | Deploya y verifica scripts en el host |
| `--verify <host> [script...]` | Solo verifica (sin deploy) |
| `--verify-all` | Verifica todos los hosts configurados en paralelo |
| `--list` | Lista hosts y scripts mapeados en PATH.toml |
| `--check` | Verifica hashes locales contra SHA256SUMS |
| `--dry-run` | Simula sin ejecutar |
| `-h, --help` | Ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `DEPLOY_PARALLEL` | `4` | Procesos paralelos de xargs |
| `PATH_TOML` | `PATH.toml` | Ruta al archivo de configuración |

______________________________________________________________________

## Ejemplos

```sh
# Deploy + verify todos los scripts mapeados al host
./scripts/dev/deploy_verify_unix.sh --deploy-verify bastion-usb-wifi

# Verificar un script específico
./scripts/dev/deploy_verify_unix.sh --verify bastion-usb-wifi scripts/network/nm_force_ip_linux.sh

# Verificar todos los hosts en paralelo
./scripts/dev/deploy_verify_unix.sh --verify-all

# Listar configuración
./scripts/dev/deploy_verify_unix.sh --list

# Simular
./scripts/dev/deploy_verify_unix.sh --deploy-verify bastion-usb-wifi --dry-run
```

______________________________________________________________________

## PATH.toml

El script lee el mapeo de scripts y hosts desde `PATH.toml`:

```toml
[hosts.bastion-usb-wifi]
address = "bastion-usb-wifi"
base_path = "~/.local/bin"
user = "rafex"

[scripts]
"scripts/network/nm_force_ip_linux.sh" = "nm-force-ip"
"scripts/hardware/usb_mount_perms_linux.sh" = "usb-mount-perms"
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

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-08-03

**feat:** Script inicial de deploy + verify de scripts.

- Deploy por scp + verificación SHA256 en un solo paso
- Procesamiento paralelo con xargs -P4
- --verify-all ejecuta todos los hosts en paralelo
- Lee PATH.toml para mapeo de scripts y hosts
- Source commons_deploy_verify_unix.sh para lógica compartida
