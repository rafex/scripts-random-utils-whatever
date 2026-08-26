# screen_auto_mirror_linux.sh

Duplica la pantalla si hay un monitor externo conectado. Si no, vuelve a solo laptop. Muestra notificación con `notify-send`.

- **Ruta:** `scripts/display/screen_auto_mirror_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `notify-send`

---

## Uso

```sh
./scripts/display/screen_auto_mirror_linux.sh
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
./scripts/display/screen_auto_mirror_linux.sh

SCREEN_INTERNAL=eDP1 SCREEN_EXTERNAL=DP1 ./scripts/display/screen_auto_mirror_linux.sh
```

---

## Changelog

### [Unreleased]

**feat:** autodetección de salidas xrandr para evitar nombres exclusivos de MacBook.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-auto-mirror.sh`.
