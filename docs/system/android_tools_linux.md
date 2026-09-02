---
title: android_tools_linux.sh
description: Consulta teléfonos Android, instala APKs explícitas y abre scrcpy sin root.
tags:
  - sistema
  - android
  - laboratorio
---

# android_tools_linux.sh

Helper de usuario para consultar dispositivos Android, instalar una APK
individual de laboratorio o iniciar scrcpy. No es una consola ADB general.

- **Ruta:** `scripts/system/android_tools_linux.sh`
- **SO requerido:** Linux (Debian, X11 para scrcpy)
- **Dependencias:** `bash`, `adb`, `fastboot`, `scrcpy` y `realpath` para APKs.

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

Instala primero las herramientas:

```bash
just install-android-tools --apply
```

El teléfono debe tener la depuración USB activa y la huella RSA aceptada. El
helper exige exactamente un dispositivo autorizado para instalar APKs o abrir
scrcpy; no muestra el número de serie por defecto.

## Uso

```bash
just android-tools --status
just android-tools --devices
just android-tools --install-apk --path ~/Android/lab-apks/app.apk
just android-tools --install-apk --path ~/Android/lab-apks/app.apk --replace
just android-tools --scrcpy
```

La primera ejecución de `--devices`, `--install-apk` o `--scrcpy` puede iniciar
el servidor ADB del usuario. No se inicia durante `--status`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra herramientas, regla udev, USBGuard y grupos sin consultar dispositivos. |
| `--devices` | — | Cuenta estados Android sin imprimir números de serie. |
| `--install-apk` | — | Instala una APK individual mediante `adb install`. |
| `--path <archivo.apk>` | — | Ruta obligatoria del APK, propiedad del usuario actual. |
| `--replace` | `-r` | Solicita explícitamente `adb install -r` para actualizar una APK instalada. |
| `--scrcpy` | — | Abre scrcpy sin argumentos arbitrarios y sin `sudo`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `DISPLAY` | Sesión actual | Requerida por scrcpy para abrir la ventana X11. |
| `PATH` | Sistema | Se anteponen rutas estándar para localizar ADB y scrcpy. |

No se aceptan variables para comandos ADB, destinos, credenciales ni opciones
libres.

## Ejemplos

### Consultar dispositivos

```bash
just android-tools --devices
```

La salida informa cantidades `autorizados`, `no_autorizados`, `offline` y
`otros`, sin exponer identificadores.

### Instalar una aplicación de laboratorio

```bash
mkdir -p ~/Android/lab-apks
just android-tools --install-apk --path ~/Android/lab-apks/app.apk
```

Para actualizar explícitamente una aplicación existente:

```bash
just android-tools --install-apk \
  --path ~/Android/lab-apks/app.apk --replace
```

### Ver y controlar el teléfono

```bash
just android-tools --scrcpy
```

## Protecciones de seguridad

- El helper siempre se ejecuta como usuario normal; nunca usa `sudo`.
- Solo acepta una APK regular, legible, propiedad del usuario y fuera de rutas
  del sistema.
- `--replace` es necesario para actualizar una instalación existente.
- No concede permisos Android automáticamente.
- No ofrece `adb shell`, `adb root`, `adb remount`, borrado, extracción de
  datos, desbloqueo de bootloader ni comandos fastboot.
- No activa ADB por Wi-Fi ni modifica NetworkManager.
- Requiere exactamente un teléfono autorizado para evitar instalar una APK en
  el dispositivo equivocado.
- La APK debe provenir de un laboratorio propio o de una fuente confiable.
- `fastboot` puede modificar particiones; su uso manual requiere confirmar el
  modelo, el bootloader y un respaldo antes de ejecutar cualquier operación.

## Fallos conocidos

### `unauthorized`

**Causa:** falta aceptar la huella RSA en el teléfono.

**Solución:** desbloquea el teléfono, acepta la solicitud y repite
`just android-tools --devices`.

### `se requiere exactamente un teléfono Android autorizado`

**Causa:** hay cero dispositivos autorizados, o hay varios conectados.

**Solución:** deja conectado un solo teléfono autorizado para la instalación o
el uso de scrcpy.

### `el APK debe pertenecer al usuario actual`

**Causa:** el archivo fue creado por `root` u otra cuenta.

**Solución:** copia el APK a `~/Android/lab-apks/` como usuario normal y vuelve
a ejecutar la acción.

### `las APK divididas no funcionan como archivo individual`

**Causa:** algunas aplicaciones se distribuyen como varios APK relacionados.

**Solución:** esta primera versión solo acepta APK individuales. La instalación
de paquetes divididos queda como procedimiento manual y explícito fuera del
helper cerrado.

## Changelog

### [Unreleased]

- **feat:** añadir consulta de dispositivos, instalación explícita de APKs y
  lanzamiento seguro de scrcpy.
