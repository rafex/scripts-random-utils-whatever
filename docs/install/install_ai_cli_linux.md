---
title: install_ai_cli_linux.sh
description: Instalación de Codex CLI y Claude Code con npm del usuario
tags:
  - instalación
  - desarrollo
---

# install_ai_cli_linux.sh

Instala Codex CLI y Claude Code usando un prefijo npm privado del usuario,
sin `sudo`, sin modificar `/usr` y sin iniciar ninguna sesión.

- **Ruta:** `scripts/install/install_ai_cli_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, Node.js 18 o posterior, `npm`, conexión HTTPS

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

- Debian o un derivado compatible.
- Node.js y npm accesibles en la shell. El instalador también busca el runtime
  propio en `~/.local/share/node-runtimes/current-node/bin/`.
- `~/.local/bin` en el `PATH` para usar los enlaces instalados.
- Internet para descargar los paquetes desde el registro npm.

La instalación oficial de Codex CLI usa `npm install -g @openai/codex`:
<https://help.openai.com/en/articles/11096431>.

Claude Code documenta `npm install -g @anthropic-ai/claude-code` y recomienda
no usar `sudo npm install -g`:
<https://docs.anthropic.com/en/docs/claude-code/getting-started>.

## Uso

Diagnosticar el runtime y los comandos disponibles:

```sh
just install-ai-cli --check
```

Revisar el plan sin instalar:

```sh
just install-ai-cli --plan
```

Instalar ambos comandos para el usuario actual:

```sh
just install-ai-cli --apply
```

Consultar el estado:

```sh
just install-ai-cli --status
```

La autenticación se realiza después, de forma interactiva:

```sh
codex --login
claude
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Node.js, npm y los comandos sin modificar archivos |
| `--plan` | `--dry-run` | Muestra el prefijo y las acciones previstas |
| `--apply` | — | Instala ambos paquetes con npm del usuario |
| `--status` | — | Muestra rutas y versiones, sin mostrar credenciales |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso | Prioridad |
|---|---|---|
| `HOME` | Determina el prefijo `~/.local/share/npm-global` y `~/.local/bin` | Entorno del usuario |
| `PATH` | Permite localizar Node.js, npm y los comandos instalados | Entorno del usuario; el script antepone rutas propias |
| `NPM_CONFIG_*` | No se requiere configurarlas; el script usa valores temporales para evitar auditoría, fund y avisos | El script solo durante `--apply` |

No se aceptan tokens, claves API ni contraseñas como argumentos o variables
administradas por el instalador.

## Ejemplos

### Forma explícita recomendada

```sh
just install-ai-cli --apply
```

### Ejecución directa

```sh
bash scripts/install/install_ai_cli_linux.sh --status
bash scripts/install/install_ai_cli_linux.sh --plan
bash scripts/install/install_ai_cli_linux.sh --apply
```

### Autenticación posterior

```sh
codex --login
claude
```

## Protecciones de seguridad

- No usa `sudo npm install -g`.
- Instala en `~/.local/share/npm-global` y enlaza solo `codex` y `claude` en
  `~/.local/bin`.
- Si ya existe un comando que no pertenece a este instalador, se detiene y no
  lo sobrescribe.
- No ejecuta `codex --login`, `claude` ni ningún flujo OAuth.
- No imprime, recopila ni almacena tokens o claves de API.
- Los comandos de IA pueden leer archivos del proyecto y enviar prompts o
  contexto al proveedor cuando el usuario los ejecuta; revisar siempre el
  modo de permisos antes de trabajar con secretos.

## Fallos conocidos

### `no se encontró Node.js` o `no se encontró npm`

**Causa:** el runtime propio no está en la shell o no existe un runtime Node
instalado.

**Solución:** abre una shell nueva o ejecuta primero
`just install-node-runtime --version lts --apply`.

### `ya existe y no pertenece a este instalador`

**Causa:** `~/.local/bin/codex` o `~/.local/bin/claude` ya es un archivo o
enlace de otro origen.

**Solución:** revisa el destino manualmente; el script no lo reemplaza de
forma silenciosa.

### Error de autenticación de Codex o Claude

**Causa:** la instalación del CLI es independiente de la autenticación.

**Solución:** ejecuta `codex --login` o inicia `claude` en una terminal
interactiva y sigue el flujo oficial.

## Changelog

### [Unreleased]

- **feat:** añadir instalación de Codex CLI y Claude Code sin privilegios.
