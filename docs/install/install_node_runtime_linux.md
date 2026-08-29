---
title: install_node_runtime_linux.sh
description: Descarga Node.js oficialmente, lo instala localmente y lo integra en mise
tags:
  - instalación
  - nodejs
  - mise
---

# install_node_runtime_linux.sh

Instala Node.js sin usar el descargador de mise y registra la ruta externa con
`mise link`, `mise use` y `mise reshim`.

- **Ruta:** `scripts/install/install_node_runtime_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, Python 3, `curl`, `tar`, `xz-utils`, `sha256sum`, `mise`

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

Debe existir `mise` para integrar el runtime, pero el runtime no se descarga
con mise.

## Uso

```bash
just install-node-runtime --version lts --apply
```

La instalación se guarda bajo `~/.local/share/node-runtimes/` y se registra en
`~/.local/share/rafex-runtimes/registry.tsv`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra Node.js y el registro. |
| `--plan` | `--dry-run` | Consulta metadata sin modificar. |
| `--apply` | — | Descarga, verifica, instala e integra. |
| `--version VERSION` | — | `lts`, versión mayor o exacta. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Entorno | Define la raíz de instalación. |
| `TMPDIR` | Entorno | Define temporales de descarga. |

## Ejemplos

```bash
just install-node-runtime --version 24.20.0 --plan
just install-node-runtime --version 24.20.0 --apply
runtime-use --list node
runtime-use node 24.20.0
```

## Protecciones de seguridad

- Verifica SHA-256 antes de extraer.
- Usa HTTPS y temporales locales.
- No usa `sudo` ni ejecuta `mise install`.
- Registra la ruta manual antes de exponerla mediante mise.

## Fallos conocidos

### `mise no está instalado`

**Causa:** se intentó integrar Node.js antes de instalar mise.

**Solución:** ejecuta la etapa de runtimes de la estación de terminal.

## Changelog

### [Unreleased]

- **feat:** instalar Node.js oficial y enlazarlo en mise.
- **fix:** leer completamente el archivo comprimido para evitar un falso
  `SIGPIPE` (`exit 141`) con `pipefail`.
