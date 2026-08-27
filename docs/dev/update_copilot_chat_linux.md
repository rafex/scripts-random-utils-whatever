---
title: update_copilot_chat_linux.sh
description: Actualización de integración Copilot Chat en Linux
tags:
  - desarrollo
---

# update_copilot_chat_linux.sh

Descarga la penúltima versión minor de GitHub Copilot Chat (`.vsix`) desde el Marketplace de VS Code. Opcionalmente instala con `codium` o `code` usando `--force`.

- **Ruta:** `scripts/dev/update_copilot_chat_linux.sh`
- **SO requerido:** Linux, macOS
- **Dependencias:** `curl`, `jq`, `sort`

______________________________________________________________________

## Uso

```sh
./scripts/dev/update_copilot_chat_linux.sh [opciones]
```

______________________________________________________________________

## Opciones

| Opción | Descripción |
|---|---|
| `--install` | Instala la extensión tras descargar |
| `--no-force` | Instala sin `--force` |
| `--out DIR` | Directorio de salida para el .vsix (default: `./vsix`) |
| `--bin codium\|code` | Binario del editor para instalar |
| `-h, --help` | Mostrar ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `OUT_DIR` | `./vsix` | Directorio de descarga |
| `INSTALL` | `0` | Instalar tras descargar (`1` = sí) |
| `FORCE` | `1` | Usar `--force` al instalar |
| `EDITOR_BIN` | auto (codium o code) | Binario del editor |

______________________________________________________________________

## Ejemplos

```sh
./scripts/dev/update_copilot_chat_linux.sh

./scripts/dev/update_copilot_chat_linux.sh --install --bin codium

OUT_DIR=/tmp/vsix INSTALL=1 EDITOR_BIN=code \
  ./scripts/dev/update_copilot_chat_linux.sh
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

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/update_copilot_chat.sh`.
