---
title: picom_toggle_linux.sh
description: Activa o desactiva picom sin sudo y conserva la preferencia de Openbox.
tags:
  - sistema
  - openbox
  - compositor
---

# picom_toggle_linux.sh

Controla el compositor picom desde i3 u Openbox. Cuando está instalado
`rafex-picom.service`, usa la unidad systemd del usuario; de lo contrario
conserva una ruta legacy compatible. El estado de autoinicio se guarda en la
configuración del usuario.

- **Ruta:** `scripts/system/picom_toggle_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `pgrep`, `systemctl`; `picom` y `notify-send` son opcionales según la acción.

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

Ejecutar como usuario normal. No requiere `sudo`. Para la ruta recomendada,
instala primero `just install-picom-user-service --apply`.

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
| `--check` | — | Muestra el estado y si usa `systemd-user` o compatibilidad legacy. |
| `--enable` | — | Activa la preferencia y arranca `rafex-picom.service` si existe. |
| `--disable` | — | Detiene la unidad administrada y desactiva la preferencia. |
| `--toggle` | — | Invierte el estado actual mediante la unidad administrada. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `PICOM_CONFIG` | `~/.config/picom/picom.conf` | Configuración que se entrega a picom. |
| `PICOM_BIN` | `~/.local/bin/picom` si es ejecutable; fallback a `PATH` | Binario de Picom que se ejecuta. Útil para una prueba explícita. |

Si existe la unidad administrada, `PICOM_BIN` y `PICOM_CONFIG` se transfieren al
entorno del servicio como `RAFEX_PICOM_BIN` y `RAFEX_PICOM_CONFIG`.

## Ejemplos

```bash
just picom-toggle --check
just picom-toggle --enable
PICOM_CONFIG="$HOME/.config/picom/picom.conf" picom-toggle --toggle
PICOM_BIN="/usr/bin/picom" picom-toggle --enable
systemctl --user status rafex-picom.service
```

## Fallos conocidos

### `picom no está instalado.`

**Causa:** se solicitó activarlo sin instalar el paquete.

**Solución:** instala `picom` desde Debian y repite la acción.

### `rafex-picom.service` no está instalada

**Causa:** el toggle no encuentra la unidad de usuario administrada.

**Solución:** ejecuta `just install-picom-user-service --apply` y después
`just picom-toggle --enable`.

### Las ventanas conservan sombras después de cambiar el perfil

**Causa:** picom conserva la configuración con la que fue iniciado; editar
`picom.conf` no cambia una instancia que ya está ejecutándose.

**Solución:** ejecuta `just picom-toggle --disable` y después
`just picom-toggle --enable`, o revisa `journalctl --user -u
rafex-picom.service -b`.

### `GLX error` o artefactos con blur

**Causa:** el backend gráfico o el controlador Xorg no soporta de forma estable
la combinación GLX/blur en esa sesión.

**Solución:** desactiva la instancia con `just picom-toggle --disable` y prueba
una configuración sin `blur-background` o con el backend disponible en la
ThinkPad. El compositor es opcional y no debe impedir usar i3 u Openbox.

## Changelog

### [Unreleased]

- `feat`: controla Picom mediante una unidad systemd de usuario cuando está instalada.
- `fix`: evita detener procesos Picom no administrados en la ruta recomendada.
- `fix`: conserva la preferencia legacy de Openbox durante la migración.
