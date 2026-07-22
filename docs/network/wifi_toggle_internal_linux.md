# wifi_toggle_internal_linux.sh

Activa o desactiva la gestión de la interfaz WiFi interna (`wlp2s0`) con NetworkManager y muestra una notificación.

- **Ruta:** `scripts/network/wifi_toggle_internal_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`, `notify-send`

---

## Uso

```sh
./scripts/network/wifi_toggle_internal_linux.sh
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `WIFI_TOGGLE_IFACE` | `wlp2s0` | Interfaz WiFi a controlar |

---

## Ejemplos

```sh
./scripts/network/wifi_toggle_internal_linux.sh

WIFI_TOGGLE_IFACE=wlan0 ./scripts/network/wifi_toggle_internal_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi.sh`.
