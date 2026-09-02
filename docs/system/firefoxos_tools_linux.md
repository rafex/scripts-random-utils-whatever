---
title: firefoxos_tools_linux.sh
description: Diagnóstico y lectura controlada de Firefox OS por USB sin shell remoto.
tags:
  - sistema
  - firefox-os
  - usb
  - laboratorio
---

# firefoxos_tools_linux.sh

Helper separado del flujo Android para diagnosticar un teléfono Firefox OS
legado por USB y, únicamente cuando ADB está autorizado, listar o extraer
archivos hacia un directorio privado del usuario.

- **Ruta:** `scripts/system/firefoxos_tools_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `adb`, `lsusb`, `lsblk`, `readlink`, `stat`; `gio` es opcional para GVfs/MTP.

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

No se requiere otro paquete para esta fase: la ThinkPad ya cuenta con ADB,
`android-udev-rules`, `scrcpy`, GVfs y `libmtp-runtime` desde la instalación
Android. El helper debe ejecutarse como `rafex`, nunca con `sudo`.

El teléfono debe exponer el perfil de depuración de Firefox OS. En el teléfono:

1. Abre **Settings → Device Information → More Information**.
2. Activa **Developer Menu**.
3. Entra en **Developer → Debugging via USB**.
4. Selecciona **ADB and DevTools** y confirma la conexión.
5. Desconecta y vuelve a conectar el cable USB.

Este flujo histórico está descrito por [Mozilla B2G/QA](https://wiki.mozilla.org/B2G/QA/Automation/Style_Guide/Howtos).
Al terminar las pruebas, desactiva **Developer Menu** y la depuración USB.

## Uso

Desde el repositorio:

```bash
just firefoxos-tools --status
just firefoxos-tools --devices
just firefoxos-tools --list --remote /
just firefoxos-tools --pull --remote /data \
  --target ~/Documents/firefoxos-exports
```

El estado diferencia `sin USB`, `USB sin ADB`, `unauthorized`, `offline` y
`device`. No imprime números de serie en la salida normal.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | `--check` | Muestra herramientas, perfil USB, ADB, almacenamiento y protecciones. |
| `--devices` | — | Consulta estados ADB sin mostrar números de serie. |
| `--list` | — | Ejecuta únicamente `adb shell ls -la` sobre la ruta indicada. |
| `--pull` | — | Extrae una ruta mediante `adb pull` al directorio permitido. |
| `--remote <ruta>` | — | Ruta absoluta remota, obligatoria para `--list` y `--pull`. |
| `--target <directorio>` | — | Directorio bajo `~/Documents/firefoxos-exports`, obligatorio para `--pull`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El helper no lee variables de entorno de configuración ni archivos `.env`.
La raíz de exportación es fija:

```text
~/Documents/firefoxos-exports
```

Las rutas, el modo USB y la autorización se proporcionan explícitamente en el
teléfono o como argumentos de la acción.

## Ejemplos

### Forma explícita/recomendada

```bash
just firefoxos-tools --status
just firefoxos-tools --devices
just firefoxos-tools --list --remote /
mkdir -p ~/Documents/firefoxos-exports
just firefoxos-tools --pull --remote /data \
  --target ~/Documents/firefoxos-exports
