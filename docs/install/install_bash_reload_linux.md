---
title: install_bash_reload_linux.sh
description: Instalador de una función para recargar Bash en la sesión actual.
tags:
  - bash
  - terminal
  - instalación
---

# install_bash_reload_linux.sh

Instala `reload-bash` en `~/.local/bin` y añade una función administrada a
`~/.bashrc` para recargar la configuración sin cerrar la terminal. También
agrega una sincronización final de Java con `mise` para mantener `JAVA_HOME` en
el enlace estable `~/.local/share/java-runtimes/current-java`, incluso si una
configuración anterior usaba otra distribución, como GraalVM.

- **Ruta:** `scripts/install/install_bash_reload_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `coreutils`

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

- Ejecutar como usuario normal, no como `root`.
- Tener `~/.bashrc` o permitir que el instalador lo cree.
- Mantener `~/.local/bin` en el `PATH`, como hace la estación terminal.

## Uso

```bash
just install-bash-reload --check
just install-bash-reload --plan
just install-bash-reload --apply
```

Después de instalarlo, recarga la shell actual:

```bash
source ~/.bashrc
reload-bash
```

Cuando `mise` está activo, `reload-bash` ejecuta `mise hook-env` después de
leer `.bashrc`, consulta `mise where java` y repunta `current-java`; de esta
forma `JAVA_HOME` conserva una ruta estable y se actualizan `PATH` y la caché
de comandos en la shell actual.

También puedes ejecutar directamente `~/.local/bin/reload-bash`; en ese caso
creará una nueva shell login porque un proceso hijo no puede cambiar el entorno
de su shell padre.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el ejecutable y el bloque de `.bashrc`. |
| `--plan` | `--dry-run` | Muestra cambios sin escribir archivos. |
| `--apply` | — | Instala el ejecutable y actualiza `.bashrc`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `HOME` | entorno del usuario | Determina `.bashrc` y `~/.local/bin`. |
| `BASHRC` | `~/.bashrc` al ejecutar el helper | Permite probar otro archivo al hacer `source`. |

No se usa `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```bash
just install-bash-reload --apply
source ~/.bashrc
reload-bash
```

### Diagnóstico

```bash
just install-bash-reload --check
```

### Uso directo del helper

```bash
source ~/.local/bin/reload-bash
```

## Protecciones de seguridad

- No usa `sudo`.
- `--check`, `--plan` y `--dry-run` no modifican archivos.
- Respaldará `.bashrc` y el helper existente antes de reemplazarlos.
- Usa bloques marcados para no duplicar la función.
- No inicia tmux, no cambia `PATH` fuera del bloque de `.bashrc` y no modifica
  archivos de contraseñas.

## Fallos conocidos

### `reload-bash: command not found`

**Causa:** la shell actual todavía no ha leído el bloque nuevo o `~/.local/bin`
no está en `PATH`.

**Solución:** ejecuta `source ~/.bashrc` o abre una terminal nueva; después
repite `reload-bash`.

### La shell padre no cambia al ejecutar el archivo directamente

**Causa:** un proceso hijo no puede modificar el entorno de su padre.

**Solución:** usa la función instalada, `reload-bash`, o `source
~/.local/bin/reload-bash`.

### `reload-bash` cierra el panel de tmux

**Causa:** una versión anterior del helper activaba `set -Eeuo pipefail` incluso
cuando se cargaba mediante `source`; un fallo opcional de `.bashrc` podía
terminar la shell del panel.

**Solución:** actualiza el helper con `just install-bash-reload --apply` y usa
la función `reload-bash`. El modo estricto solo se aplica cuando el archivo se
ejecuta directamente; la sesión de tmux no debe cerrarse al recargar Bash.

## Changelog

### [Unreleased]

- **feat:** añade recarga idempotente de Bash para la sesión actual.
- **fix:** conservar `JAVA_HOME` estable al recargar Bash.
- **fix:** evitar heredar `set -e` al cargar el helper desde una shell
  interactiva.
