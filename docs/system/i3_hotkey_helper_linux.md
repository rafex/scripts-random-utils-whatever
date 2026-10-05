---
title: i3_hotkey_helper_linux.sh
description: Menú Rofi para consultar y ejecutar atajos frecuentes de i3.
tags:
  - system
---

# i3_hotkey_helper_linux.sh

Muestra atajos habituales de i3 junto con su acción. Permite buscar la lista y
ejecutar la acción seleccionada desde Rofi.

- **Ruta:** `scripts/system/i3_hotkey_helper_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `rofi`, `i3-msg`; los comandos asociados a cada acción.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

Debe ejecutarse dentro de una sesión i3 en X11. El atajo **Win+Shift+H** abre
el menú interactivo. **Win+Shift+E** permanece asignado a Rofi Run para
escribir comandos arbitrarios, por ejemplo `xkill` o `killall firefox`.

## Uso

```sh
~/.local/bin/i3-hotkey-helper.sh
~/.local/bin/i3-hotkey-helper.sh --list
```

Busca por la combinación o por la acción. Al pulsar Enter, el helper ejecuta
la acción seleccionada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--list` | — | Imprime la lista de atajos y los comandos asociados. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no usa variables de entorno.

## Ejemplos

```sh
# Abrir la lista para seleccionar una acción.
~/.local/bin/i3-hotkey-helper.sh

# Consultar la lista desde una terminal.
~/.local/bin/i3-hotkey-helper.sh --list

# Ejecutar un comando libre como xkill o killall firefox.
# Pulsa Win+Shift+E y escribe el comando en Rofi Run.
```

## Fallos conocidos

### `No se encontró rofi.`

**Causa:** Rofi no está instalado o no está en `PATH`.

**Solución:** instala Rofi y ejecuta el helper dentro de la sesión gráfica.

### Una acción seleccionada no se ejecuta

**Causa:** el comando asociado no está instalado o el helper se inició fuera
de i3.

**Solución:** usa `--list` para revisar el comando y confirma que la sesión
i3 esté activa.

## Changelog

### [Unreleased]

- Sin cambios pendientes.

### v1.0.0 — 2026-10-04

**feat:** agregar una referencia interactiva de atajos i3.

- Buscar atajos y acciones frecuentes en Rofi.
- Ejecutar directamente la acción seleccionada.
