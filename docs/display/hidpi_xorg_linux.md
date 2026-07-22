# hidpi_xorg_linux.sh

Detecta la resolución y DPI del monitor conectado y ajusta el escalado de Xorg (`xrandr --scale`) y `Xft.dpi` en `~/.Xresources`.

- **Ruta:** `scripts/display/hidpi_xorg_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** `xrandr`, `python3`, `xrdb`

---

## Uso

```sh
./scripts/display/hidpi_xorg_linux.sh
```

---

## Cómo funciona

1. Detecta el monitor externo (HDMI/DP/DVI) o usa el primero disponible
2. Mide DPI a partir de la resolución y dimensiones físicas (mm) del EDID
3. Si no hay mm en EDID, estima por resolución (4K → 200%, QHD+ → 150%, etc.)
4. Ajusta `Xft.dpi` en `~/.Xresources` y aplica con `xrdb -merge`

---

## Ejemplos

```sh
./scripts/display/hidpi_xorg_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/hidpi_xorg.sh`.
