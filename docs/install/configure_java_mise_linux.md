---
title: configure_java_mise_linux.sh
description: Selección global de un JDK Temurin instalado mediante su ruta versionada directa.
tags:
  - java
  - mise
  - instalación
---

# configure_java_mise_linux.sh

Registra en `mise` un JDK Temurin que ya existe en el usuario y lo selecciona
globalmente sin apuntar al enlace mutable `current-temurin-jdk`.

- **Ruta:** `scripts/install/configure_java_mise_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `mise`, un JDK Temurin local

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

Instala primero Temurin, por ejemplo:

```bash
just install-java-runtime --provider temurin --version 25 --image jdk --apply
```

El JDK se busca por defecto bajo:

```text
~/.local/share/java-runtimes/temurin/jdk-25*-jdk/
```

También debe estar disponible `mise`, normalmente en `~/.local/bin/mise`.

## Uso

```bash
just configure-java-mise --version 25 --apply
```

La configuración global resultante será `java@temurin-25`, enlazada al
directorio real versionado, por ejemplo:

```text
/home/rafex/.local/share/java-runtimes/temurin/jdk-25.0.4.1+1-jdk
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el JDK encontrado y el estado de mise. |
| `--plan` | `--dry-run` | Muestra las operaciones sin modificar archivos. |
| `--apply` | — | Crea el enlace de mise, actualiza la selección global y ejecuta `mise reshim`. |
| `--provider temurin` | — | Proveedor admitido. |
| `--version VERSION` | — | Versión mayor, como `25`. |
| `--path DIRECTORIO` | — | Ruta exacta del JDK; evita cualquier resolución mediante `current`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `HOME` | entorno del usuario | Determina la raíz de runtimes, `mise` y su configuración. |

No se usa `.env` ni se aceptan credenciales.

## Ejemplos

### Forma explícita recomendada

```bash
just configure-java-mise --version 25 --apply
java --version
mise current java
```

### Ruta directa exacta

```bash
just configure-java-mise \
  --version 25 \
  --path "$HOME/.local/share/java-runtimes/temurin/jdk-25.0.4.1+1-jdk" \
  --apply
```

### Diagnóstico y plan

```bash
just configure-java-mise --version 25 --check
just configure-java-mise --version 25 --plan
```

## Protecciones de seguridad

- No usa `sudo` ni modifica Java del sistema.
- No elimina instalaciones anteriores.
- Rechaza rutas relativas o que contengan `..`.
- Crea un respaldo fechado de `~/.config/mise/config.toml` antes de cambiarlo.
- Solo configura `java@temurin-VERSION` y apunta al directorio recibido o detectado.

## Fallos conocidos

### `no se encontró Temurin JDK 25`

**Causa:** todavía no se instaló Temurin o la ruta no coincide con el patrón.

**Solución:** instala el runtime con `just install-java-runtime ... --apply` o
proporciona `--path` con la ruta exacta.

### `mise no está instalado`

**Causa:** el binario no está en `~/.local/bin/mise` ni en `PATH`.

**Solución:** ejecuta `just install-terminal-workstation --apply --stage runtimes`.

### `java --version` continúa mostrando GraalVM

**Causa:** la shell actual conserva el entorno anterior o existe un `JAVA_HOME`
exportado manualmente.

**Solución:** ejecuta `reload-bash`, abre una shell nueva y verifica `type -a java`
y `mise current java`.

## Changelog

### [Unreleased]

- **feat:** registrar Temurin en mise usando el directorio versionado real.

