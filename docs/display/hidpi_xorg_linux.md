# hidpi_xorg_linux.sh

Detecta la resolución y DPI del monitor conectado y ajusta el escalado de Xorg (`xrandr --scale`) y `Xft.dpi` en `~/.Xresources`.

- **Ruta:** `scripts/display/hidpi_xorg_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `python3`, `xrdb`

---

## Uso

```sh
./scripts/display/hidpi_xorg_linux.sh --check
./scripts/display/hidpi_xorg_linux.sh --apply
```

---

## Cómo funciona

1. Detecta el panel interno (`eDP-*`, `LVDS-*` o `DSI-*`) o usa el primero disponible
2. Mide DPI a partir de la resolución y dimensiones físicas (mm) del EDID
3. Si no hay mm en EDID, estima por resolución (4K → 200%, QHD+ → 150%, etc.)
4. `--check` solo informa; `--apply` ajusta `xrandr`, `Xft.dpi` y aplica `xrdb -merge`

## Opciones

| Opción | Descripción |
|---|---|
| `--check` | Diagnóstico sin modificar archivos, modo predeterminado |
| `--apply` | Aplica el escalado y actualiza `~/.Xresources` |
| `--output <nombre>` | Fuerza una salida concreta |

---

## Ejemplos

```sh
./scripts/display/hidpi_xorg_linux.sh
```

---

## Changelog

### [Unreleased]

**feat:** modo diagnóstico y detección de panel interno portable.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/hidpi_xorg.sh`.
