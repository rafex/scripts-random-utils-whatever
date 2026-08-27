---
title: diag_iface_linux.sh
description: Diagnóstico completo de una interfaz de red
tags:
  - red
---

# diag_iface_linux.sh

Diagnóstico completo de una interfaz de red. Recolecta evidencia con sudo: WiFi, driver, fail2ban, firewall, kernel, ARP, conntrack, MTU path test, captura tcpdump y hardware. Genera evidencia en `/tmp` y `REPORTE.md` con análisis automático.

- **Ruta:** `scripts/network/diag_iface_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `sudo`, `iproute2`, `iw`, `ethtool`, `fail2ban-client`, `tcpdump` (opcional), `nft`/`iptables`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Auto-detección de interfaz](#auto-deteccion-de-interfaz)
- [Qué recolecta](#que-recolecta)
- [Análisis automático](#analisis-automatico)
- [Ejemplos](#ejemplos)

> **Forma recomendada desde la raíz del repo:** usar `just diag-iface`.

______________________________________________________________________

## Requisitos

- Linux con `sudo` disponible
- `iproute2`, `iw`, `ethtool`, `bc`
- `fail2ban-client` si fail2ban está activo
- `tcpdump` (opcional, auto-detecta)
- `nft` o `iptables` (auto-detecta)

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
# Interfaz específica
just diag-iface -i wlxa047d76360c5

# Auto-detectar interfaz con más RX drops
just diag-iface --auto
```

### Directamente

```sh
sudo scripts/network/diag_iface_linux.sh [opciones]
```

El script requiere `sudo` para acceder a fail2ban, dmesg, iptables, tcpdump y stats de sistema. Si no es root, aborta con mensaje de error.

### Resultado

El script crea:

- `/tmp/diag-iface-<timestamp>/` — directorio con evidencia
- `/tmp/diag-iface-<timestamp>.tar.gz` — tarball para transporte
- `REPORTE.md` — análisis automático con semáforo 🔴🟡🟢

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--iface <nombre>` | `-i` | Interfaz a diagnosticar |
| `--auto` | | Auto-detectar interfaz con más RX drops |
| `--capture <N>` | `-c` | Paquetes a capturar con tcpdump (default: 50) |
| `--no-capture` | | Omitir captura tcpdump |
| `--mtu-target <ip>` | | IP para test de MTU con ping DF (default: gateway) |
| `--output <dir>` | `-o` | Directorio de salida (default: autogenerado en /tmp) |
| `--help` | `-h` | Muestra la ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `DIAG_IFACE` | — | Interfaz a diagnosticar |
| `DIAG_CAPTURE` | `50` | Paquetes a capturar (0 = no capturar) |
| `DIAG_MTU_TARGET` | — | IP para test MTU (default: gateway) |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

______________________________________________________________________

## Auto-detección de interfaz

Con `--auto`, el script busca la interfaz con mayor número de RX drops:

```sh
sudo ./scripts/network/diag_iface_linux.sh --auto
```

Útil cuando no sabes qué interfaz está fallando — el script deduce cuál tiene más paquetes descartados.

______________________________________________________________________

## Qué recolecta

| Fase | Archivo | Contenido |
|---|---|---|
| 1 | `01-ip-addr.txt` | `ip -br addr` |
| 1 | `02-ip-route.txt` | `ip route` |
| 1 | `03-ip-link.txt` | `ip -s link show <iface>` |
| 1 | `04-ip-neigh.txt` | `ip neigh show dev <iface>` |
| 2 | `05-ss-listen.txt` | `ss -tlnp` |
| 2 | `06-ss-established.txt` | `ss -tn state established` |
| 2 | `07-ss-summary.txt` | `ss -s` |
| 3 | `08-iw-dev.txt` | `iw dev`, `iw dev <iface> link` |
| 3 | `09-iw-station.txt` | `iw dev <iface> station dump` |
| 3 | `10-iw-info.txt` | `iw dev <iface> info` |
| 4 | `11-lsmod.txt` | `lsmod` (drivers red/wifi) |
| 4 | `12-ethtool.txt` | `ethtool -i <iface>` |
| 4 | `13-ethtool-stats.txt` | `ethtool -S <iface>` |
| 4 | `14-lsusb.txt` | `lsusb` |
| 4 | `15-usb-power.txt` | USB power management (autosuspend) |
| 5 | `16-fail2ban-status.txt` | `fail2ban-client status` |
| 5 | `17-fail2ban-jails.txt` | `fail2ban-client status <jail>` |
| 5 | `18-fail2ban-log.txt` | Tail de `/var/log/fail2ban.log` |
| 6 | `19-nft-ruleset.txt` | `nft list ruleset` |
| 6 | `20-iptables.txt` | `iptables -L -n -v` |
| 7 | `21-dmesg.txt` | `dmesg` filtrado (rtw/usb/wifi/deauth/disconnect/mtu) |
| 7 | `22-journal-kernel.txt` | `journalctl -k --no-pager` |
| 7 | `23-journal-fail2ban.txt` | `journalctl -u fail2ban` |
| 7 | `24-journal-nm.txt` | `journalctl -u NetworkManager` |
| 8 | `25-sysctl.txt` | rp_filter, ip_forward, conntrack, TCP |
| 9 | `26-mtu-test.txt` | `ping -M do` Path MTU Discovery |
| 10 | `27-hardware.txt` | RAM, CPUs, load, interrupts, top procesos |
| 11 | `28-capture.pcap` | `tcpdump -i <iface> -c N` (50 paquetes) |

______________________________________________________________________

## Análisis automático

El `REPORTE.md` incluye una tabla de hallazgos con semáforo:

| Check | Lógica | Severidad |
|---|---|---|
| TX/RX asymmetry | `TX/RX < 0.01` | 🔴 |
| RX drops | `> 500` / `> 100` | 🔴 / 🟡 |
| USB autosuspend | `on` + delay < 5000ms | 🔴 |
| fail2ban bans | bans en log reciente | 🟡 |
| rp_filter | `1` (estricto) | 🟡 |
| conntrack | `> 80%` / `> 50%` | 🔴 / 🟡 |
| dmesg errores | `> 10` líneas relevantes | 🟡 |
| MTU path | ping DF falla | 🟡 |
| ARP STALE | `> 2` entradas | 🟡 |

______________________________________________________________________

## Ejemplos

```sh
# Diagnóstico de interfaz WiFi USB
sudo ./scripts/network/diag_iface_linux.sh -i wlxa047d76360c5

# Auto-detectar interfaz problemática
sudo ./scripts/network/diag_iface_linux.sh --auto

# Sin captura tcpdump, con MTU test a IP específica
sudo ./scripts/network/diag_iface_linux.sh -i enp1s0f0 --no-capture --mtu-target 8.8.8.8

# Via just (recomendado)
just diag-iface -i wlxa047d76360c5
just diag-iface --auto

# Traer evidencia al local
scp servidor:/tmp/diag-iface-*.tar.gz .
tar xzf diag-iface-*.tar.gz
cat diag-iface-*/REPORTE.md
```

______________________________________________________________________

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-04

**feat:** Script inicial de diagnóstico de interfaz de red.

- Recolección completa: red, sockets, WiFi, driver/USB, fail2ban, firewall, kernel, sysctl, MTU, hardware.
- Captura tcpdump opcional.
- Auto-detección de interfaz con más RX drops.
- Análisis automático con semáforo 🔴🟡🟢 en REPORTE.md.
- Recomendaciones de mitigación automáticas (autosuspend, fail2ban, ARP, conntrack).
- Empaquetado en `.tar.gz` para transporte vía scp.
