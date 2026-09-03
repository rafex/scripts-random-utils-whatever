---
title: firefoxos_flash_nightly_linux.sh
description: Verificación y flasheo controlado de la base v18D nightly v5 para Firefox OS 2.6 en Mozilla Flame.
tags:
  - sistema
  - firefox-os
  - fastboot
  - laboratorio
---

# firefoxos_flash_nightly_linux.sh

Wrapper separado para verificar y, con confirmación interactiva, escribir la
base histórica `v18D_nightly_v5` de Firefox OS 2.6 en un Mozilla Flame. No
ejecuta el `flash.sh` incluido en la descarga.

- **Ruta:** `scripts/system/firefoxos_flash_nightly_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `fastboot`, `sha512sum`, `unzip`, `readlink`, `mktemp`, `stat`.

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

La imagen debe llamarse exactamente `v18D_nightly_v5.zip` y coincidir con el
SHA512 histórico publicado:

```text
f92123446f71289dd0ea23b0c602f8a192267fbfcf2f25682cbc072f8bbe3e8b795aea3305ba6ea6cc504d252f1d895b07704b5b65700fcf3760e1386b89c431
```

El archivo debe estar fuera del repositorio, por defecto en:

```text
/tmp/v18D_nightly_v5.zip
```

El teléfono debe ser un Mozilla Flame/Flame KK y `fastboot` debe funcionar
como usuario normal. En el Flame histórico, `fastboot getvar product` puede
devolver `MSM8610`; solo se acepta junto con el protocolo `version: 0.5`.

Esta operación borra los datos del usuario mediante `userdata.img`. Por
decisión explícita, no se realiza backup. `modemst1` y `modemst2` se conservan
para reducir el riesgo de perder calibración o estado del módem.

## Uso

Desde el repositorio:

```bash
just firefoxos-flash-nightly --status
just firefoxos-flash-nightly --check --archive /tmp/v18D_nightly_v5.zip
just firefoxos-flash-nightly --plan --archive /tmp/v18D_nightly_v5.zip
```

La guía histórica de Mozilla identifica `v18D_nightly_v5` como la base de
Firefox OS 2.6 y publica el checksum anterior:
[guía histórica del Flame](https://devdoc.net/web/developer.mozilla.org/en-US/Firefox_OS/Developer_phone_guide/Flame/Updating_your_Flame.html).

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra disponibilidad de fastboot, cantidad de dispositivos e imagen esperada. |
| `--check` | — | Verifica SHA512, integridad, rutas y particiones del ZIP sin contactar el teléfono. |
| `--plan` | — | Muestra el orden de escritura sin contactar ni modificar el teléfono. |
| `--fastboot` | — | Valida un único Flame en fastboot y `max-download-size`; no escribe. |
| `--apply` | — | Escribe la base después de repetir las validaciones y exigir confirmación. |
| `--archive <archivo>` | — | Usa un ZIP local; por defecto `/tmp/v18D_nightly_v5.zip`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El wrapper no acepta variables de entorno para comandos, dispositivo,
particiones, rutas ni confirmaciones. Usa el `PATH` del sistema para localizar
`fastboot` y establece `LC_ALL=C` internamente para procesar su salida.

## Ejemplos

### Verificación recomendada

```bash
just firefoxos-flash-nightly --check --archive /tmp/v18D_nightly_v5.zip
just firefoxos-flash-nightly --plan --archive /tmp/v18D_nightly_v5.zip
```

### Prueba fastboot sin escribir

Con el teléfono en modo fastboot, mediante la combinación de botones o una
acción manual previa desde ADB:

```bash
just firefoxos-flash-nightly --fastboot --archive /tmp/v18D_nightly_v5.zip
```

Para regresar sin modificar particiones:

```bash
fastboot reboot
```

### Aplicación destructiva

Solo después de comprobar que el dispositivo fastboot es el Flame correcto:

```bash
just firefoxos-flash-nightly --apply --archive /tmp/v18D_nightly_v5.zip
```

La orden solicitará escribir exactamente:

```text
FLAME-V18D-NIGHTLY-V5-WIPE
```

El wrapper escribe `gpt_both0_big.bin`, las particiones de firmware y sistema,
`userdata.img` y `usbdisk.img`; no borra `modemst1` ni `modemst2` y reinicia al
terminar correctamente.

### Verificación posterior

Después del primer arranque, reactiva Developer Menu y ADB si el borrado los
deshabilitó:

```bash
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.product.device
adb shell getprop ro.bootloader
adb shell getprop ro.build.version.release
adb shell df /system
just firefoxos-tools --inventory
just firefoxos-tools --preflight
```

## Protecciones de seguridad

- `--check`, `--plan` y `--fastboot` no escriben particiones.
- Solo acepta `v18D_nightly_v5.zip` con el SHA512 conocido.
- Prueba la integridad ZIP y rechaza rutas absolutas o traversal `..`.
- Exige la estructura `v18D_nightly_v5/` y las imágenes específicas de Flame.
- Usa `gpt_both0_big.bin`, que es la tabla de particiones de v5; no reutiliza el
  GPT normal de la base estable v18D.
- No ejecuta el `flash.sh` descargado, `adb kill-server` ni `adb reboot bootloader`.
- Exige exactamente un dispositivo fastboot identificado como Flame o como
  `MSM8610` con protocolo `0.5`.
- Comprueba `max-download-size` antes de solicitar confirmación y verifica que
  todas las imágenes caben en ese límite.
- Se detiene ante cualquier error de fastboot.
- No usa `sudo`, no imprime seriales y no ofrece selección de particiones.
- Conserva `modemst1` y `modemst2` deliberadamente.
- Extrae la imagen a un directorio temporal privado y lo elimina al salir.
- No se ejecuta ningún backup ni se conserva información de usuario.

El flasheo completo modifica la tabla GPT y puede dejar el teléfono sin
arrancar si se interrumpe. Mantén la ThinkPad conectada a corriente, usa un
cable directo, evita hubs y no suspendas el equipo. La guía histórica advierte
que algunos puertos USB 3 pueden fallar durante fastboot.

## Fallos conocidos

### `SHA512 no coincide`

**Causa:** archivo incompleto, alterado o de otro origen.

**Solución:** no lo flashees; conserva la copia validada y consigue otra fuente
que coincida con el checksum histórico.

### `se requiere exactamente un dispositivo en fastboot`

**Causa:** el teléfono sigue en ADB, no se detecta, o hay más de un dispositivo.

**Solución:** desconecta dispositivos adicionales y coloca manualmente el Flame
en fastboot. No uses `sudo` para ocultar el problema.

### `el dispositivo fastboot no se identificó como Flame`

**Causa:** el producto no es `flame`/`flame-kk`, ni `MSM8610` con protocolo
`version: 0.5`.

**Solución:** detén el procedimiento. No uses ROMs Motorola, Android genéricas
ni imágenes de otro modelo.

### `no se pudo consultar max-download-size en fastboot`

**Causa:** el bootloader no responde a la consulta o no devuelve un límite
numérico.

**Solución:** no continúes. Comprueba cable, puerto USB y fastboot; el wrapper
no asume un límite desconocido.

### `system.img excede max-download-size`

**Causa:** el bootloader no puede recibir una imagen de ese tamaño en una sola
operación segura.

**Solución:** no escribas la imagen. No cambies el orden ni uses otra imagen sin
validación específica para Flame.

### `confirmación incorrecta`

**Causa:** no se escribió exactamente el token de borrado.

**Solución:** el teléfono no fue modificado; revisa el archivo y vuelve a
ejecutar `--apply` solo cuando aceptes la pérdida de datos.

### `fastboot falló al escribir ...`

**Causa:** pérdida de USB/energía, error del bootloader o interrupción durante
el flasheo.

**Solución:** no repitas comandos al azar. Intenta fastboot con Volumen abajo +
Encendido y conserva la base v18D validada para una eventual recuperación.

## Changelog

### [Unreleased]

- **feat:** añade un wrapper específico para validar y flashear la base v18D nightly v5 de Firefox OS 2.6.
- **fix:** conserva `modemst1` y `modemst2` y valida `max-download-size` antes de escribir.

