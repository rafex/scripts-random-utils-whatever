# screen_auto_edge_mirror_linux.sh

Duplica la pantalla ajustando el monitor externo al modo nativo del panel interno. Si el externo no está conectado, vuelve a solo laptop.

- **Ruta:** `scripts/display/screen_auto_edge_mirror_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `notify-send`, `awk`

---

## Uso

```sh
./scripts/display/screen_auto_edge_mirror_linux.sh
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SCREEN_INTERNAL` | autodetectada (`eDP-*`, `LVDS-*`, `DSI-*`) | Salida de pantalla interna |
| `SCREEN_EXTERNAL` | autodetectada (`HDMI-*`, `DP-*`, `DVI-*`, `VGA-*`) | Salida de monitor externo |

---

## Ejemplos

```sh
./scripts/display/screen_auto_edge_mirror_linux.sh
```

---

## Changelog

### [Unreleased]

**feat:** autodetección de salidas xrandr para ThinkPad y otros equipos.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-auto-edge-mirror.sh`.
