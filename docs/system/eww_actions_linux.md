---
title: eww_actions_linux.sh
description: Allowlist de datos y acciones para el dashboard EWW de Rafex.
tags:
  - sistema
  - eww
  - seguridad
---

# eww_actions_linux.sh

Entrega datos compactos para los widgets y ejecuta únicamente acciones
predefinidas del perfil ThinkPad.

- **Ruta:** `scripts/system/eww_actions_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** bash; helpers del perfil según la acción; `playerctl` para multimedia.

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

El instalador EWW copia este helper como `~/.local/bin/eww-actions.sh`. Debe
ejecutarse como usuario normal, nunca como root.

## Uso

```bash
~/.local/bin/eww-actions.sh --status
~/.local/bin/eww-actions.sh --value media
~/.local/bin/eww-actions.sh --action volume-mute
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--value <nombre>` | — | Devuelve reloj, calendario, multimedia, dispositivos o estado resumido. |
| `--action <nombre>` | — | Ejecuta una acción de la lista cerrada. |
| `--status` | — | Muestra disponibilidad de dependencias sin datos privados. |
| `--help` | `-h` | Muestra la ayuda. |

Valores admitidos: `time`, `date`, `calendar`, `media`, `notifications`,
`devices`, `battery`, `printers`, `scanner` y `theme`.

Acciones admitidas: brillo de pantalla/teclado, volumen, micrófono, Wi‑Fi,
WWAN, Bluetooth, controles multimedia, historial de Dunst, panel Rafex,
captura, bloqueo y acciones de sesión/energía.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Ubicación del estado de tema. |

## Ejemplos

```bash
~/.local/bin/eww-actions.sh --value calendar
~/.local/bin/eww-actions.sh --value printers
~/.local/bin/eww-actions.sh --action media-play
~/.local/bin/eww-actions.sh --action control-panel
```

## Protecciones de seguridad

- No usa `eval`, `sh -c` con entrada del usuario ni argumentos arbitrarios.
- Las acciones sensibles delegan en `desktop-settings-menu.sh`, que conserva
  la confirmación mediante Rofi.
- No muestra SSID, IP, IMEI, IMSI, APN, MAC, rutas privadas ni secretos.
- La tarjeta multimedia muestra metadatos del reproductor activo porque es la
  función solicitada; no muestra credenciales ni historial de archivos.
- La lectura de escáner está limitada a una consulta breve y tolera `N/D`.

## Fallos conocidos

### `playerctl` no está disponible

**Causa:** la dependencia multimedia obligatoria no se instaló.

**Solución:** ejecuta `just install-eww --apply`; el instalador verifica el
candidato APT antes de instalarlo.

### `No hay reproductor MPRIS`

**Causa:** no hay un reproductor compatible activo.

**Solución:** abre un reproductor con soporte MPRIS; el widget seguirá mostrando
`N/D` hasta entonces.

## Changelog

### [Unreleased]
- **feat:** añadir datos seguros y acciones cerradas para el dashboard EWW.