```

### Diagnóstico USB sin ADB

```bash
lsusb -d 05c6:9025
lsusb -d 05c6:9026
lsusb -t
just firefoxos-tools --devices
```

Si el teléfono continúa como `File-CD Gadget` de `0B`, ese perfil no ofrece
archivos legibles ni una interfaz ADB. Cambia el modo desde el propio teléfono
y reconecta antes de tocar la configuración de la ThinkPad.

Al activar **ADB and DevTools**, algunos modelos Firefox OS cambian a
`05c6:9025`; el helper reconoce ambos perfiles conocidos y confirma la interfaz
ADB antes de permitir una lectura.

### Almacenamiento real o MTP

Si `lsblk` muestra un tamaño distinto de `0B`, usa Thunar o GVfs como usuario
normal. `gio`/`libmtp-runtime` permiten explorar un perfil MTP cuando el
teléfono lo ofrece; no se usa `mount`, `dd`, formateo ni reparación automática.

### Compatibilidad legacy

`~/.android/adb_usb.ini` solo se considerará manualmente si la interfaz ADB ya
aparece pero un cliente antiguo no reconoce el teléfono. El helper no modifica
ese archivo, no agrega identificadores automáticamente y no reemplaza el modo
USB seleccionado en el teléfono.

## Protecciones de seguridad

- Se ejecuta como usuario normal y no añade grupos ni reglas udev.
- No activa Developer Mode, ADB por Wi-Fi ni `adb tcpip`, `adb connect` o `adb pair`.
- No ofrece `adb shell` arbitrario, `adb push`, borrado, reinicio, `adb root`,
  `adb remount`, desbloqueo de bootloader ni flasheo mediante fastboot.
- `--list` solo usa el comando fijo `ls -la`; la ruta remota debe ser absoluta y
  no puede contener `..` ni caracteres de shell.
- `--pull` solo puede escribir bajo `~/Documents/firefoxos-exports`, cuya ruta
  se canoniza y se valida contra enlaces simbólicos y propiedad del usuario.
- La salida normal no muestra números de serie. El listado remoto puede mostrar
  nombres de archivos porque es una acción de lectura solicitada explícitamente.
- No se modifica USBGuard, NetworkManager, WWAN, hardening ni el helper Android.
- `scrcpy` es para Android y no es un método de lectura para Firefox OS.

Para depurar aplicaciones Firefox OS, WebIDE/B2G es una vía histórica. WebIDE
fue retirado de Firefox 71 y las versiones actuales no son compatibles
directamente; consulta [Firefox Source Docs: herramientas retiradas](https://firefox-source-docs.mozilla.org/devtools-user/deprecated_tools/index.html).
Usa un navegador legacy o una máquina virtual aislada, sin cuentas personales y
sin convertir versiones antiguas en navegador diario. Las aplicaciones Firefox
OS no son APK: suelen ser aplicaciones web hosted o empaquetadas compatibles
con B2G/WebIDE.

## Fallos conocidos

### `sin USB Firefox OS detectado`

**Causa:** el teléfono no está conectado, el cable no transmite datos o el
perfil USB cambió.

**Solución:** comprueba el cable, `lsusb` y vuelve a conectar el teléfono.

### `USB detectado, pero el perfil actual no expone ADB`

**Causa:** Firefox OS continúa en el perfil Qualcomm/QMI o almacenamiento
`File-CD Gadget` sin interfaz ADB.

**Solución:** selecciona **ADB and DevTools** en el teléfono y reconecta. El
teléfono puede aparecer como `05c6:9025` después del cambio. No
instales reglas udev adicionales para resolver este estado.

### `unauthorized` o `offline`

**Causa:** la autorización de depuración no fue aceptada o el enlace USB quedó
en un estado transitorio.

**Solución:** desbloquea el teléfono, confirma la autorización y reconecta.

### `se requiere exactamente un teléfono Firefox OS autorizado`

**Causa:** no hay un único dispositivo ADB en estado `device`, o hay más de uno.

**Solución:** deja conectado solo el teléfono de laboratorio y repite
`--devices`.

### `--target debe estar dentro de .../firefoxos-exports`

**Causa:** se intentó extraer hacia una ruta fuera del directorio privado
permitido.

**Solución:** usa un subdirectorio de `~/Documents/firefoxos-exports`.

### WebIDE no detecta el teléfono

**Causa:** WebIDE fue retirado de Firefox moderno y requiere herramientas B2G
legacy.

**Solución:** usa un perfil legacy aislado o una VM preparada manualmente; no
descargues binarios antiguos automáticamente ni uses ese navegador para cuentas
personales.

## Changelog

### [Unreleased]

- **feat:** añade diagnóstico USB, listado controlado y extracción segura para
  Firefox OS separado de Android.

### v1.0.0 — 2026-09-02

- **feat:** primera versión del helper de lectura Firefox OS por USB.
