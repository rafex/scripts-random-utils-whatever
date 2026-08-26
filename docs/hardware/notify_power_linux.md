# notify_power_linux.sh

Monitoriza cambios de estado de energía (AC/batería) mediante eventos de UPower y notifica al conectar o desconectar el cargador.

Se ejecuta como daemon (bloquea escuchando eventos).

- **Ruta:** `scripts/hardware/notify_power_linux.sh`
- **SO requerido:** Linux (UPower)
- **Dependencias:** `upower`, `notify-send`

---

## Uso

```sh
./scripts/hardware/notify_power_linux.sh &
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `POWER_DEVICE` | autodetectado | Dispositivo UPower a monitorizar; útil para forzar un nombre concreto |

---

## Ejemplos

```sh
# Lanzar en background
./scripts/hardware/notify_power_linux.sh &

# ThinkPad: detecta automáticamente AC y BAT0
~/.local/bin/power-notify.sh &

# Con dispositivo personalizado
POWER_DEVICE=/org/freedesktop/UPower/devices/line_power_AC0 \
  ./scripts/hardware/notify_power_linux.sh &
```

---

## Changelog

### [Unreleased]

**fix:** detección dinámica de dispositivos AC compatible con ThinkPad y MacBook.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/power-notify.sh`.
