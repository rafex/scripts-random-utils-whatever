---
title: install_android_tools_linux.sh
description: Instala ADB, fastboot, scrcpy y reglas udev Android en Debian.
tags:
  - instalación
  - android
  - thinkpad
---

# install_android_tools_linux.sh

Instala las herramientas Debian necesarias para administrar teléfonos Android
por USB, instalar APKs de laboratorio y abrir scrcpy sin ejecutar esas
operaciones como `root`.

- **Ruta:** `scripts/install/install_android_tools_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-cache`, `apt-get`, `dpkg-query`, `sudo` solo durante `--apply`.

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

- Debian con candidatos APT para `adb`, `fastboot`, `android-udev-rules` y
  `scrcpy`.
- Ejecutar el instalador como usuario normal con `sudo` disponible para
  `--apply`.
- El teléfono debe tener **Opciones de desarrollador → Depuración USB** activa.
- Después de instalar las reglas udev hay que desconectar y volver a conectar
  el teléfono.

Debian proporciona reglas udev que permiten que `adb` y `fastboot` funcionen
sin permisos de `root`. Android requiere además aceptar manualmente la huella
RSA en el teléfono: [Android Debug Bridge](https://developer.android.com/tools/adb).

## Uso

```bash
just install-android-tools --check
just install-android-tools --plan
just install-android-tools --apply
just install-android-tools --status
```

La instalación es independiente de `install-profile` y no instala Android
Studio ni el SDK completo.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquetes, candidatos y conflictos sin modificar nada. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin ejecutar `sudo`. |
| `--apply` | — | Instala paquetes y recarga las reglas udev mediante `sudo`. |
| `--status` | — | Muestra paquetes, regla udev, USBGuard y política de grupos. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. El usuario se obtiene de la sesión que
ejecuta el instalador y no se añade a `plugdev`, `input` ni grupos
administrativos.

## Ejemplos

### Instalación recomendada

```bash
just install-android-tools --check
just install-android-tools --plan
just install-android-tools --apply
```

### Verificación posterior

```bash
just install-android-tools --status
adb version
fastboot --version
scrcpy --version
```

### Preparar un teléfono

1. Activa las opciones de desarrollador y la depuración USB.
2. Conecta el cable USB y acepta la huella RSA en la pantalla del teléfono.
3. Ejecuta `just android-tools --devices`.

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- `--apply` usa `sudo` únicamente para APT y recargar udev.
- No se inicia el servidor ADB automáticamente.
- No se habilita ADB por Wi-Fi ni se ejecutan `adb tcpip`, `adb connect` o
  `adb pair`.
- No se añaden grupos, reglas udev locales ni permisos administrativos.
- Si existe un paquete antiguo de reglas Android potencialmente conflictivo, el
  instalador se detiene y no lo elimina automáticamente.
- USBGuard puede bloquear un teléfono nuevo; el instalador no lo autoriza por
  sí mismo.

## Fallos conocidos

### `no hay un teléfono Android autorizado conectado`

**Causa:** el teléfono no está conectado, la depuración USB está desactivada o
la huella RSA todavía no fue aceptada.

**Solución:** desbloquea el teléfono, activa la depuración USB, acepta la
solicitud RSA y vuelve a conectar el cable.

### `se detectó ... android-sdk-platform-tools-common`

**Causa:** existe una instalación antigua de reglas Android que puede entrar en
conflicto con `android-udev-rules` de Debian.

**Solución:** revisa y retira o actualiza ese paquete manualmente. El script no
lo desinstala ni modifica sus archivos.

### `adb muestra unauthorized`

**Causa:** el teléfono no ha autorizado a esta computadora.

**Solución:** confirma la huella RSA en la pantalla del teléfono. No se debe
copiar una huella de otro equipo.

### `scrcpy requiere una sesión gráfica X11`

**Causa:** se ejecutó desde una terminal SSH sin `DISPLAY` o fuera de i3/Openbox.

**Solución:** abre scrcpy desde la sesión gráfica local.

## Changelog

### [Unreleased]

- **feat:** añadir instalador Debian de ADB, fastboot, scrcpy y reglas udev sin
  grupos adicionales ni ADB por red.
