---
title: rafex_picom_runner_linux.sh
description: Runner seguro para iniciar Picom desde la unidad de usuario Rafex.
tags:
  - sistema
  - picom
  - systemd
---

# rafex_picom_runner_linux.sh

Inicia Picom con la configuración administrada desde `rafex-picom.service`.
No es un launcher interactivo: su única función es validar el entorno gráfico,
seleccionar el binario permitido y reemplazar el proceso por Picom.

- **Ruta:** `scripts/system/rafex_picom_runner_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `picom`, `DISPLAY` y `~/.config/picom/picom.conf`.

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

Lo ejecuta systemd como usuario normal. Requiere `DISPLAY` y una configuración
de Picom existente.

## Uso

Normalmente no se ejecuta directamente:

```bash
systemctl --user start rafex-picom.service
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| Ninguna | — | El runner no acepta argumentos; los rechaza Picom o systemd. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `RAFEX_PICOM_BIN` | `~/.local/bin/picom`, después `/usr/bin/picom` | Binario explícito validado por el runner. |
| `RAFEX_PICOM_CONFIG` | `PICOM_CONFIG` o `~/.config/picom/picom.conf` | Configuración usada por Picom. |
| `PICOM_BIN` | — | Alias compatible para la configuración. |
| `PICOM_CONFIG` | — | Alias compatible para la configuración. |
| `DISPLAY` | — | Display X11 requerido. |
| `XAUTHORITY` | `~/.Xauthority` si existe | Archivo de autorización X11. |

## Ejemplos

```bash
systemctl --user start rafex-picom.service
RAFEX_PICOM_BIN=/usr/bin/picom systemctl --user restart rafex-picom.service
RAFEX_PICOM_CONFIG="$HOME/.config/picom/picom.conf" systemctl --user restart rafex-picom.service
```

## Protecciones de seguridad

- Rechaza ejecución como `root`.
- No acepta comandos ni argumentos arbitrarios.
- Solo elige un binario local explícito, `~/.local/bin/picom`, `/usr/bin/picom`
  o el ejecutable resuelto por `PATH`.
- Requiere una configuración regular existente.
- No usa `sudo`, modifica archivos ni inicia servicios adicionales.

## Fallos conocidos

### `DISPLAY no está disponible`

**Causa:** el runner se ejecutó desde una TTY o el servicio no recibió el
entorno importado por i3.

**Solución:** inicia el servicio desde i3 o importa el entorno con:
`systemctl --user import-environment DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS`.

### `no se encontró un binario Picom ejecutable`

**Causa:** Picom no está instalado en las rutas permitidas.

**Solución:** instala Picom desde Debian o completa la instalación upstream y
repite `just install-picom-user-service --status`.

## Changelog

### [Unreleased]
- `feat`: añade runner para el servicio de usuario de Picom.
