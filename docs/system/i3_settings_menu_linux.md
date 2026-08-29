---
title: i3_settings_menu_linux.sh
description: Menú Rofi de configuraciones habituales para i3
tags:
  - i3
  - configuración
---

# i3_settings_menu_linux.sh

Ofrece un menú Rofi para abrir las herramientas de red, audio, pantallas,
Bluetooth, cámara, Synaptic, i3 y estado del sistema.

- **Ruta:** `scripts/system/i3_settings_menu_linux.sh`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `rofi`; `synaptic-pkexec` y las herramientas de cada opción
  son opcionales

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

Debe existir una sesión gráfica i3 y `rofi`.

## Uso

```sh
~/.local/bin/i3-settings-menu.sh
```

La opción `Software — Synaptic` ejecuta `synaptic-pkexec`. Synaptic debe
instalarse previamente y `lxpolkit` debe estar activo para mostrar el diálogo
gráfico de autenticación.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| sin argumentos | — | Abre el centro de control completo. |
| `power` | — | Abre solo energía y sesión. |

## Variables de entorno

Este script no requiere variables de entorno.

## Ejemplos

```sh
~/.local/bin/i3-settings-menu.sh
```

## Fallos conocidos

### Una opción no abre

**Causa:** la herramienta asociada no está instalada.
**Solución:** instalar el paquete indicado o usar otra opción del menú.

### `Authorization is required` sin diálogo gráfico

**Causa:** no hay un agente de PolicyKit activo en la sesión i3.

**Solución:** ejecuta `just install-i3-laptop-controls --apply`, cierra y vuelve
a iniciar la sesión gráfica, y comprueba `pgrep -x lxpolkit`. Para Synaptic usa
`synaptic-pkexec`, no `/usr/sbin/synaptic` directamente.

## Changelog

### [Unreleased]

**feat:** añadir un centro de configuraciones ligero para i3.
