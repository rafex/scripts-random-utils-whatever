---
title: install_picom_upstream_linux.sh
description: Compila Picom v13 upstream con GLX, transparencias y desenfoque para Xorg.
tags:
  - instalación
  - picom
  - i3
---

# install_picom_upstream_linux.sh

Compila la etiqueta oficial `v13` de Picom y coloca el binario en el espacio
del usuario, sin reemplazar el paquete de Debian ni iniciar el compositor.

- **Ruta:** `scripts/install/install_picom_upstream_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, git, Meson, Ninja, pkg-config, compilador C, dependencias de desarrollo X11/GLX y sudo únicamente para APT.

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

El instalador está pensado para Debian con una sesión Xorg. Requiere una
conexión para obtener el código oficial de Picom durante `--apply` y espacio
para las fuentes y la compilación bajo `~/.local/share/rafex/picom/`.

La compilación fija la etiqueta oficial `v13` y comprueba que el commit
obtenido coincide exactamente con `d87a5ba3af7a9ee3c4e040ee29b2dea7e9e46317`.
El binario final se instala en `~/.local/bin/picom`, de modo que el paquete del sistema continúa disponible
como fallback.

## Uso

```bash
just install-picom-upstream --check
just install-picom-upstream --plan
just install-picom-upstream --apply
just install-picom-upstream --status
```

El instalador no inicia Picom ni detiene la instancia que pudiera estar activa.
Después de revisar la configuración, reinicia la instancia administrada:

```bash
just picom-toggle --disable
just picom-toggle --enable
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el entorno, las dependencias y el plan sin escribir. |
| `--plan` | — | Muestra origen, commit, rutas y paquetes faltantes sin escribir. |
| `--apply` | — | Instala dependencias faltantes, obtiene Picom v13, compila e instala el binario y la configuración administrada. |
| `--status` | — | Muestra las versiones, el origen local y el estado de la configuración. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este instalador no requiere variables de entorno. Las rutas se derivan de
`$HOME` y de `XDG_CONFIG_HOME`/`XDG_DATA_HOME` si están definidos.

## Ejemplos

```bash
# Forma recomendada: inspeccionar antes de compilar.
just install-picom-upstream --check
just install-picom-upstream --plan
just install-picom-upstream --apply

# Comprobar que el binario local tiene prioridad en el helper.
~/.local/bin/picom --version
just picom-toggle --check
```

## Protecciones de seguridad

- Solo `--apply` modifica el equipo.
- `sudo` se utiliza únicamente para `apt-get update` y para instalar
  dependencias de compilación faltantes; Picom se instala en `~/.local`.
- El script rechaza ejecución como root y no modifica `/usr/bin/picom`, GRUB,
  Xorg, i3, Openbox ni servicios del sistema.
- El origen Git debe ser exactamente `https://github.com/yshui/picom.git`, las
  fuentes deben estar limpias y la etiqueta debe resolver al commit esperado.
- Se crean respaldos fechados si ya existen el binario o la configuración
  administrados antes de reemplazarlos.
- El compositor no se inicia automáticamente durante la instalación. La
  activación queda bajo el control de `picom-toggle`.
- La configuración usa GLX, transparencia moderada, blur dual-kawase y una
  sombra pequeña (`radius=5`, `opacity=0.22`). Conky, EWW, barras y ventanas
  de escritorio quedan sin sombra ni blur para preservar su comportamiento.

## Fallos conocidos

### `la compilación no produjo build/src/picom`

**Causa:** faltan dependencias de desarrollo, el checkout no corresponde a
`v13` o Meson/Ninja terminó con error.

**Solución:** ejecuta `--check`, revisa la salida de Meson y confirma que la
ThinkPad tiene espacio suficiente. No inicies el binario hasta que `--status`
muestre `v13`.

### `commit inesperado para v13`

**Causa:** la etiqueta remota cambió, el checkout local fue alterado o el
origen no es el repositorio oficial.

**Solución:** no fuerces la compilación. Conserva el árbol para inspección y
revisa la etiqueta y su firma en el repositorio oficial antes de actualizar el
commit fijado en este script.

### `Picom no inicia con la configuración visual`

**Causa:** GLX, blur o el controlador gráfico pueden no funcionar bien en una
sesión concreta; también puede existir otra instancia activa.

**Solución:** vuelve a `just picom-toggle --disable` y prueba la configuración
con blur desactivado temporalmente. El paquete de Debian no se elimina y el
binario anterior queda disponible en los respaldos fechados.

## Changelog

### [Unreleased]

- **feat:** añadir compilación reproducible de Picom upstream v13 en el espacio del usuario.
- **style:** configurar GLX, blur, transparencia y sombras pequeñas para i3/Openbox.
- **fix:** hacer que el helper prefiera `~/.local/bin/picom` sin eliminar el fallback del sistema.

### v1.0.1 — 2026-09-05

**fix:** restaurar automáticamente el binario y la configuración anteriores si
el reemplazo atómico falla.
