---
title: tint2_status_linux.sh
description: Genera el estado compacto de red, audio, batería y recursos para tint2.
tags:
  - sistema
  - openbox
  - tint2
---

# tint2_status_linux.sh

Produce una línea de texto para el executor de tint2 sin privilegios elevados.

- **Ruta:** `scripts/system/tint2_status_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `awk`, `date`; opcionales `nmcli`, `wpctl`, `upower` y `free`.

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

Puede ejecutarse desde una terminal o desde tint2. No requiere X11 ni `sudo`.

## Uso

```bash
tint2-status.sh
```

La salida tiene el formato `NET`, `VOL`, `BAT`, `CPU`, `RAM` y hora.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| ninguna | — | El script no acepta opciones; imprime un estado y termina. |

## Variables de entorno

No usa variables de entorno propias.

## Ejemplos

```bash
just tint2-status
~/.local/bin/tint2-status.sh
```

## Fallos conocidos

### `NET:offline` o `BAT:n/a`

**Causa:** NetworkManager o UPower no están disponibles, o el equipo no tiene
un dispositivo que pueda reportarse.

**Solución:** comprueba el servicio correspondiente; el script continúa
mostrando los demás indicadores.

## Changelog

### [Unreleased]

- `feat`: añade estado compacto para el panel superior tint2.
