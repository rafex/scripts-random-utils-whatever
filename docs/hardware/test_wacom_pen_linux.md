---
title: test_wacom_pen_linux.sh
description: Diagnóstico de pluma y dispositivos Wacom
tags:
  - hardware
---

# test_wacom_pen_linux.sh

Instala y diagnostica las herramientas necesarias para probar escritura,
presión e inclinación de la pluma Wacom en la ThinkPad X1 Yoga.

- **Ruta:** `scripts/hardware/test_wacom_pen_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `sudo`, `apt-get`, `xinput`, `xsetwacom`, `libinput`, `evtest`

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

Ejecuta el diagnóstico desde la sesión Xorg local para que `xinput` y
`xsetwacom` puedan acceder al servidor X. La etapa `--apply` instala:

- `evtest` y `libinput-tools` para eventos.
- `xinput`, `xserver-xorg-input-wacom` y `libwacom` para Xorg/Wacom.
- `xournalpp` para escritura y anotación de PDF.
- `krita` para presión, inclinación y trazos.

## Uso

```sh
just test-wacom-pen --check
just test-wacom-pen --plan
just test-wacom-pen --apply
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica la pila instalada sin cambios; es el valor predeterminado. |
| `--plan` | `--dry-run` | Muestra la instalación APT prevista sin cambiar el sistema. |
| `--apply` | — | Solicita `sudo -v`, instala paquetes y ejecuta el diagnóstico. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no requiere variables de entorno ni archivo `.env`.

## Ejemplos

Diagnóstico completo:

```sh
just test-wacom-pen --check
```

Instalación de herramientas:

```sh
just test-wacom-pen --apply
```

Pruebas manuales después de iniciar una aplicación gráfica:

```sh
xsetwacom --list devices
xsetwacom get "Wacom Pen and multitouch sensor Pen stylus" all
libinput debug-events
evtest /dev/input/eventX
```

Aplicaciones recomendadas:

- **Xournal++:** escritura manuscrita, notas y anotación de PDF.
- **Krita:** líneas, presión, inclinación y botones del lápiz.
- **evtest/libinput:** eventos de bajo nivel y diagnóstico.

## Protecciones de seguridad

- `--check` y `--plan` no escriben archivos ni cambian paquetes.
- La contraseña nunca se acepta como argumento, se guarda ni se transmite; la
  instalación solo valida permisos mediante `sudo -v`.
- El diagnóstico no ejecuta `evtest --list-devices`, porque esa opción no
  existe en la versión de Debian instalada. Muestra instrucciones y deja la
  lectura de eventos como operación manual.
- No crea reglas udev ni permisos amplios para `/dev/input`.

## Fallos conocidos

### `unable to open display`

**Causa:** el comando se ejecutó por SSH sin `DISPLAY` y sin autorización del
servidor X local.

**Solución:** abre una terminal dentro de i3 y repite `--check`.

### No aparece el sensor `Validity` o Wacom

**Causa:** el kernel puede detectar el USB, pero el lector de huellas Validity
no tiene soporte estándar; esto no implica que la pluma Wacom esté ausente.

**Solución:** confirma `grep -i Wacom /proc/bus/input/devices` y
`xsetwacom --list devices`. La ruta experimental del lector de huellas es
independiente y no se instala automáticamente.

### `evtest: unrecognized option '--list-devices'`

**Causa:** algunas versiones de `evtest` de Debian no implementan esa opción.

**Solución:** enumera los nodos con `ls /dev/input/event*` o
`/proc/bus/input/devices` y ejecuta `evtest /dev/input/eventX`. Si el nodo
requiere permisos, usa `sudo evtest /dev/input/eventX` desde la consola local.

## Changelog

### [Unreleased]

- `feat:` diagnóstico de XInput, Wacom, libinput y eventos crudos.
- `feat:` instalación de Xournal++ y Krita para pruebas de escritura.
