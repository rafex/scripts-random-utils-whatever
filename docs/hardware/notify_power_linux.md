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
| `POWER_DEVICE` | `/org/freedesktop/UPower/devices/line_power_ADP1` | Dispositivo UPower a monitorizar |

---

## Ejemplos

```sh
# Lanzar en background
./scripts/hardware/notify_power_linux.sh &

# Con dispositivo personalizado
POWER_DEVICE=/org/freedesktop/UPower/devices/line_power_AC0 \
  ./scripts/hardware/notify_power_linux.sh &
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/power-notify.sh`.
