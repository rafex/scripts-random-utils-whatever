---
title: firefoxos_hello_world_linux.sh
description: Valida y empaqueta una aplicación Firefox OS local de ejemplo sin usar ADB.
tags:
  - sistema
  - firefox-os
  - laboratorio
---

# firefoxos_hello_world_linux.sh

Valida y empaqueta la aplicación `Rafex Hola Mundo` para probarla en un
Mozilla Flame mediante WebIDE legacy. No instala la aplicación ni modifica el
teléfono.

- **Ruta:** `scripts/system/firefoxos_hello_world_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `python3`, `realpath`, `find`, `mktemp`, `zipfile` de Python.

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

La aplicación está versionada en:

```text
examples/firefoxos/hello-world/
```

El teléfono debe tener activados **Developer Menu** y **ADB and DevTools**.
Para una prueba completa se necesita WebIDE legacy en un perfil aislado o una
máquina virtual. WebIDE fue retirado de Firefox moderno; no se recomienda
instalar un navegador antiguo sobre el perfil diario.

## Uso

Validar sin escribir:

```bash
just firefoxos-hello-world --check
just firefoxos-hello-world --status
```

Generar el paquete:

```bash
just firefoxos-hello-world --package \
  --output /tmp/rafex-firefoxos-hello-world.zip
```

El ZIP solo contiene el manifiesto, HTML, CSS y JavaScript de la aplicación.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida estructura, archivos permitidos y manifiesto sin escribir. |
| `--status` | — | Muestra el estado local de la aplicación sin crear el ZIP. |
| `--package` | — | Genera un ZIP reproducible de la aplicación. |
| `--output <archivo.zip>` | `-o` | Ruta de salida bajo `HOME` o `/tmp`; solo con `--package`. |
| `--force` | — | Permite reemplazar explícitamente el ZIP existente. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `TMPDIR` | `/tmp` | Directorio usado para el ZIP predeterminado si está definido. |
| `PATH` | Rutas del sistema | Se anteponen rutas estándar para localizar `python3` y utilidades. |

No se leen archivos `.env` ni se aceptan variables para ADB, WebIDE o comandos
de instalación.

## Ejemplos

### Forma explícita/recomendada

```bash
just firefoxos-hello-world --check
just firefoxos-hello-world --package \
  --output /tmp/rafex-firefoxos-hello-world.zip
unzip -t /tmp/rafex-firefoxos-hello-world.zip
```

### Verificar el paquete desde la ThinkPad

```bash
adb devices
just firefoxos-hello-world --status
```

Después abre el ZIP desde WebIDE legacy, selecciona el Flame en **Select
Runtime → USB Devices** y ejecuta la aplicación temporalmente con **Play**.
Pulsa **Probar interacción** y detén/elimina la aplicación temporal al
terminar. El empaquetador no ejecuta ninguno de esos pasos automáticamente.

### Repetir la generación de forma explícita

```bash
just firefoxos-hello-world --package \
  --output /tmp/rafex-firefoxos-hello-world.zip --force
```

## Protecciones de seguridad

- La aplicación no declara permisos ni tipo privilegiado.
- El script no ejecuta `adb`, `fastboot`, WebIDE ni comandos remotos.
- No usa `sudo` y no modifica el teléfono, ADB, USBGuard, udev o la red.
- El ZIP se genera únicamente con cuatro archivos versionados y sin enlaces
  simbólicos.
- Se rechazan archivos ocultos, rutas absolutas, componentes `..` y archivos
  adicionales dentro del ejemplo.
- La salida solo puede estar bajo el `HOME` del usuario o `/tmp`.
- No se guardan credenciales, claves, cookies, tokens ni datos del teléfono.
- Firefox OS no usa APK para este flujo; el paquete es una aplicación web
  empaquetada compatible con B2G/WebIDE.

## Fallos conocidos

### `WebIDE no detecta el teléfono`

**Causa:** WebIDE fue retirado de Firefox moderno o el Flame no tiene activo
**ADB and DevTools**.

**Solución:** usa un perfil legacy aislado o una VM, activa el modo de
desarrollo en el teléfono, acepta la autorización y reconecta el USB. El
helper `firefoxos-tools` permite diagnosticar el estado ADB sin instalar la
aplicación.

### `el archivo ya existe; usa --force`

**Causa:** el empaquetador evita reemplazar un ZIP existente por accidente.

**Solución:** elige otra salida o usa `--force` únicamente si confirmas que el
archivo es el paquete generado de esta aplicación.

### `la aplicación contiene archivos no permitidos`

**Causa:** se añadió un archivo, enlace simbólico o recurso no contemplado al
ejemplo.

**Solución:** conserva únicamente `manifest.webapp`, `index.html`, `style.css`
y `app.js`; los recursos nuevos deben incorporarse mediante un cambio
revisado del empaquetador.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.0.0 — 2026-09-02

- **feat:** añade una aplicación Firefox OS Hola Mundo en español y un
  empaquetador local reproducible sin ADB.
