---
title: picom_toggle_linux.sh
description: Activa o desactiva picom sin sudo y conserva la preferencia de Openbox.
tags:
  - sistema
  - openbox
  - compositor
---

# picom_toggle_linux.sh

Controla el compositor picom desde i3 u Openbox. El estado de autoinicio se
guarda en la configuración del usuario y el helper prefiere el binario upstream
instalado en `~/.local/bin/picom` antes que el paquete del sistema.

- **Ruta:** `scripts/system/picom_toggle_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `pgrep`; `picom` y `notify-send` son opcionales según la acción.

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

Ejecutar como usuario normal. No requiere `sudo`.

En los perfiles ThinkPad, la configuración administrada usa GLX, una sombra
pequeña y tenue, transparencias moderadas y blur para ventanas normales. Las
ventanas de escritorio, Conky, EWW y las barras quedan excluidas. Si una sesión
ya tenía picom ejecutándose, hay que reiniciarlo para que lea el archivo
actualizado.

## Uso

```bash
picom-toggle.sh --check
picom-toggle.sh --toggle
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra si picom está activo y si se iniciará con Openbox. |
| `--enable` | — | Activa picom y su autoinicio. |
| `--disable` | — | Detiene picom y desactiva su autoinicio. |
| `--toggle` | — | Invierte el estado actual. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `PICOM_CONFIG` | `~/.config/picom/picom.conf` | Configuración que se entrega a picom. |
| `PICOM_BIN` | `~/.local/bin/picom` si es ejecutable; fallback a `PATH` | Binario de Picom que se ejecuta. Útil para una prueba explícita. |

## Ejemplos

```bash
just picom-toggle --check
just picom-toggle --enable
PICOM_CONFIG="$HOME/.config/picom/picom.conf" picom-toggle --toggle
PICOM_BIN="/usr/bin/picom" picom-toggle --enable
```

## Fallos conocidos

### `picom no está instalado.`

**Causa:** se solicitó activarlo sin instalar el paquete.

**Solución:** instala `picom` desde Debian y repite la acción.

### Las ventanas conservan sombras después de cambiar el perfil

**Causa:** picom conserva la configuración con la que fue iniciado; editar
`picom.conf` no cambia una instancia que ya está ejecutándose.

**Solución:** ejecuta `just picom-toggle --disable` y después
`just picom-toggle --enable`, o cierra y abre la sesión gráfica.

### `GLX error` o artefactos con blur

**Causa:** el backend gráfico o el controlador Xorg no soporta de forma estable
la combinación GLX/blur en esa sesión.

**Solución:** desactiva la instancia con `just picom-toggle --disable` y prueba
una configuración sin `blur-background` o con el backend disponible en la
ThinkPad. El compositor es opcional y no debe impedir usar i3 u Openbox.

## Changelog

### [Unreleased]

- `feat`: añade control de picom para el perfil Openbox.
- `fix`: prioriza el binario upstream local y documenta la configuración visual de Picom v13.
