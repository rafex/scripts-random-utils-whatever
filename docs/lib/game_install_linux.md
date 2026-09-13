---
title: game_install_linux.sh
description: Biblioteca interna compartida por instaladores de juegos Linux
tags:
  - biblioteca
  - instalación
---

# game_install_linux.sh

Biblioteca interna usada por los instaladores de Xonotic y Urban Terror.

- **Ruta:** `scripts/lib/game_install_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `unzip`, `zipinfo`, `sha256sum`, `file`, `ldd`, `realpath`

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

No se ejecuta directamente. Los instaladores consumidores definen la versión, el checksum, la raíz esperada y los paquetes Debian.

## Uso

Los consumidores cargan la biblioteca y llaman a `gi_main` después de definir sus variables `GI_*`.

## Opciones

La interfaz pública está documentada en [Xonotic](../install/install_xonotic_linux.md) y [Urban Terror](../install/install_urban_terror_linux.md).

## Variables de entorno

Las variables `GI_*` son internas de los instaladores y no forman una interfaz de usuario.

## Ejemplos

No debe invocarse directamente; usa las tareas Just de cada juego.

## Protecciones de seguridad

Centraliza la validación de ZIP, checksums, extracción temporal, publicación atómica, detección de dependencias y rollback para evitar divergencias entre instaladores.

## Fallos conocidos

### Ejecución directa de la biblioteca

**Causa:** no contiene la configuración concreta de un juego.

**Solución:** usa `just install-xonotic ...` o `just install-urban-terror ...`.

## Changelog

### [Unreleased]
- Biblioteca compartida para instalaciones de juegos rootless.

