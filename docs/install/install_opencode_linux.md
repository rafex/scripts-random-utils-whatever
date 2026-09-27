---
title: install_opencode_linux.sh
description: Instalar OpenCode oficial en Debian sin root
tags:
  - instalación
  - opencode
  - thinkpad
---

# install_opencode_linux.sh

Instala OpenCode desde el instalador oficial para el usuario normal de la
ThinkPad y mantiene una copia administrada en `~/.local/bin`.

- **Ruta:** `scripts/install/install_opencode_linux.sh`
- **SO requerido:** Linux (Debian y derivados compatibles)
- **Dependencias:** `bash`, `curl`, `cmp`, `install`, `mktemp`

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

- Debian en la ThinkPad.
- Ejecutar como usuario normal; no se usa `sudo`.
- `curl` y conexión HTTPS hacia `opencode.ai` solo durante `--apply`.
- El instalador oficial debe crear `~/.opencode/bin/opencode`.
- La autenticación se realiza después, de forma independiente.

## Uso

```bash
just install-opencode --check
just install-opencode --plan
just install-opencode --apply
just install-opencode --status
```

Para actualizar una instalación existente:

```bash
just update-opencode --check
just update-opencode --plan
just update-opencode --apply
```

El instalador de la estación de terminal reutiliza este script:

```bash
just install-terminal-workstation --apply --stage opencode
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el estado sin descargar ni escribir |
| `--plan` | — | Muestra las acciones previstas sin modificar archivos |
| `--status` | — | Consulta las dos copias locales y el PATH |
| `--apply` | — | Descarga, instala y sincroniza OpenCode |
| `--version X.Y.Z` | — | Solicita una versión estable explícita |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso |
|---|---|
| `HOME` | Define las rutas de instalación del usuario |
| `PATH` | Solo se informa la instalación que resuelve `opencode`; no se modifica |
| `VERSION` | Se elimina antes de ejecutar el instalador oficial |

No usa `.env`, no recibe credenciales y no almacena tokens.

## Ejemplos

### Instalación recomendada

```bash
just install-opencode --apply
```

### Probar sin cambios

```bash
just install-opencode --check
just install-opencode --plan
```

### Versión explícita

```bash
just install-opencode --apply --version 1.0.180
```

### Actualización posterior

```bash
just update-opencode --apply
```

## Protecciones de seguridad

- Rechaza root, enlaces simbólicos y archivos ajenos en las rutas administradas.
- No usa `sudo`, npm, Homebrew ni un daemon privilegiado.
- Descarga únicamente por HTTPS desde `https://opencode.ai/install`.
- Valida la sintaxis del instalador antes de ejecutarlo.
- Crea un respaldo privado en `~/.opencode/rafex-install-*`.
- Usa un lock para impedir instalaciones simultáneas.
- Si falla la instalación, intenta restaurar ambas copias.
- No modifica PATH, shell, credenciales, MCP ni autenticación.

El instalador descargado ejecuta código del proveedor; la validación de sintaxis
no sustituye una firma criptográfica independiente.

## Fallos conocidos

### `el instalador no creó ~/.opencode/bin/opencode`

**Causa:** el proveedor cambió el destino o la descarga no terminó correctamente.

**Solución:** revisa la conectividad y el respaldo mostrado; no copies un binario
manualmente sin verificar su origen.

### `actualización bloqueada`

**Causa:** otra instalación está activa o quedó un lock vacío después de una
interrupción.

**Solución:** confirma que no haya otra ejecución y elimina solo el directorio
vacío `~/.opencode/.rafex-install.lock` con `rmdir`.

### `archivo existe pero no es un binario ejecutable propio`

**Causa:** una instalación externa o un enlace ocupa la ruta administrada.

**Solución:** conserva esa instalación con su gestor original o retírala
manualmente; el script no la sobrescribe.

## Changelog

### [Unreleased]

- **feat:** añadir instalador independiente de OpenCode para Debian/ThinkPad.
- **refactor:** reutilizarlo desde la etapa `opencode` de la estación terminal.
