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
legado por USB, generar un inventario técnico de solo lectura, verificar un
archivo local de base `v18D.zip` y, únicamente cuando ADB está autorizado,
listar o extraer archivos hacia un directorio privado del usuario.

- **Ruta:** `scripts/system/firefoxos_tools_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `adb`, `lsusb`, `lsblk`, `readlink`, `stat`; `sha512sum` y `unzip` son necesarios para `--verify-base`; `gio` es opcional para GVfs/MTP.

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
just firefoxos-tools --inventory
just firefoxos-tools --preflight
just firefoxos-tools --verify-base --archive ~/Downloads/v18D.zip
just firefoxos-tools --list --remote /
just firefoxos-tools --pull --remote /data \
  --target ~/Documents/firefoxos-exports
```

El estado diferencia `sin USB`, `USB sin ADB`, `unauthorized`, `offline` y
`device`. No imprime números de serie en la salida normal.

## Inventario y preflight

    just firefoxos-tools --inventory
    just firefoxos-tools --preflight

inventory es el primer diagnóstico recomendado después de autorizar ADB.
preflight añade la interpretación de compatibilidad, pero no prepara ni
descarga ninguna imagen. `verify-base` lee un ZIP que ya existe en el equipo,
comprueba su checksum y estructura, pero tampoco lo ejecuta ni lo instala.
Estas acciones no muestran números de serie.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | `--check` | Muestra herramientas, perfil USB, ADB, almacenamiento y protecciones. |
| `--devices` | — | Consulta estados ADB sin mostrar números de serie. |
| `--inventory` | — | Lee modelo, base, build, B2G/Gecko, Gaia, USB y almacenamiento del teléfono. |
| `--preflight` | — | Evalúa, sin modificar, la compatibilidad histórica con Firefox OS 2.5 y JanOS. |
| `--verify-base` | — | Verifica localmente el candidato histórico `v18D.zip`, sin reiniciar ni flashear. |
| `--list` | — | Ejecuta únicamente `adb shell ls -la` sobre la ruta indicada. |
| `--pull` | — | Extrae una ruta mediante `adb pull` al directorio permitido. |
| `--remote <ruta>` | — | Ruta absoluta remota, obligatoria para `--list` y `--pull`. |
| `--target <directorio>` | — | Directorio bajo `~/Documents/firefoxos-exports`, obligatorio para `--pull`. |
| `--archive <archivo>` | — | Archivo local, obligatorio para `--verify-base`; debe llamarse `v18D.zip`. |
| `--help` | `-h` | Muestra la ayuda. |

Acciones nuevas:

- inventory: lee modelo, base, build, B2G/Gecko, Gaia, USB y almacenamiento
  del teléfono.
- preflight: evalúa, sin modificar, la compatibilidad histórica con Firefox OS
  2.5 y JanOS.
- verify-base: verifica el checksum SHA512 y la estructura de una copia local
  de `v18D.zip`; no descarga, reinicia ni flashea.

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

### Verificación local de `v18D.zip`

La fase histórica seleccionada para este equipo es la base estable `v18D.zip`.
La suma SHA512 publicada en los archivos históricos de Firefox OS es:

```text
SHA512(v18D.zip)=2befa6d7c1202f8bc9e5dab75d644387cffa727b362ad0508981eac2a910f7dfbd3938d915d259476750d8a74af7de96c811788d35a1d3311d65e72ce5026076
```

Cuando consigas una copia por un medio externo, guárdala fuera del repositorio
y ejecuta:

```bash
just firefoxos-tools --verify-base --archive ~/Downloads/v18D.zip
```

El verificador exige el nombre exacto `v18D.zip`, calcula SHA512, prueba que el
ZIP sea legible, rechaza rutas internas peligrosas, busca `flash.sh`, revisa
que el script solo se inspeccione como texto y comprueba invocaciones de
`fastboot`, marcadores estructurales de Flame e imágenes de partición. El
`flash.sh` histórico no necesita contener el texto `Flame`: la identidad queda
confirmada por el checksum y el payload esperado. Un resultado verificado solo
significa que el archivo coincide con el artefacto histórico conocido; no
autoriza todavía reiniciar, entrar en fastboot o flashear.

