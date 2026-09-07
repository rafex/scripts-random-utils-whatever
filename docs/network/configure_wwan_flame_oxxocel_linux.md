---
title: configure_wwan_flame_oxxocel_linux.sh
description: Configurar datos móviles OXXO Cel y consultar SMS mediante el módem del Firefox OS Flame conectado por USB
tags:
  - red
  - wwan
  - modemmanager
  - firefoxos
---

# configure_wwan_flame_oxxocel_linux.sh

Configura el módem que ModemManager reconoce cuando un teléfono Firefox OS
Flame se conecta por USB, para usar datos móviles OXXO Cel mediante
NetworkManager. También permite listar los SMS que el módem expone al
sistema.

Hermano de
[configure_wwan_oxxocel_linux.sh](configure_wwan_oxxocel_linux.md): esa
administra la EM7455 interna de la ThinkPad; esta administra el módem del
Flame. Ambos usan el mismo APN OXXO Cel, pero son SIM y perfiles distintos
— conectar uno no debe afectar al otro (ver
[Requisitos](#requisitos) sobre cómo cada script identifica su propio
módem).

- **Ruta:** `scripts/network/configure_wwan_flame_oxxocel_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `NetworkManager`, `ModemManager`, `nmcli`, `mmcli`, `sudo` solo para `--apply`

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

- Debian o una distribución Linux con NetworkManager y systemd.
- Un Firefox OS Flame conectado por USB, con la SIM OXXO Cel insertada en
  el teléfono (no en la ThinkPad). Al conectarlo, ModemManager reconoce
  su módem por QMI (`qmi_wwan`) igual que un módem WWAN normal.
- El estado puede consultarse sin privilegios con `mmcli -L` y
  `mmcli -m <índice>`.
- El APN es el mismo que usa `configure_wwan_oxxocel_linux.sh`:
  `internet.mvne1.com`.
- Ejecutar el script como el usuario normal, no como root. `--apply`
  solicita privilegios solo mediante `sudo -v` para instalar paquetes y
  habilitar servicios.

Si además tienes la EM7455 interna con su propia SIM OXXO Cel conectada
al mismo tiempo, `mmcli -L` lista ambos módems y **el orden no es
estable** entre reinicios de ModemManager. Este script busca
explícitamente el módem que **no** menciona "Sierra Wireless" (esa lo
administra el otro script); si algún día agregas un tercer módem WWAN de
otro fabricante, revisa `mmcli -L` a mano antes de asumir cuál tomará
cada script.

## Uso

Desde la raíz del repositorio, con el Flame ya conectado por USB:

```bash
just configure-wwan-flame-oxxocel --check
just configure-wwan-flame-oxxocel --plan
just configure-wwan-flame-oxxocel --apply
just configure-wwan-flame-oxxocel --status
```

`--apply` crea o actualiza el perfil `Flame Oxxo Cel` y deja habilitada
su autoconexión, pero no ejecuta directamente una orden de conexión.
NetworkManager intentará activarlo cuando el Flame esté conectado y la
SIM y la red estén disponibles. La operación es idempotente: si existen
varios perfiles GSM con ese nombre, reutiliza primero el que está activo
y elimina únicamente los duplicados inactivos del mismo tipo. No toca
perfiles Wi-Fi, VPN ni conexiones con otro nombre — incluyendo el perfil
`OXXO Cel` de la EM7455.

```bash
just configure-wwan-flame-oxxocel --connect
just configure-wwan-flame-oxxocel --disconnect
```

`--connect` debe ejecutarse desde una terminal interactiva del usuario
normal. Activa el radio WWAN con NetworkManager, espera a que
ModemManager termine la transición del módem y sube el perfil por su
UUID. No ejecuta `sudo`, `mmcli --enable` ni comandos AT. Si se invoca
por SSH, usa una pseudo-terminal:

```bash
ssh -tt thinkpad 'cd /opt/repository/github/rafex/scripts-random-utils-whatever && just configure-wwan-flame-oxxocel --connect'
```

El script clasifica explícitamente la SIM como ausente, detectada,
bloqueada por PIN/PIN2 o desconocida. También distingue un módem
deshabilitado, uno registrado sin datos y una conexión de datos activa.

Para consultar los SMS almacenados por ModemManager:

```bash
just configure-wwan-flame-oxxocel --sms-list
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita paquetes, driver, servicios, módem, SIM y perfil sin modificar. |
| `--plan` | `--dry-run` | Muestra paquetes y cambios previstos sin modificar el sistema. |
| `--apply` | — | Instala dependencias, habilita servicios y crea o actualiza el perfil Flame Oxxo Cel. |
| `--status` | — | Muestra estado de WWAN, perfil y capacidades sin modificar. |
| `--connect` | — | Activa WWAN y conecta el perfil mediante `nmcli --ask`. |
| `--disconnect` | — | Desconecta el perfil Flame Oxxo Cel. |
| `--sms-list` | — | Lista los SMS expuestos por ModemManager. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `FLAME_OXXOCEL_PROFILE` | `Flame Oxxo Cel` | Nombre del perfil NetworkManager que administra el script. |

El APN no se toma de variables de entorno: queda fijado a
`internet.mvne1.com` para evitar configurar accidentalmente el perfil con
otro proveedor. No se aceptan PIN, usuario ni contraseña como argumentos
o variables.

## Ejemplos

Auditoría inicial con el Flame ya conectado:

```bash
just configure-wwan-flame-oxxocel --check
```

Instalación del soporte y creación del perfil:

```bash
just configure-wwan-flame-oxxocel --apply
```

Después de `--apply`, NetworkManager intentará conectar automáticamente
la WWAN cuando el Flame esté disponible. Si solicita el PIN, se introduce
de forma interactiva y no se guarda en el perfil. Para forzar la
conexión manualmente:

```bash
just configure-wwan-flame-oxxocel --connect
```

Usar otro nombre de perfil sin modificar el APN:

```bash
FLAME_OXXOCEL_PROFILE='Flame Oxxo Cel viajes' \
  just configure-wwan-flame-oxxocel --apply
```

Consultar los mensajes recibidos:

```bash
just configure-wwan-flame-oxxocel --sms-list
```

## Protecciones de seguridad

- `--check`, `--plan`, `--status` y `--sms-list` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`.
- No se guardan PIN, usuarios, contraseñas, IMEI ni identificadores del módem.
- El perfil tiene autoconexión habilitada y usa una métrica de ruta alta
  (`700`) para conservar Wi-Fi como conexión preferida (`600`). Ambas
  interfaces pueden permanecer conectadas; la ruta por Wi-Fi se elige por
  tener la métrica menor.
- `connection.metered yes` identifica la WWAN como datos medidos.
- El roaming queda desactivado inicialmente (`gsm.home-only yes`).
- No se modifican firmware, composición USB, BIOS, GRUB, particiones,
  `fstab` ni configuraciones de NetworkManager ajenas al perfil
  administrado — incluyendo el perfil `OXXO Cel` de la EM7455.
- No se ejecutan comandos AT ni se detiene ModemManager para acceder
  directamente al nodo QMI/MBIM.

## Fallos conocidos

### `find_modem_id` selecciona el módem equivocado con dos módems WWAN presentes

**Causa:** el orden de `/org/freedesktop/ModemManager1/Modem/<N>` que
reporta `mmcli -L` no es estable entre reinicios de ModemManager. Este
script excluye explícitamente cualquier línea que mencione "Sierra
Wireless" (para no competir con `configure_wwan_oxxocel_linux.sh` por la
EM7455), pero si algún día hay un tercer módem WWAN de otro fabricante
conectado a la vez, la heurística puede volver a ser ambigua.

**Solución:** ejecuta `mmcli -L` para confirmar cuántos módems hay y cuál
es cuál antes de depender de la detección automática; `--status` también
imprime el índice y fabricante del módem que seleccionó.

### `ModemManager no detecta ningún módem del Flame`

**Causa:** el Flame no está conectado por USB, la pantalla está
bloqueada, la depuración USB no está activa, o el modo USB del teléfono
no expone el módem al host.

**Solución:** conecta el Flame por USB, desbloquea la pantalla y repite
`mmcli -L`. Si sigue sin aparecer, revisa el modo de conexión USB del
teléfono (algunos requieren activar explícitamente "depuración
remota"/USB en Ajustes).

### `la SIM está ausente o no es detectada por el módem del Flame`

**Causa:** la SIM OXXO Cel no está insertada en el Flame, está mal
orientada, o el teléfono todavía no terminó de inicializar el módem tras
conectarse.

**Solución:** inserta la SIM en el Flame (no en la ThinkPad) y repite
`mmcli -L`/`--check` tras unos segundos.

## Changelog

### [Unreleased]

- **feat:** administrar el módem OXXO Cel del Firefox OS Flame conectado
  por USB como perfil NetworkManager independiente (`Flame Oxxo Cel`),
  hermano de `configure_wwan_oxxocel_linux.sh` (EM7455 interna) — mismo
  APN, perfiles y módems separados.
