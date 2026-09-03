---
title: firefoxos_hello_world_linux.sh
description: Valida, empaqueta y publica mediante Podman una aplicación Firefox OS local de ejemplo sin usar ADB.
tags:
  - sistema
  - firefox-os
  - laboratorio
---

# firefoxos_hello_world_linux.sh

Valida y empaqueta la aplicación `Rafex Hola Mundo` para un Mozilla Flame. Como
WebIDE ya no está disponible en Firefox moderno, también puede publicarla
temporalmente como aplicación hospedada desde un contenedor Podman rootless.
La publicación no instala la aplicación por ADB ni modifica directamente el
teléfono: la instalación se confirma desde el navegador del Flame.

- **Ruta:** `scripts/system/firefoxos_hello_world_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `python3`, `realpath`, `find`, `mktemp`, `zipfile` de Python; `podman` e `ip` solo para publicar.

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

El teléfono debe tener activado el navegador y, para el flujo USB histórico,
**Developer Menu** y **ADB and DevTools**. El flujo hospedado no necesita WebIDE
ni ADB: solo necesita que el Flame y la ThinkPad estén en la misma red local.
La IP prevista de la ThinkPad es `192.168.3.91`.

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

Para publicarla temporalmente como aplicación hospedada, el servidor genera una
página `install.html` y sirve el manifiesto con un origen de instalación
limitado. El contenido de la aplicación se monta en el contenedor en modo de
solo lectura:

```bash
just firefoxos-hello-world --plan
just firefoxos-hello-world --serve-podman
```

En el Flame abre:

```text
http://192.168.3.91:8765/install.html
```

Pulsa **Instalar en este Flame** y acepta la confirmación del teléfono. Para
detener el servidor:

```bash
just firefoxos-hello-world --publisher-status
just firefoxos-hello-world --stop-podman
```

El servidor se publica solamente en `192.168.3.91:8765`. No se abre UFW de
forma automática; si la conexión falla, se debe comprobar el firewall antes de
crear, de forma temporal y explícita, una regla limitada a la IP del teléfono.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida estructura, archivos permitidos y manifiesto sin escribir. |
| `--status` | — | Muestra el estado local de la aplicación sin crear el ZIP. |
| `--plan` | — | Muestra el plan del publicador Podman sin construir ni iniciar nada. |
| `--package` | — | Genera un ZIP reproducible de la aplicación. |
| `--output <archivo.zip>` | `-o` | Ruta de salida bajo `HOME` o `/tmp`; solo con `--package`. |
| `--force` | — | Permite reemplazar explícitamente el ZIP existente. |
| `--serve-podman` | — | Construye, si hace falta, e inicia el publicador rootless temporal. |
| `--publisher-status` | — | Muestra el estado de la imagen y del contenedor administrado. |
| `--stop-podman` | — | Detiene únicamente el contenedor administrado del publicador. |
| `--bind <ip>` | — | IP local donde se publica el servidor; predeterminada `192.168.3.91`. |
| `--port <puerto>` | — | Puerto TCP alto del servidor; predeterminado `8765`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `TMPDIR` | `/tmp` | Directorio usado para el ZIP predeterminado si está definido. |
| `PATH` | Rutas del sistema | Se anteponen rutas estándar para localizar `python3` y utilidades. |
| `PUBLIC_ORIGIN` | — | Solo es consumida dentro del contenedor; la tarea la fija como `http://192.168.3.91:8765`. |

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

### Publicación local aislada con Podman

```bash
just firefoxos-hello-world --check
just firefoxos-hello-world --plan --bind 192.168.3.91 --port 8765
just firefoxos-hello-world --serve-podman --bind 192.168.3.91 --port 8765
```

En el Flame visita `http://192.168.3.91:8765/install.html` y confirma la
instalación. La tarea verifica que `192.168.3.91` pertenezca a una interfaz
local y rechaza loopback, puertos privilegiados y direcciones no configuradas.

Detén el servicio al terminar:

```bash
just firefoxos-hello-world --stop-podman
```

### Verificar el paquete desde la ThinkPad

```bash
adb devices
just firefoxos-hello-world --status
```

El flujo preferido ya no necesita WebIDE: inicia el publicador Podman, abre
`http://192.168.3.91:8765/install.html` desde el Flame, pulsa el botón y acepta
la confirmación. Después abre la aplicación instalada y pulsa **Probar
interacción**.

Como alternativa histórica, un perfil legacy aislado o una máquina virtual con
WebIDE puede abrir el ZIP, seleccionar el Flame en **Select Runtime → USB
Devices** y ejecutarlo temporalmente con **Play**. El empaquetador no ejecuta
WebIDE, ADB ni fastboot.

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
- El publicador Podman usa una imagen rootless, `--read-only`, sin capacidades,
  sin privilegios nuevos, con límite de memoria/procesos y con la aplicación
  montada en modo `ro`.
- El servidor no usa `--network=host`, no accede a ADB y no expone más rutas que
  la página de instalación, el manifiesto y los cuatro archivos de la app.
- La aplicación hospedada se ofrece por HTTP únicamente en la red local; no se
  debe publicar en Wi-Fi pública ni abrirla a Internet.
- `--stop-podman` solo detiene un contenedor que tenga la etiqueta administrada
  `io.rafex.publisher=firefoxos-hello-world`.

## Fallos conocidos

### `WebIDE no detecta el teléfono`

**Causa:** WebIDE fue retirado de Firefox moderno o el Flame no tiene activo
**ADB and DevTools**.

**Solución:** usa un perfil legacy aislado o una VM, activa el modo de
desarrollo en el teléfono, acepta la autorización y reconecta el USB. El
helper `firefoxos-tools` permite diagnosticar el estado ADB sin instalar la
aplicación.

### `el Flame no puede abrir http://192.168.3.91:8765`

**Causa:** la IP no está en la misma red, la dirección no pertenece a la
ThinkPad o UFW bloquea la conexión entrante.

**Solución:** ejecuta `--publisher-status`, confirma que el publicador esté
activo y comprueba la conectividad desde una red local autorizada. El script no
modifica UFW; si hace falta, crea una regla temporal restringida al teléfono y
elimínala al terminar.

### `navigator.mozApps no está disponible`

**Causa:** la página se abrió en un navegador moderno o en una versión que no
expone la API histórica de instalación de Firefox OS.

**Solución:** abre la URL desde el navegador del Flame con Firefox OS 2.6. El
ZIP seguirá disponible para una herramienta WebIDE legacy o un flujo histórico
de depuración remota.

### `ya existe un contenedor no administrado con el nombre rafex-firefoxos-hello`

**Causa:** el instalador evita detener o reemplazar contenedores que no creó.

**Solución:** inspecciona el conflicto manualmente y usa otro nombre fuera de
este helper, o retíralo manualmente solo después de confirmar su propietario.

### `la imagen Podman no puede construirse`

**Causa:** la primera publicación necesita descargar la imagen base oficial de
Python y puede estar bloqueada por red o por el registro de contenedores.

**Solución:** ejecuta primero `podman pull docker.io/library/python:3.13-alpine`
en una sesión autorizada y repite `--serve-podman`. La tarea no usa `sudo` ni
instala Podman en el host.

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

### v1.1.0 — 2026-09-02

- **feat:** añade publicación hospedada temporal mediante contenedor Podman
  rootless para sustituir el flujo dependiente de WebIDE.