La guía histórica de Mozilla describe `v18D.zip` como una base estable de
producción para Firefox OS 2.0 y confirma que las bases v180 y posteriores
usan Android KitKat. También advierte que el flasheo completo sobrescribe los
datos del teléfono:
[guía histórica de actualización](https://devdoc.net/web/developer.mozilla.org/en-US/Firefox_OS/Developer_phone_guide/Flame/Updating_your_Flame.html).

#### Candidato rechazado: `sjarb_android4.4r4`

El elemento de [Archive.org](https://archive.org/details/sjarb_android4.4r4)
contiene `android-x86-4.4-r4.iso`, una ISO para computadoras x86, no firmware
para el Mozilla Flame ARM/Qualcomm. El release oficial de
[Android-x86 4.4-r4](https://www.android-x86.org/releases/releasenote-4-4-r4.html)
confirma ese formato y arquitectura. No contiene `v18D.zip`, `flash.sh`,
particiones del Flame ni una imagen válida para `fastboot`; no debe usarse con
este teléfono. Puede ser útil únicamente como ISO para una máquina virtual
Android-x86 en la ThinkPad.

La existencia de un archivo en Archive.org o de un checksum SHA-1 no demuestra
compatibilidad con el Flame. Los mirrors comunitarios de firmware solo se
considerarán si corresponden al nombre esperado, tienen una fuente
identificable y coinciden con el checksum histórico. En la ThinkPad se
verificó una copia obtenida desde el archivo comunitario: el SHA512 confirma
que coincide con el artefacto histórico conocido, pero no elimina el riesgo
propio de haber usado un mirror de terceros.

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

### Lectura del estado actual

El Flame evaluado reporta:

- modelo Flame y dispositivo flame;
- base Android 4.3, build JLS36C y bootloader L1TC00011230, cuyo sufijo
  corresponde históricamente a una base v123;
- B2G/Gecko 28.0, con una build de 2014;
- perfil USB 05c6:9025 con ADB autorizado.

Estos datos describen el teléfono conectado; no significan que Firefox OS 2.5
ni JanOS estén instalados. La interpretación de la base es histórica y debe
confirmarse antes de cualquier operación futura.

### Qué significa el preflight

Firefox OS 2.5 fue una plataforma histórica basada en Gaia 2.5 y Gecko 44,
por lo que no se trata de una actualización OTA moderna. La documentación
histórica del Flame indica que las imágenes nuevas requerían primero una base
v180 o superior y advierte que el flasheo puede sobrescribir los datos:
[Firefox OS 2.5](https://wiki.mozilla.org/Firefox_OS/Releases/2.5) ·
[actualización histórica del Flame](https://devdoc.net/web/developer.mozilla.org/en-US/Firefox_OS/Developer_phone_guide/Flame/Updating_your_Flame.html).

La ruta comunitaria más concreta para este hardware es JanOS, que incluye
flame-kk entre sus dispositivos documentados, pero también exige una base
actualizada y advierte del borrado del teléfono:
[dispositivos JanOS](https://janos.io/device-list.html).

Con una base equivalente a v123, el preflight marcará pendiente la ruta 2.5 o
JanOS. No ejecutará reinicios para verificar recovery, no probará fastboot, no
descargará imágenes y no modificará particiones.

### Rutas que no se mezclan

- Conservar el sistema actual: inventario, listado y extracción controlada
  mediante ADB.
- Firefox OS 2.5: ruta histórica, no mantenida y potencialmente destructiva.
- JanOS: candidato comunitario experimental para Flame; una imagen disponible
  no se considera compatible hasta verificarla.
- Capyloon: no es candidato para este Flame; sus dispositivos actuales
  documentados son Pixel 3a y Android GSI
  ([Capyloon](https://capyloon.org/)).

Los proyectos oficiales Mozilla-B2G están archivados, por lo que esta
evaluación no representa soporte actual ni actualizaciones de seguridad:
[Mozilla-B2G](https://github.com/mozilla-b2g). Esta conclusión es una
inferencia del estado archivado de los repositorios y de la antigüedad de las
guías.

Ninguna ruta de actualización se ejecutará desde este helper. Antes de
considerar un procedimiento manual futuro se necesitarán una exportación
validada, una imagen exacta para Flame con checksum, un método de recuperación,
batería suficiente, cable estable y autorización explícita para borrar datos.

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

Las acciones inventory y preflight solo ejecutan consultas fijas: getprop,
lectura de archivos de versión y df. `verify-base` solo lee el archivo local y
lo inspecciona sin ejecutarlo. Ninguna de estas acciones ofrece shell remoto,
adb push, borrado, reinicio, root, remount, desbloqueo de bootloader ni
flasheo. Tampoco descargan imágenes ni modifican ADB, udev o USBGuard.

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

### la base histórica v123 es anterior a v180

**Causa:** el bootloader reportado corresponde al esquema histórico de base
v123. Las guías antiguas del Flame no consideran esa base apta para imágenes
posteriores.

**Solución:** no intentes actualizar desde este helper. Primero serían
necesarios una exportación validada, una imagen exacta para Flame, checksum,
recuperación confirmada y autorización separada para el posible borrado.

### no se puede verificar recovery sin reiniciar

**Causa:** comprobar recovery o fastboot requiere cambiar el estado de arranque
del teléfono y ya no sería una consulta completamente pasiva.

**Solución:** el preflight deja el dato como pendiente. No uses reboot,
desbloqueo de bootloader ni fastboot como parte de la evaluación actual.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.2.1 — 2026-09-02

- **fix:** valida `v18D.zip` por su checksum y sus marcadores estructurales de
  Flame; el `flash.sh` histórico no necesita contener la palabra `Flame`.

### v1.2.0 — 2026-09-02

- **feat:** añade verificación local del candidato histórico `v18D.zip` sin
  descarga, reinicio ni flasheo.
- **fix:** reconoce sufijos de bootloader alfanuméricos como `v18D` además de
  bases numéricas como `v123`.
- **docs:** registra el candidato Android-x86 de Archive.org como incompatible
  con el Flame.

### v1.1.0 — 2026-09-02

- **feat:** añade consultas fijas de modelo, base, B2G/Gecko, Gaia,
  almacenamiento y configuración USB.
- **docs:** documenta Firefox OS 2.5, JanOS, Capyloon y los prerrequisitos de
  cualquier futura actualización.

### v1.0.0 — 2026-09-02

- **feat:** primera versión del helper de lectura Firefox OS por USB.
