---
title: install_mobile_hotspot_linux.sh
description: Preparar un AP Wi-Fi oculto con NetworkManager y WWAN
tags:
  - red
  - thinkpad
---

# install_mobile_hotspot_linux.sh

Prepara un perfil NetworkManager para compartir temporalmente la conexión móvil
de la ThinkPad mediante una red Wi-Fi oculta llamada `internet-movil`.

- **Ruta:** `scripts/install/install_mobile_hotspot_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `nmcli`, `NetworkManager`, `ModemManager`, `iw`, `rfkill`, `sudo` solo para APT

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

La ThinkPad debe tener una conexión WWAN activa y una tarjeta Wi-Fi que declare
soporte para modo `AP`. NetworkManager debe estar ejecutándose. `iw` y `rfkill`
se instalan mediante APT únicamente si faltan.

Crear la clave fuera del repositorio:

```bash
install -d -m 700 ~/.config/rafex
printf '%s\n' 'HOTSPOT_PSK=CAMBIA_ESTA_CLAVE' > ~/.config/rafex/mobile-hotspot.conf
chmod 600 ~/.config/rafex/mobile-hotspot.conf
```

La clave WPA2 debe tener entre 8 y 63 caracteres ASCII. No se registra ni se
muestra en la salida.

## Uso

```bash
just install-mobile-hotspot --check
just install-mobile-hotspot --plan
just install-mobile-hotspot --apply
just install-mobile-hotspot --status
```

La instalación prepara el perfil, pero no inicia la red.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, NetworkManager, WWAN, Wi-Fi y dependencias. |
| `--plan` | `--dry-run` | Muestra el plan sin instalar paquetes ni crear el perfil. |
| `--apply` | — | Instala `iw`/`rfkill` si faltan y crea el perfil administrado. |
| `--status` | — | Muestra el perfil y su estado sin mostrar la clave. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Cambia la raíz de configuración; por defecto `~/.config`. |
| `XDG_STATE_HOME` | Cambia la raíz de estado; por defecto `~/.local/state`. |

La clave de acceso no se acepta como variable de entorno ni argumento para
evitar que aparezca en historial o inspección de procesos.

## Ejemplos

```bash
just install-mobile-hotspot --check
just install-mobile-hotspot --plan
just install-mobile-hotspot --apply
just install-mobile-hotspot --status
```

Después se utiliza el helper operativo:

```bash
just mobile-hotspot --start
just mobile-hotspot --stop
```

## Protecciones de seguridad

- El perfil tiene `autoconnect=no` y no se inicia durante el arranque.
- El SSID se configura como no anunciable, pero un SSID oculto no sustituye WPA2.
- No se instala `hostapd` ni un `dnsmasq` independiente.
- No se modifica UFW, nftables, Polkit ni la conexión móvil permanentemente.
- El perfil se limita al usuario local mediante `connection.permissions`.
- La activación y desactivación posteriores no usan `sudo`.
- Si la ruta móvil no puede priorizarse, el AP no se inicia.

## Fallos conocidos

### `la tarjeta Wi-Fi no declara soporte AP`

**Causa:** el adaptador o su driver no ofrece modo punto de acceso.
**Solución:** usar otro adaptador Wi-Fi compatible con AP o conservar la conexión
móvil directamente en la ThinkPad.

### `HOTSPOT_PSK debe contener 8-63 caracteres ASCII`

**Causa:** falta la clave local, tiene permisos distintos de `0600` o contiene
caracteres no permitidos.
**Solución:** corregir `~/.config/rafex/mobile-hotspot.conf` y repetir `--apply`.

### `NetworkManager no permitió cargar el perfil como usuario normal`

**Causa:** la política Polkit no permite al usuario crear/modificar perfiles.
**Solución:** revisar la política existente de NetworkManager; el instalador no
crea permisos administrativos amplios automáticamente.

## Changelog

### [Unreleased]

**feat:** preparar AP móvil oculto administrado por NetworkManager.
