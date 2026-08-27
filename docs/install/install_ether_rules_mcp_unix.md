---
title: install_ether_rules_mcp_unix.sh
description: Instala y configura el MCP oficial Ether-rules para clientes locales
tags:
  - instalación
  - seguridad
  - referencia
---

# install_ether_rules_mcp_unix.sh

Instala el wheel oficial de Ether-rules mediante `uv`, verifica su SHA-256 y configura clientes MCP locales detectados.

- **Ruta:** `scripts/install/install_ether_rules_mcp_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** Bash, Python 3, `curl`, `uv` y `sha256sum` o `shasum`

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

Instala `uv` con el gestor de paquetes de tu sistema o sigue la documentación oficial de [uv](https://docs.astral.sh/uv/). El script no usa `sudo` y no instala automáticamente Claude, Codex ni OpenCode.

La documentación oficial de [Ether-rules](https://my-best-practice.rafex.io/mcp-install/) publica el MCP como wheel de un release de GitHub y usa `uvx ether-mcp` para los clientes.

## Uso

```bash
just install-ether-rules-mcp --check
just install-ether-rules-mcp --plan
just install-ether-rules-mcp --apply
```

Por defecto solo configura clientes que estén presentes en `PATH`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra estado sin red ni cambios |
| `--plan` | `--dry-run` | Consulta el release y muestra acciones sin modificar archivos |
| `--apply` | — | Descarga, verifica, instala y configura |
| `--status` | — | Alias de diagnóstico de estado |
| `--uninstall` | — | Elimina `ether-rules` de clientes seleccionados y desinstala la herramienta |
| `--action install\|status\|uninstall` | — | Selecciona la acción explícitamente |
| `--client all\|claude\|codex\|opencode` | — | Limita los clientes; `all` usa todos los detectados |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `HOME` | Entorno del usuario | Raíz de las configuraciones y herramientas locales |
| `TMPDIR` | `/tmp` | Directorio padre para descargas temporales |

No se usa archivo `.env`.

## Ejemplos

```bash
# Instalar y configurar todos los clientes presentes
just install-ether-rules-mcp --apply

# Configurar únicamente OpenCode
just install-ether-rules-mcp --client opencode --apply

# Revisar el plan sin modificar nada
just install-ether-rules-mcp --client codex --plan

# Consultar el estado
just install-ether-rules-mcp --status

# Desinstalar únicamente la integración de OpenCode
just install-ether-rules-mcp --client opencode --uninstall
```

La entrada configurada usa:

```text
command: uvx
args: ether-mcp
```

No se configuran API keys ni autenticación del proveedor.

## Compatibilidad del release actual

El release oficial `v0.5.0` publicado en GitHub importa símbolos antiguos del
SDK MCP. En este equipo se mantiene el wheel oficial sin modificar y Codex
usa el adaptador local `tools/ether_rules_mcp_compat.py`, que corrige esos
imports al iniciar el proceso y fuerza el uso de los datos incluidos en el
wheel. El adaptador no descarga código ni recibe credenciales.

## Protecciones de seguridad

- No ejecuta `curl | bash`.
- Descarga primero el wheel y su checksum desde el release oficial.
- Verifica SHA-256 antes de ejecutar `uv tool install`.
- Solo modifica los archivos de configuración del cliente seleccionado.
- Crea respaldos fechados antes de cambios.
- No utiliza `sudo`, no escribe en `/usr/lib` y no modifica credenciales.
- Los clientes que no están instalados se omiten y se reportan.
- Las acciones `--check` y `--plan` no modifican configuraciones.

## Fallos conocidos

### `falta uv`

**Causa:** `uv` no está instalado o no está en `PATH`.

**Solución:** instalarlo según la [documentación oficial de uv](https://docs.astral.sh/uv/) y abrir una nueva terminal.

### `el release no contiene checksum del wheel`

**Causa:** Ether-rules publicó un release sin el asset de checksum esperado.

**Solución:** no se instala el wheel; revisar el release oficial y reintentar cuando tenga checksum.

### El cliente no muestra `ether-rules`

**Causa:** el cliente no estaba instalado, su CLI rechazó la operación o no recargó su configuración.

**Solución:** ejecutar `--status`, revisar el respaldo generado y reiniciar el cliente.

## Changelog

### [Unreleased]

- **feat:** instalar y verificar Ether-rules MCP para clientes locales detectados.
