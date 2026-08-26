# screen_mirror_linux.sh

Duplica la pantalla interna en el monitor externo detectado por xrandr.

- **Ruta:** `scripts/display/screen_mirror_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`

---

## Uso

```sh
./scripts/display/screen_mirror_linux.sh
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SCREEN_INTERNAL` | autodetectada (`eDP-*`, `LVDS-*`, `DSI-*`) | Salida interna |
| `SCREEN_EXTERNAL` | autodetectada (`HDMI-*`, `DP-*`, `DVI-*`, `VGA-*`) | Salida externa |

---

## Ejemplos

```sh
./scripts/display/screen_mirror_linux.sh

SCREEN_EXTERNAL=DP1 ./scripts/display/screen_mirror_linux.sh
```

---

## Changelog

### [Unreleased]

**feat:** autodetección de salidas xrandr.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-mirror.sh`.
