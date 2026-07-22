# wifi_scan_linux.sh

Escanea y muestra redes WiFi disponibles usando NetworkManager.

- **Ruta:** `scripts/network/wifi_scan_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con NetworkManager)
- **Dependencias:** `nmcli`

---

## Uso

```sh
./scripts/network/wifi_scan_linux.sh
```

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `WIFI_SCAN_MAX` | `50` | Máximo de redes a mostrar en la salida |

---

## Ejemplos

```sh
# Escaneo normal
./scripts/network/wifi_scan_linux.sh

# Mostrar solo 10 redes
WIFI_SCAN_MAX=10 ./scripts/network/wifi_scan_linux.sh
```

---

## Salida

```
  → Escaneando redes WiFi...

SSID              SEGURIDAD  SEÑAL%  BARRAS  CANAL
MiRed             WPA2       85      ▂▄▆█    6
CasaVecina        WPA2       45      ▂▄__     11
WiFi-Abierto      --         30      ▂___     1

  ✓ Total: 12 redes detectadas.
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial.
