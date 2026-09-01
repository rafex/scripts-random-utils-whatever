---
title: install_mdns_linux.sh
description: Instala y configura mDNS/Avahi con resolución local y alcance seguro
tags:
  - red
  - mdns
  - privacidad
---

# install_mdns_linux.sh

Instala Avahi y `libnss-mdns` para resolver nombres `.local` y publicar el
nombre de la ThinkPad en la red local. El valor predeterminado permite mDNS
solo en Wi-Fi y Ethernet; la WWAN queda fuera.

- **Ruta:** `scripts/network/install_mdns_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `apt-get`, `apt-cache`, `dpkg-query`, `nmcli`, `systemctl`, `sudo` para aplicar

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

Debian o un derivado compatible con NetworkManager, Avahi y `systemd`. El
perfil actual usa `wlp4s0` para Wi-Fi y `enp0s31f6` para Ethernet cuando están
disponibles.

El paquete `libnss-mdns` integra la resolución `.local` con NSS y
`avahi-daemon` gestiona multicast DNS/DNS-SD. El script no instala servicios de
descubrimiento en la WWAN.

## Uso

Ejecuta primero el diagnóstico:

```bash
just install-mdns --check
just install-mdns --plan
```

Aplica la configuración con `sudo` solo en esta fase:

```bash
just install-mdns --apply
```

Consulta el resultado:

```bash
just install-mdns --status
getent hosts thinkpad.local
```

La configuración publica el hostname local, pero no publica workstation,
HINFO, dominios ni servidores DNS. Los servicios concretos solo se anunciarán
si se añaden explícitamente archivos de servicio de Avahi.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquetes, interfaces, NSS y servicio sin escribir. |
| `--plan` | `--dry-run` | Muestra los cambios previstos sin modificar el sistema. |
| `--apply` | — | Instala paquetes, actualiza Avahi/NSS y reinicia Avahi. Requiere `sudo`. |
| `--status` | — | Muestra el estado del servicio y la resolución local. |
| `--interfaces <lista>` | — | Permite una lista explícita separada por comas; no acepta WWAN. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos tienen prioridad sobre la detección automática. No se aceptan
variables para habilitar WWAN ni para guardar credenciales.

| Variable | Predeterminado | Descripción |
|---|---|---|
| `PATH` | El del proceso | Se anteponen rutas estándar para localizar APT y systemd. |

## Ejemplos

Configuración recomendada para la ThinkPad:

```bash
just install-mdns --apply
```

Configurar interfaces locales concretas:

```bash
just install-mdns --plan --interfaces wlp4s0,enp0s31f6
just install-mdns --apply --interfaces wlp4s0,enp0s31f6
```

Verificar resolución y servicio:

```bash
getent hosts thinkpad.local
systemctl status avahi-daemon --no-pager
avahi-browse --all --terminate
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no requieren `sudo` ni modifican archivos.
- `--apply` usa `sudo` únicamente para APT, `/etc/avahi/avahi-daemon.conf`,
  `/etc/nsswitch.conf` y el servicio Avahi.
- Antes de cambiar archivos existentes se crea un respaldo fechado.
- El script limita Avahi a interfaces Wi-Fi/Ethernet detectadas y rechaza
  explícitamente interfaces WWAN como `wwp*` o `cdc-wdm*`.
- No modifica NetworkManager, rutas, DNS global, UFW, WWAN, SSH ni servicios de
  compartición.
- No publica automáticamente servicios de archivos, SSH, impresoras o
  escritorios remotos.
- En una Wi-Fi pública, `hostname.local` y la dirección local pueden ser
  visibles para otros dispositivos del mismo segmento. Si no necesitas mDNS,
  desactiva Avahi con una decisión explícita del administrador.

## Fallos conocidos

### `no se detectaron interfaces Wi-Fi/Ethernet`

**Causa:** NetworkManager no está instalado, no responde o la máquina no tiene
una interfaz local disponible.

**Solución:** revisa `nmcli device status`. No habilites WWAN como sustituto
para publicar mDNS.

### `nsswitch no contiene mdns4_minimal`

**Causa:** la resolución `.local` todavía no está integrada con NSS.

**Solución:** ejecuta `just install-mdns --apply` y verifica la línea `hosts:`
de `/etc/nsswitch.conf`. El script conserva las entradas no administradas.

### `thinkpad.local` no resuelve desde SSH

**Causa:** mDNS funciona por multicast dentro de la red local y el cliente
remoto puede estar en otra red, VPN o segmento aislado.

**Solución:** prueba desde otro equipo conectado a la misma Wi-Fi/Ethernet con
`getent hosts thinkpad.local`. La falta de resolución desde la propia máquina
no siempre indica que Avahi esté caído.

### `avahi-daemon` escucha UDP 5353

**Causa:** es el puerto estándar de mDNS, no una conexión entrante TCP de
Internet.

**Solución:** en redes públicas evita publicar servicios y mantén WWAN fuera de
las interfaces permitidas. Si no usas descubrimiento local, detén Avahi.

## Changelog

### [Unreleased]

- **feat:** añadir instalación y configuración idempotente de mDNS/Avahi con
  resolución `.local` y exclusión de WWAN.

