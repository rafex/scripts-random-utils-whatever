---
title: install_runtime_switcher_linux.sh
description: Instala runtime-use y mantiene JAVA_HOME mediante un enlace simbólico estable.
tags:
  - instalación
  - java
  - nodejs
  - mise
---

# install_runtime_switcher_linux.sh

Instala la función Bash `runtime-use` para seleccionar Java y Node.js mediante
`mise`. `JAVA_HOME` permanece estable y apunta a
`~/.local/share/java-runtimes/current-java`.

- **Ruta:** `scripts/install/install_runtime_switcher_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `mise`, `awk`, `grep`, `ln`, `mv`, `readlink`

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
- Tener `mise` instalado y activado en Bash.
- Tener `~/.bashrc` o permitir que el instalador lo cree.
- Las versiones que se seleccionen deben estar instaladas en `mise` o se
  solicitará confirmación antes de ejecutar `mise install`.

## Uso

Desde la raíz del repositorio:

```bash
just install-runtime-switcher --check
just install-runtime-switcher --plan
just install-runtime-switcher --apply
reload-bash
```

El enlace estable es:

```text
~/.local/share/java-runtimes/current-java
```

`JAVA_HOME` apunta a ese enlace. El destino cambia cuando se selecciona otro
Java; `JAVA_HOME` no se convierte en una ruta versionada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el bloque, el enlace y los runtimes activos. |
| `--plan` | `--dry-run` | Muestra los cambios sin modificar archivos. |
| `--apply` | — | Instala o actualiza el bloque administrado de `.bashrc`. |
| `--help` | `-h` | Muestra la ayuda. |

La función instalada acepta:

| Comando | Descripción |
|---|---|
| `runtime-use java VERSION` | Selecciona Java globalmente. Un número usa Temurin. |
| `runtime-use node VERSION` | Selecciona Node.js globalmente. |
| `runtime-use --local java VERSION` | Selecciona Java en el `.mise.toml` local. |
| `runtime-use --local node VERSION` | Selecciona Node.js en el proyecto actual. |
| `runtime-use --list [java\|node]` | Lista runtimes instalados para elegir una versión. |
| `runtime-use list [java\|node]` | Alias compatible para listar runtimes. |
| `runtime-use current [java\|node]` | Muestra selección y `JAVA_HOME`. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `BASHRC` | CLI indirecta / entorno | Permite probar otro archivo Bash durante la instalación. |
| `HOME` | Entorno del usuario | Determina `.bashrc` y el enlace `current-java`. |

No se usa `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```bash
just install-runtime-switcher --apply
reload-bash
runtime-use java 25
runtime-use node lts
```

### Java alternativo

Usa el identificador exacto mostrado por `runtime-use list java`:

```bash
runtime-use java graalvm-25.0.2
readlink -f "$JAVA_HOME"
```

### Listar versiones para elegir

```bash
runtime-use --list
runtime-use --list java
runtime-use --list node
```

Después selecciona el identificador mostrado:

```bash
runtime-use java temurin-25
runtime-use node 22
```

### Versión por proyecto

```bash
cd ~/repository/github/mi-proyecto
runtime-use --local java 21
runtime-use --local node 20
runtime-use current
```

### Verificación de la ruta estable

```bash
echo "$JAVA_HOME"
readlink -f "$JAVA_HOME"
java --version
node --version
```

## Protecciones de seguridad

- `--check` y `--plan` no modifican archivos.
- No usa `sudo` ni almacena credenciales.
- Crea respaldo fechado de `.bashrc` antes de modificarlo.
- No elimina runtimes instalados.
- Rechaza reemplazar `current-java` si existe como archivo o directorio no
  simbólico.
- Actualiza el enlace mediante un temporal y `mv`.
- Pregunta antes de instalar una versión ausente.
- No sobrescribe `PROMPT_COMMAND`; agrega una única función de sincronización.

## Fallos conocidos

### `runtime-use: mise no está instalado`

**Causa:** `mise` no está instalado o no se encuentra en `PATH`.

**Solución:** ejecuta `just install-terminal-workstation --apply --stage runtimes`
y abre una nueva shell.

### `JAVA_HOME` conserva una ruta antigua

**Causa:** la shell fue abierta antes de instalar el selector o conserva el
valor exportado por una configuración anterior.

**Solución:** ejecuta `reload-bash` o abre una nueva terminal y verifica que
`JAVA_HOME` termine en `current-java`.

### `current-java existe pero no es un enlace simbólico`

**Causa:** un archivo o directorio ocupa la ruta administrada.

**Solución:** conserva el archivo, muévelo manualmente y vuelve a ejecutar el
instalador. El script nunca lo reemplaza automáticamente.

### `mise install` solicita o no encuentra una versión

**Causa:** la versión no está instalada o el identificador no coincide con el
catálogo del backend de mise.

**Solución:** revisa `runtime-use list`, consulta `mise ls-remote` y usa el
identificador exacto del proveedor.

## Changelog

### [Unreleased]

- **feat:** añade `runtime-use` para Java y Node.js con selección global y local.
- **feat:** mantiene `JAVA_HOME` en `~/.local/share/java-runtimes/current-java`.
- **fix:** evita exportar rutas versionadas directas de Temurin o GraalVM.
