# screen_mirror_linux.sh

Duplica la pantalla interna en el monitor externo HDMI.

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
| `SCREEN_INTERNAL` | `LVDS1` | Salida de pantalla interna |
| `SCREEN_EXTERNAL` | `HDMI1` | Salida de monitor externo |

---

## Ejemplos

```sh
./scripts/display/screen_mirror_linux.sh

SCREEN_EXTERNAL=DP1 ./scripts/display/screen_mirror_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/screen-mirror.sh`.
