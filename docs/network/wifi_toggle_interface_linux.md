# wifi_toggle_interface_linux.sh

Alterna entre WiFi interno y USB de forma interactiva. Útil en laptops con doble interfaz WiFi (ej. Broadcom interna + adaptador USB externo).

- **Ruta:** `scripts/network/wifi_toggle_interface_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`

---

## Uso

```sh
./scripts/network/wifi_toggle_interface_linux.sh
```

---

## Menú interactivo

```
1) Apagar WiFi interno, encender USB
2) Apagar WiFi USB, encender interno
3) Solo apagar WiFi interno
4) Solo encender WiFi interno
5) Mostrar estado
```

Detecta automáticamente qué interfaz es interna (drivers: `wl`, `b43`, `brcmfmac`, `iwlwifi`) y cuál es USB.

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-toggle.sh`.
