# screen_extend_auto_linux.sh

Extiende el escritorio al monitor externo (a la derecha). Si no hay externo conectado, vuelve a solo laptop.

- **Ruta:** `scripts/display/screen_extend_auto_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `notify-send`, `awk`

---

## Uso

```sh
./scripts/display/screen_extend_auto_linux.sh
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SCREEN_INTERNAL` | `LVDS1` | Salida de pantalla interna |
| `SCREEN_EXTERNAL` | `HDMI1` | Salida de monitor externo |

---

## Ejemplos

```sh
./scripts/display/screen_extend_auto_linux.sh

SCREEN_INTERNAL=eDP1 SCREEN_EXTERNAL=DP1 ./scripts/display/screen_extend_auto_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-extend-auto.sh`.
