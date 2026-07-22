# wifi_reset_linux.sh

Recarga el driver WiFi `wl` (Broadcom) y reinicia la radio WiFi con `nmcli`.

- **Ruta:** `scripts/network/wifi_reset_linux.sh`
- **SO requerido:** Linux (con driver Broadcom wl)
- **Dependencias:** `sudo`, `modprobe`, `nmcli`

---

## Uso

```sh
./scripts/network/wifi_reset_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-reset.sh`.
