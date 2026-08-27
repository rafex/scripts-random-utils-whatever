---
title: install_eclipse_ide_linux.sh
description: Instalación de Eclipse IDE oficial
tags:
  - instalación
---

# install_eclipse_ide_linux.sh

Descarga, verifica e instala la versión vigente de Eclipse IDE para Java o
Enterprise Java/Web desde las páginas oficiales de Eclipse.

- **Ruta:** `scripts/install/install_eclipse_ide_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `python3`, `dpkg`, `sudo`; el script instala `ca-certificates`, `wget`, `tar` y `default-jre` si faltan

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

- Debian con `apt-get`, `dpkg` y arquitectura `amd64` o `arm64`.
- `sudo` configurado para el usuario actual.
- Conectividad HTTPS a Eclipse.org y sus espejos de descarga.
- Ejecutar como usuario normal, no como root.

El ThinkPad x86_64 debe utilizar `--package jee` para Enterprise Java/Web o
`--package java` para el paquete estándar.

## Uso

Diagnosticar sin cambios:

```sh
just install-eclipse-ide --package jee --check
```

Revisar la versión, archivo y SHA-512 detectados:

```sh
just install-eclipse-ide --package jee --plan
```

Descargar e instalar Enterprise Java/Web:

```sh
just install-eclipse-ide --package jee --apply
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica la instalación sin modificar nada |
| `--plan` | `--dry-run` | Consulta Eclipse y muestra las acciones sin modificar el sistema |
| `--apply` | — | Descarga, verifica e instala Eclipse |
| `--package <tipo>` | — | `java` o `jee`; default: `jee` |
| `--prefix <directorio>` | — | Directorio absoluto de instalación; default: `/opt/eclipse-<tipo>` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza variables de entorno para URLs, versiones, contraseñas
ni tokens. La versión se obtiene en cada ejecución desde Eclipse.org.

## Ejemplos

### Enterprise Java/Web en la ubicación predeterminada

```sh
just install-eclipse-ide --package jee --apply
```

### Java estándar en una ubicación personalizada

```sh
just install-eclipse-ide --package java --prefix /opt/eclipse-java --apply
```

### Lanzadores creados

```sh
/usr/local/bin/eclipse-jee
/usr/local/bin/eclipse-java
```

También se crea un archivo `.desktop` para el menú de aplicaciones de i3.

## Protecciones de seguridad

- Usa el scraper local `scrape_eclipse_packages.py` para consultar las páginas
  oficiales de Eclipse y obtener el archivo vigente.
- Verifica el SHA-512 publicado por Eclipse antes de extraer el archivo.
- Rechaza arquitecturas no publicadas por Eclipse.
- Solicita la contraseña de sudo únicamente mediante `sudo -v`.
- Respaldará una instalación anterior en
  `/var/backups/rafex-eclipse-ide/` antes de reemplazarla.
- Valida `--prefix` y rechaza directorios raíz o protegidos.
- No modifica particiones, `fstab`, GRUB ni archivos de credenciales.

## Fallos conocidos

### `no se encontró descarga Linux <arquitectura>`

**Causa:** Eclipse no publica ese paquete para la arquitectura solicitada o la
estructura de la página cambió.

**Solución:** ejecuta `just scrape-eclipse-packages --package all --pretty` y
revisa los paquetes y arquitecturas disponibles.

### `SHA-512 inesperado`

**Causa:** el archivo descargado no coincide con la suma publicada por Eclipse.

**Solución:** no se instala el archivo. Comprueba la conectividad, repite la
descarga más tarde y conserva el respaldo anterior.

### Eclipse no inicia desde el menú

**Causa:** falta un JVM del sistema visible para aplicaciones gráficas.

**Solución:** el instalador intenta instalar `default-jre` si no existe
`/usr/bin/java`; también puedes validar `java -version` y ejecutar el lanzador
de terminal para ver el error.

## Changelog

### [Unreleased]

- **feat:** instalar Eclipse IDE Java y Enterprise Java/Web desde el archivo
  oficial vigente y su checksum SHA-512.
