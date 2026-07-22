# wifi_connect_interactive_linux.sh

Conecta a una red WiFi con selección interactiva de red e interfaz. Soporta modo directo con flags `-s` (SSID) y `-b` (BSSID) para uso no interactivo.

- **Ruta:** `scripts/network/wifi_connect_interactive_linux.sh`
- **SO requerido:** Linux (NetworkManager)
- **Dependencias:** `nmcli`

---

## Uso

```sh
./scripts/network/wifi_connect_interactive_linux.sh [opciones]
```

---

## Opciones

| Opción | Descripción |
|---|---|
| `-i, --iface <iface>` | Interfaz WiFi (por defecto: primera encontrada) |
| `-s, --ssid <ssid>` | Conectar directo al SSID (usa `$WIFI_PASS`) |
| `-b, --bssid <mac>` | Conectar directo al BSSID (usa `$WIFI_PASS`) |
| `-h, --help` | Mostrar ayuda |

---

## Variables de entorno

| Variable | Descripción |
|---|---|
| `WIFI_PASS` | Contraseña para modo directo con `-s` o `-b` |

---

## Ejemplos

```sh
# Modo interactivo
./scripts/network/wifi_connect_interactive_linux.sh

# Modo directo
WIFI_PASS=<WIFI_PASSWORD> ./scripts/network/wifi_connect_interactive_linux.sh -s MiRed

# Con interfaz específica
./scripts/network/wifi_connect_interactive_linux.sh -i wlp2s0
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/wifi-connect.sh`.
