---
title: scrape_java_runtimes.py
description: Consulta de runtimes Java oficiales
tags:
  - instalación
---

# scrape_java_runtimes.py

Consulta los catálogos y enlaces oficiales de Eclipse Temurin, GraalVM Community, Oracle GraalVM e IBM Semeru para Linux y devuelve metadatos JSON verificables.

- **Ruta:** `scripts/install/scrape_java_runtimes.py`
- **SO requerido:** Linux
- **Dependencias:** Python 3 y acceso HTTPS; solo usa la biblioteca estándar

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

El equipo debe poder acceder por HTTPS a las fuentes oficiales. El scraper no solicita credenciales y no necesita `sudo`.

Fuentes consultadas:

- [Eclipse Temurin releases](https://adoptium.net/es/temurin/releases) y [Adoptium API](https://api.adoptium.net/).
- [GraalVM downloads](https://www.graalvm.org/downloads/) y [releases oficiales de GraalVM Community](https://github.com/graalvm/graalvm-ce-builds/releases/).
- [IBM Semeru downloads](https://developer.ibm.com/languages/java/semeru-runtimes/downloads/).

## Uso

Desde la raíz del repositorio:

```bash
just scrape-java-runtimes --provider all --version latest --pretty
```

La salida contiene el enlace de descarga, versión resuelta, nombre de archivo, checksum SHA-256 y enlace del checksum. `graalvm-community` usa sus releases oficiales de GitHub; `graalvm-oracle` usa la página oficial de Oracle y el enlace de descarga de Oracle.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--provider NOMBRE` | — | `all`, `temurin`, `graalvm-community`, `graalvm-oracle` o `semeru` |
| `--version VERSION` | — | `latest`, una versión mayor o una versión exacta según el proveedor |
| `--image jdk\|jre` | — | Tipo de imagen; GraalVM solo ofrece `jdk` |
| `--architecture x64\|aarch64` | — | Arquitectura Linux; por defecto detecta la local |
| `--timeout SEGUNDOS` | — | Timeout HTTP por solicitud; predeterminado: `30` |
| `--pretty` | — | Formatea el JSON para lectura humana |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

No usa variables de entorno para seleccionar versiones. Las opciones de línea de comandos tienen toda la configuración.

## Ejemplos

```bash
# Temurin LTS 21 JDK
just scrape-java-runtimes --provider temurin --version 21 --image jdk --pretty

# Temurin JRE 17
just scrape-java-runtimes --provider temurin --version 17 --image jre --pretty

# GraalVM Community más reciente
just scrape-java-runtimes --provider graalvm-community --version latest --pretty

# GraalVM Oracle actual
just scrape-java-runtimes --provider graalvm-oracle --version latest --pretty

# IBM Semeru JDK más reciente
just scrape-java-runtimes --provider semeru --version latest --image jdk --pretty
```

## Protecciones de seguridad

- Solo acepta URLs HTTPS y verifica que las redirecciones finales continúen en HTTPS.
- No ejecuta instaladores remotos ni `curl | bash`.
- No devuelve secretos ni credenciales.
- Los checksums se entregan al instalador para verificarse antes de extraer el archivo.

## Fallos conocidos

### `no se encontró un checksum válido`

**Causa:** el proveedor cambió la estructura de su página o no publicó el checksum para ese artefacto.

**Solución:** revisar la página oficial y esperar una actualización del scraper; no instalar el archivo sin checksum.

### `Oracle GraalVM admite únicamente latest`

**Causa:** los enlaces archivados de Oracle no tienen un catálogo estable común con el endpoint usado para la versión actual.

**Solución:** usar `graalvm-community` para versiones archivadas o descargar una versión Oracle específica verificándola manualmente.

## Changelog

### [Unreleased]

- **feat:** consultar Temurin, GraalVM Community/Oracle e IBM Semeru con checksums SHA-256.
