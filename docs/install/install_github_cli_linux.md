---
title: install_github_cli_linux.sh
description: Instalación de GitHub CLI oficial
tags:
  - instalación
---

# install_github_cli_linux.sh

Configura el repositorio APT oficial de GitHub CLI e instala el comando `gh`
en Debian. No configura autenticación ni almacena tokens.

- **Ruta:** `scripts/install/install_github_cli_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `dpkg`, `sudo`; el script instala `wget`, `gnupg` y `ca-certificates` si faltan

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

- Debian con `apt-get`, `dpkg` y arquitectura APT compatible.
- `sudo` configurado para el usuario actual.
- Conectividad HTTPS a `cli.github.com`.
- Ejecutar como usuario normal, no como root.

El script utiliza el repositorio APT oficial documentado por GitHub CLI:
<https://github.com/cli/cli/blob/trunk/docs/install_linux.md>.

## Uso

Diagnosticar sin modificar nada:

```sh
just install-github-cli --check
```

Revisar el plan:

```sh
just install-github-cli --plan
```

Configurar el repositorio e instalar GitHub CLI:

```sh
just install-github-cli --apply
```

Verificar la instalación:

```sh
gh --version
gh auth status
```

`gh auth status` puede indicar que aún no existe una sesión autenticada; eso es
normal. La autenticación se inicia manualmente con:

```sh
gh auth login
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica repositorio, clave y paquete sin cambios |
| `--plan` | `--dry-run` | Muestra acciones previstas sin modificar el sistema |
| `--apply` | — | Configura el repositorio oficial e instala `gh` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza variables de entorno para repositorios, claves,
contraseñas ni tokens. La contraseña de sudo se solicita únicamente mediante
`sudo -v`.

## Ejemplos

### Forma explícita recomendada

```sh
just install-github-cli --apply
```

### Ejecución directa

```sh
bash scripts/install/install_github_cli_linux.sh --check
bash scripts/install/install_github_cli_linux.sh --plan
bash scripts/install/install_github_cli_linux.sh --apply
```

### Autenticación posterior

```sh
gh auth login
gh auth status
gh repo view rafex/scripts-random-utils-whatever
```

## Protecciones de seguridad

- Usa exclusivamente `https://cli.github.com/packages` como origen APT.
- Descarga la clave oficial por HTTPS y verifica su SHA256 antes de instalarla:
  `6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b`.
- Comprueba además una de las huellas PGP oficiales:
  `2C6106201985B60E6C7AC87323F3D4EA75716059` o
  `7F38BBB59D064DBCB3D84D725612B36462313325`.
- Usa `signed-by` para limitar la clave al repositorio de GitHub CLI.
- Respaldará la clave y la fuente anterior en
  `/var/backups/rafex-github-cli/` antes de reemplazarlas.
- No acepta, almacena ni transmite contraseñas, tokens ni claves SSH.
- No ejecuta `gh auth login` automáticamente.

## Fallos conocidos

### `gh` aparece instalado desde el repositorio Debian

**Causa:** Debian puede ofrecer una versión comunitaria de GitHub CLI cuando el
repositorio oficial todavía no se ha configurado.

**Solución:** ejecuta `just install-github-cli --apply` y revisa
`apt-cache policy gh` para confirmar el origen y la versión candidata.

### `no se pudo descargar la clave`

**Causa:** falta de conectividad HTTPS, DNS, proxy o `wget`.

**Solución:** verifica `curl -I https://cli.github.com/packages` y repite el
modo `--apply` cuando exista conectividad.

### `checksum SHA256 inesperado para la clave`

**Causa:** la descarga no coincide con la clave oficial esperada o la clave
publicada cambió.

**Solución:** no continúes manualmente. Comprueba la documentación oficial de
instalación y actualiza el checksum del script mediante una revisión explícita.

## Changelog

### [Unreleased]

- **feat:** añadir instalador Debian idempotente para GitHub CLI oficial.
