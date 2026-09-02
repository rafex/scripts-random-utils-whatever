---
title: firefoxos_flash_base_linux.sh
description: Verificación y flasheo controlado de la base v18D en un Mozilla Flame.
tags:
  - sistema
  - firefox-os
  - fastboot
  - laboratorio
---

# firefoxos_flash_base_linux.sh

Wrapper separado para verificar y, con confirmación interactiva, escribir la
base histórica `v18D` en un Mozilla Flame. No ejecuta el `flash.sh` incluido en
la descarga.

- **Ruta:** `scripts/system/firefoxos_flash_base_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `adb`, `fastboot`, `sha512sum`, `unzip`, `readlink`, `mktemp`.

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

La imagen debe llamarse exactamente `v18D.zip`, estar fuera del repositorio y
coincidir con este SHA512:

```text
2befa6d7c1202f8bc9e5dab75d644387cffa727b362ad0508981eac2a910f7dfbd3938d915d259476750d8a74af7de96c811788d35a1d3311d65e72ce5026076
```

El teléfono debe ser un Mozilla Flame y ADB/fastboot deben funcionar como
usuario normal. No se debe usar `sudo` con este wrapper.

Antes de aplicar se necesita una exportación validada de los datos accesibles
mediante ADB. La exportación no equivale a una imagen completa del teléfono.

## Uso

Desde el repositorio:

```bash
just firefoxos-flash-base --status
just firefoxos-flash-base --check --archive /tmp/v18D.zip
just firefoxos-flash-base --plan --archive /tmp/v18D.zip
```

Después de validar la exportación, coloca manualmente el teléfono en fastboot
con `adb reboot bootloader` o con **Volumen abajo + Encendido**, y comprueba:

```bash
just firefoxos-flash-base --fastboot
```

El wrapper no entra automáticamente en fastboot y no escribe nada con
`--fastboot`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra herramientas, imagen y cantidades ADB/fastboot sin seriales. |
| `--check` | — | Verifica SHA512, integridad, rutas y archivos requeridos del ZIP. |
| `--plan` | — | Muestra el orden de particiones sin contactar ni modificar el teléfono. |
| `--fastboot` | — | Comprueba un único dispositivo fastboot identificado como Flame. |
| `--apply` | — | Escribe la base v18D después de exigir confirmación interactiva de borrado. |
| `--archive <archivo>` | — | Usa un ZIP local; por defecto `/tmp/v18D.zip`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El wrapper no acepta variables para comandos, dispositivo, particiones,
destinos ni confirmaciones. Usa el `PATH` del sistema con rutas administrativas
estándar antepuestas para localizar `adb` y `fastboot`.

## Ejemplos

### Verificación recomendada

```bash
just firefoxos-flash-base --check --archive /tmp/v18D.zip
just firefoxos-flash-base --plan --archive /tmp/v18D.zip
```

### Prueba de fastboot sin escribir

```bash
adb devices
adb reboot bootloader
just firefoxos-flash-base --fastboot
fastboot reboot
```

### Aplicación destructiva

Solo después de exportar y validar los datos:

```bash
just firefoxos-flash-base --apply --archive /tmp/v18D.zip
```

La orden exige escribir exactamente `FLAME-V18D-WIPE` en un terminal
interactivo. El orden es: GPT, modem, RPM, TZ, SBL1, SDI, FSG, aboot, boot,
system, persist, recovery, cache, userdata, usbmsc, borrado de `modemst1` y
`modemst2`, y reinicio.

### Restauración de lectura después del arranque

```bash
just firefoxos-tools --inventory
just firefoxos-tools --preflight
```

## Protecciones de seguridad

- Solo acepta el nombre `v18D.zip` y el SHA512 histórico conocido.
- Prueba la integridad ZIP y rechaza rutas absolutas o traversal `..`.
- Exige los archivos de partición y marcadores estructurales específicos de Flame.
- Nunca ejecuta `flash.sh`, `adb kill-server` ni `adb logcat` del archivo.
- No reinicia el teléfono desde ADB automáticamente.
- Exige exactamente un dispositivo fastboot.
- Verifica que el producto fastboot sea `flame` o `flame-kk`.
- No imprime seriales ni usa `sudo`.
- `--check`, `--plan` y `--fastboot` no escriben particiones.
- `--apply` exige un terminal interactivo y la confirmación exacta del borrado.
- Se detiene ante cualquier error y no intenta una recuperación automática.
- Extrae la imagen a un directorio temporal privado y lo elimina al terminar.

El flasheo sobrescribe datos, tabla GPT, sistema, recuperación, módem y otras
particiones. Una interrupción puede dejar el teléfono sin arrancar. Mantén
corriente estable, cable directo y evita hubs; la guía histórica advierte que
algunos puertos USB 3 pueden fallar durante fastboot.

## Fallos conocidos

### `no hay un dispositivo en fastboot`

**Causa:** el teléfono continúa en modo ADB, el cable/puerto no fue detectado,
o las reglas udev/USBGuard no permiten el perfil fastboot.

**Solución:** entra en fastboot, prueba otro cable o puerto USB, preferentemente
USB 2, y repite `--fastboot`. No uses `sudo` para ocultar el problema.

### `el dispositivo fastboot no se identificó como Flame`

**Causa:** el producto no es `flame`/`flame-kk` o no pudo consultarse.

**Solución:** detén el procedimiento. No flashees ROMs Motorola, Android
genéricas ni imágenes de otro modelo.

### `SHA512 no coincide`

**Causa:** archivo incompleto, alterado o de otro origen.

**Solución:** no lo ejecutes ni lo extraigas para flashear; consigue otra copia
y verifica nuevamente el SHA512.

### `confirmación incorrecta`

**Causa:** no se escribió exactamente `FLAME-V18D-WIPE`.

**Solución:** el teléfono no fue modificado. Revisa la exportación y vuelve a
ejecutar `--apply` solo cuando aceptes el borrado.

### `flasheo interrumpido o el teléfono no arranca`

**Causa:** pérdida de USB/energía o error de una partición durante una operación
destructiva.

**Solución:** no repitas comandos al azar. Intenta fastboot con Volumen abajo +
Encendido. Si no responde, la recuperación histórica requiere una herramienta
de emergencia de Windows y un cable especial; no se garantiza recuperación con
este wrapper.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.0.0 — 2026-09-02

- **feat:** añade verificación, plan y flasheo controlado de `v18D.zip`.
- **fix:** evita ejecutar el `flash.sh` histórico sin `set -e`.
- **docs:** documenta las puertas de exportación, fastboot y confirmación de borrado.
