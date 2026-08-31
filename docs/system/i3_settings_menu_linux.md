---
title: i3_settings_menu_linux.sh
description: Menú Rofi de configuraciones habituales para i3
tags:
  - i3
  - configuración
---

# i3_settings_menu_linux.sh

Ofrece un menú Rofi para abrir las herramientas de red, audio, pantallas,
Bluetooth, cámara, Synaptic, i3 y estado del sistema, además de acciones de
sesión y energía con confirmación.

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
~/.local/bin/i3-settings-menu.sh logout
~/.local/bin/i3-settings-menu.sh suspend
~/.local/bin/i3-settings-menu.sh hibernate
~/.local/bin/i3-settings-menu.sh reboot
~/.local/bin/i3-settings-menu.sh poweroff
```

La opción `Software — Synaptic` ejecuta `synaptic-pkexec`. Synaptic debe
instalarse previamente y `lxpolkit` debe estar activo para mostrar el diálogo
gráfico de autenticación.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| sin argumentos | — | Abre el centro de control completo. |
| `power` | — | Abre solo energía y sesión. |
| `logout` | — | Pide confirmación y termina la sesión i3. |
| `suspend` | — | Pide confirmación y suspende el equipo. |
| `hibernate` | — | Comprueba `loginctl can-hibernate` y pide confirmación. |
| `reboot` | — | Pide confirmación y reinicia el equipo. |
| `poweroff` | — | Pide confirmación y apaga el equipo. |

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

### `La hibernación no está disponible en este equipo.`

**Causa:** systemd, el firmware o el espacio de swap no ofrecen hibernación.

**Solución:** comprueba `loginctl can-hibernate`. El menú no intentará
hibernar si devuelve `no`.

### Acciones de energía sin diálogo

**Causa:** el script se ejecutó fuera de una sesión gráfica o Rofi no pudo abrir
la confirmación.

**Solución:** ejecutar el menú dentro de i3 con Rofi activo. No uses sudo para
las acciones normales del menú.

## Changelog

### [Unreleased]

**feat:** añadir un centro de configuraciones ligero para i3.
