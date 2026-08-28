---
title: install_java_runtime_linux.sh
description: Instalación local de runtimes Java oficiales
tags:
  - instalación
---

# install_java_runtime_linux.sh

Descarga, verifica e instala un JDK o JRE oficial en el espacio del usuario, sin reemplazar el Java del sistema. Al instalar cualquier proveedor Java soportado, mantiene `JAVA_HOME` mediante el enlace estable `~/.local/share/java-runtimes/current-java` y registra la ruta manual en `mise` sin permitir que `mise` descargue runtimes.

- **Ruta:** `scripts/install/install_java_runtime_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, Python 3, `curl`, `tar` y `sha256sum`

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

Ejecutar desde la raíz del repositorio en la ThinkPad:

```bash
sudo apt-get install python3 curl ca-certificates tar coreutils
```

El instalador no usa `sudo`; la línea anterior solo prepara dependencias si faltan. El scraper consulta las fuentes oficiales y el instalador guarda los archivos en:

```text
~/.local/share/java-runtimes/<proveedor>/<versión>-<imagen>/
```

El enlace activo queda como `current-<proveedor>-<imagen>`.

## Uso

```bash
just install-java-runtime --provider temurin --version 25 --image jdk --apply
```

Después de instalar, el script registra automáticamente Temurin, GraalVM Community, Oracle GraalVM o Semeru en el backend correspondiente de `mise` si está disponible, ejecutando únicamente `mise link`, `mise use` y `mise reshim`. También actualiza el manifiesto propio y `current-java`. Para omitir el registro automático usa `--no-mise`; en ese caso el runtime queda instalado localmente, pero no estará disponible para `runtime-use` hasta integrarlo.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el runtime activo y las instalaciones locales |
| `--plan` | `--dry-run` | Consulta metadatos y muestra lo que se instalaría; no descarga ni escribe |
| `--apply` | — | Descarga, verifica SHA-256, extrae y activa el runtime |
| `--provider NOMBRE` | — | `temurin`, `graalvm-community`, `graalvm-oracle` o `semeru` |
| `--version VERSION` | — | `latest`, versión mayor o exacta según proveedor |
| `--image jdk\|jre` | — | Imagen a instalar; GraalVM solo admite `jdk` |
| `--root DIRECTORIO` | — | Cambia la raíz local; debe ser absoluta y segura |
| `--no-mise` | — | No registra automáticamente el proveedor instalado en `mise` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Base del valor predeterminado | Determina `~/.local/share/java-runtimes`; no se sobrescribe desde el script |
| `TMPDIR` | Sistema | Directorio padre para temporales de descarga |

No se usa `.env`.

## Ejemplos

```bash
# Revisar estado sin cambiar nada
just install-java-runtime --provider temurin --version 21 --check

# Ver el plan, sin descargar
just install-java-runtime --provider temurin --version 17 --plan

# Instalar Temurin 25 y dejarlo como Java activo mediante current-java
just install-java-runtime --provider temurin --version 25 --image jdk --apply

# Instalar GraalVM Community actual
just install-java-runtime --provider graalvm-community --version latest --apply

# Instalar IBM Semeru JDK actual
just install-java-runtime --provider semeru --version latest --image jdk --apply

# Instalar Oracle GraalVM actual
just install-java-runtime --provider graalvm-oracle --version latest --apply
```

Verificación de la ruta estable:

```bash
export JAVA_HOME="$HOME/.local/share/java-runtimes/current-java"
export PATH="$JAVA_HOME/bin:$PATH"
readlink -f "$JAVA_HOME"
java -version
```

## Protecciones de seguridad

- Instalación únicamente dentro de una raíz local absoluta; se rechazan `/`, rutas con `..` y rutas terminadas en `/`.
- Verifica SHA-256 antes de extraer cualquier archivo.
- No usa `sudo`, no escribe `/usr/lib`, no modifica `update-alternatives`, `fstab`, GRUB ni contraseñas.
- `mise` solo recibe enlaces hacia instalaciones manuales; nunca se ejecuta `mise install`.
- Descarga con HTTPS, TLS 1.2 o superior y sin ejecutar contenido remoto.
- Si ya existe el destino, lo conserva como `.bak.<fecha>` antes de reemplazarlo.
- El archivo temporal se elimina al terminar.

## Fallos conocidos

### `no se pudieron obtener metadatos oficiales del runtime`

**Causa:** el catálogo del proveedor está temporalmente inaccesible, cambió o no tiene un binario para la arquitectura solicitada.

**Solución:** ejecutar primero el scraper con `--pretty`, revisar el proveedor y volver a intentarlo más tarde.

### `el archivo no contiene un JDK/JRE válido`

**Causa:** el archivo descargado no contiene `bin/java` en su directorio raíz.

**Solución:** no se activa el runtime; conserva el log y revisa el enlace oficial antes de reintentar.

## Changelog

### [Unreleased]

- **feat:** instalar localmente Temurin, GraalVM Community/Oracle e IBM Semeru con verificación SHA-256.
- **fix:** mantener `JAVA_HOME` en el enlace estable `current-java` y
  provisionar `runtime-use` después de una instalación exitosa.
