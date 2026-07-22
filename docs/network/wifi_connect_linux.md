# wifi_connect_linux.sh

Conecta a una red WiFi usando NetworkManager (`nmcli`). Solicita la contraseña de forma interactiva si no se pasa por argumento.

- **Ruta:** `scripts/network/wifi_connect_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu con NetworkManager)
- **Dependencias:** `nmcli`, `NetworkManager`

---

## Uso

```sh
./scripts/network/wifi_connect_linux.sh <SSID> [password]
```

| Argumento | Descripción |
|---|---|
| `SSID` | Nombre de la red WiFi (obligatorio) |
| `password` | Contraseña (opcional; si se omite se pide interactivamente) |

---

## Variables de entorno

| Variable | Descripción |
|---|---|
| `WIFI_PASSWORD` | Contraseña de la red WiFi (alternativa al argumento o prompt) |

---

## Ejemplos

```sh
# Con contraseña por argumento
./scripts/network/wifi_connect_linux.sh MiRed miPassword123

# Pedirá la contraseña interactivamente
./scripts/network/wifi_connect_linux.sh MiRed

# Con contraseña por variable de entorno
WIFI_PASSWORD=securePass ./scripts/network/wifi_connect_linux.sh MiRed

# Red con espacios en el nombre
./scripts/network/wifi_connect_linux.sh "Mi WiFi" contraseña
```

---

## Validaciones previas

Antes de conectar el script verifica:

1. `nmcli` está instalado
2. `NetworkManager` está corriendo (`systemctl is-active`)
3. El WiFi no está bloqueado a nivel radio — si lo está, lo activa automáticamente

---

## Fallos conocidos

### `Error: No network with SSID 'X' found.`

La red no está en rango. Escanear primero:

```sh
./scripts/network/wifi_scan_linux.sh
```

### `Error: Connection activation failed: (7) Secrets were required but not provided.`

Contraseña incorrecta o faltante. Reintentar con la contraseña correcta.

### `Error: nmcli no está instalado`

Instalar NetworkManager:

```sh
sudo apt install network-manager
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial.
