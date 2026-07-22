# notify_brightness_linux.sh

Ajusta el brillo de pantalla con `brightnessctl` y muestra una notificación con barra de progreso.

- **Ruta:** `scripts/hardware/notify_brightness_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `brightnessctl`, `notify-send`

---

## Uso

```sh
./scripts/hardware/notify_brightness_linux.sh up
./scripts/hardware/notify_brightness_linux.sh down
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `BRIGHTNESS_STEP` | `5` | Porcentaje de incremento/decremento |

---

## Ejemplos

```sh
./scripts/hardware/notify_brightness_linux.sh up
BRIGHTNESS_STEP=10 ./scripts/hardware/notify_brightness_linux.sh down
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/brightness-notify.sh`.
