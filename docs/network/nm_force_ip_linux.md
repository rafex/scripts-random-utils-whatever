# nm_force_ip_linux.sh

Diagnostica y fuerza la obtención de IP en una interfaz de red. Detecta el stack de red activo (NetworkManager, systemd-networkd, dhcpcd, ifupdown, dhclient standalone) y usa las herramientas adecuadas sin conflictos.

- **Ruta:** `scripts/network/nm_force_ip_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `nmcli` (NetworkManager), `networkctl`, `dhcpcd`, `dhclient`, `ethtool`, `iproute2` (según el stack)

---

## Requisitos

- **NetworkManager** (recomendado) — `nmcli` + `systemctl`
- **systemd-networkd** — `networkctl` + `systemctl`
- **dhcpcd** — standalone DHCP client
- **ethtool** — para modo `--auto-neg`
- **iproute2** — fallback para IP estática con `ip`

---

## Uso

```sh
./scripts/network/nm_force_ip_linux.sh <iface> [opciones]
```

## Opciones

| Opción | Descripción |
|---|---|
| `--check` | Diagnostica la interfaz sin modificar (default) |
| `--dhcp` | Fuerza la renovación DHCP de la interfaz |
| `--release` | Libera lease DHCP y renueva |
| `--static <IP/CIDR>` | Configura IP estática |
| `--gateway <GW>` | Gateway (usar con --static) |
| `--dns <DNS>` | Servidores DNS (usar con --static) |
| `--auto-neg <on\|off>` | Activa/desactiva auto-negociación (ethtool) |
| `--show-stack` | Solo mostrar el stack de red detectado |
| `--dry-run` | Simular sin ejecutar comandos de modificación |
| `-h, --help` | Muestra la ayuda |

## Detección de stack de red

El script detecta automáticamente el stack de red en uso:

| Stack | Cómo detecta | Comando usado |
|---|---|---|
| NetworkManager | `systemctl is-active NetworkManager` + `nmcli` | `nmcli dev connect` / `nmcli con up` |
| systemd-networkd | `systemctl is-active systemd-networkd` + `networkctl` | `networkctl reconfigure` |
| dhcpcd standalone | `systemctl is-active dhcpcd` + `dhcpcd` | `dhcpcd -n` |
| ifupdown | `/etc/network/interfaces` con entrada | `ifdown` / `ifup` |
| dhclient standalone | `dhclient` en PATH sin NM/networkd | `dhclient -r && dhclient` |

También detecta el DHCP client interno de NM (`internal`, `dhclient`, `dhcpcd`).

## Conflictos detectados

El script avisa si detecta:

- NetworkManager + dhcpcd corriendo simultáneamente
- NetworkManager + systemd-networkd corriendo simultáneamente
- `isc-dhcp-client` + `dhcpcd-base` ambos instalados

---

## Diagnóstico (`--check`)

Muestra sin modificar y sin requerir sudo:

1. Stack de red activo + DHCP client en uso
2. Conflictos detectados (múltiples stacks/DHCP clients)
3. Estado de la interfaz (carrier, operstate, driver, MAC, MTU, IPs)
4. Estado de NetworkManager (device state, connection config, perfil IP)
5. **Auto-negociación en perfil NM** — detecta si está desactivada (causa común de "sin IP")
6. Estado de asociación conexión↔dispositivo
7. Timeout y tolerancia a fallos (may-fail, dhcp-timeout)
8. Última conexión exitosa (timestamp)
9. Conflicto con `/etc/network/interfaces`
10. DHCP leases (rutas, sin leer contenido)

### Diagnóstico automático

Al final del `--check`, el script analiza los hallazgos y emite recomendaciones concretas:

```
═══ Diagnóstico automático — recomendaciones ═══
  ✓ Cable conectado (carrier=1)
  ✗ Auto-negociación DESACTIVADA en el perfil NM.
  ✗ Conexión NM no asociada al dispositivo.
  ✗ NM state: disconnected pero carrier=1 — algo bloquea la activación.

  Comandos recomendados (en orden):
  $ sudo ~/.local/bin/nm-force-ip enp1s0f0 --auto-neg on
  $ sudo ~/.local/bin/nm-force-ip enp1s0f0 --dhcp
```

---

## Ejemplos

```sh
# Diagnóstico (sin sudo)
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --check

# Forzar DHCP (pide sudo interactivo si no se ejecuta con sudo)
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --dhcp

# IP estática
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --static 192.168.3.50/24 --gateway 192.168.3.1 --dns 192.168.3.1

# Activar auto-negociación
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --auto-neg on

# Liberar y renovar DHCP (con sudo)
sudo ./scripts/network/nm_force_ip_linux.sh enp1s0f0 --release

# Solo ver stack de red
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --show-stack

# Simular acciones
./scripts/network/nm_force_ip_linux.sh enp1s0f0 --dhcp --dry-run
```

### Forma recomendada (instalado en PATH)

```sh
nm-force-ip enp1s0f0 --check
sudo nm-force-ip enp1s0f0 --dhcp
```

---

## Fallos conocidos

### `DHCP falló en todos los intentos`

**Causa:** No hay servidor DHCP en la red o la auto-negociación no funciona.
**Solución:** 
1. Probar `--auto-neg on` para reactivar auto-negociación
2. Usar IP estática: `--static 192.168.x.x/24 --gateway 192.168.x.1`
3. Verificar que el puerto del switch/router tiene DHCP habilitado

### `Se requiere sudo`

**Causa:** Los modos `--dhcp`, `--static`, `--release` y `--auto-neg` requieren privilegios.
**Solución:** Ejecutar con `sudo`: `sudo $0 <iface> --dhcp`

### `802-3-ethernet.auto-negotiate: no` y `speed: 0`

**Causa:** La interfaz está configurada sin auto-negociación, lo que puede causar que DHCP falle aunque el cable esté conectado.
**Solución:** `sudo $0 <iface> --auto-neg on`

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-03

**feat:** Script inicial de diagnóstico y forzado de IP.

- Detección automática del stack de red (NM, networkd, dhcpcd, ifupdown, dhclient)
- Detección de DHCP client interno de NM
- Detección de conflictos (múltiples stacks o DHCP clients)
- Modos: check, dhcp, release, static, auto-neg, show-stack
- Soporte para --dry-run
- Limpieza de leases DHCP stale antes de reconectar
- Estrategia de reconnect en 3 niveles: device connect → connection up → reapply
