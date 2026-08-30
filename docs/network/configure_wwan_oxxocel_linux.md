---
title: configure_wwan_oxxocel_linux.sh
description: Configurar datos móviles OXXO Cel y consultar SMS mediante la EM7455 en Linux
tags:
  - red
  - wwan
  - modemmanager
---

# configure_wwan_oxxocel_linux.sh

Configura el módem Sierra Wireless EM7455 de la ThinkPad X1 Yoga para usar
datos móviles OXXO Cel mediante NetworkManager y ModemManager. También permite
listar los SMS que el módem expone al sistema.

- **Ruta:** `scripts/network/configure_wwan_oxxocel_linux.sh`
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
- Módem WWAN compatible con ModemManager. La ThinkPad X1 Yoga auditada usa una
  Sierra Wireless EM7455 en modo `cdc_mbim`.
- SIM OXXO Cel insertada y detectada. El estado actual puede consultarse sin
  privilegios con `mmcli -L` y `mmcli -m <índice>`.
- El APN oficial para la SIM México es `internet.mvne1.com`.
- Ejecutar el script como el usuario normal, no como root. `--apply` solicita
  privilegios solo mediante `sudo -v` para instalar paquetes y habilitar servicios.

La página vigente de configuración de OXXO Cel está en
[oxxocel.com/apn](https://www.oxxocel.com/apn). Sus instrucciones enlazan con
la configuración de la SIM México en
[my.oxxocel.com/apn](https://my.oxxocel.com/apn).

## Uso

Desde la raíz del repositorio:

```bash
just configure-wwan-oxxocel --check
just configure-wwan-oxxocel --plan
just configure-wwan-oxxocel --apply
just configure-wwan-oxxocel --status
```

`--apply` crea el perfil `OXXO Cel`, pero no enciende una conexión de datos.
Después de insertar la SIM, activa la conexión de forma explícita:

```bash
just configure-wwan-oxxocel --connect
just configure-wwan-oxxocel --disconnect
```

Para consultar los SMS almacenados por ModemManager:

```bash
just configure-wwan-oxxocel --sms-list
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita paquetes, driver, servicios, módem, SIM y perfil sin modificar. |
| `--plan` | `--dry-run` | Muestra paquetes y cambios previstos sin modificar el sistema. |
| `--apply` | — | Instala dependencias, habilita servicios y crea o actualiza el perfil OXXO Cel. |
| `--status` | — | Muestra estado de WWAN, perfil y capacidades sin modificar. |
| `--connect` | — | Activa WWAN y conecta el perfil mediante `nmcli --ask`. |
| `--disconnect` | — | Desconecta el perfil OXXO Cel. |
| `--sms-list` | — | Lista los SMS expuestos por ModemManager. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `WWAN_OXXOCEL_PROFILE` | `OXXO Cel` | Nombre del perfil NetworkManager que administra el script. |

El APN no se toma de variables de entorno: queda fijado a `internet.mvne1.com`
para evitar configurar accidentalmente un perfil OXXO Cel con otro proveedor.
No se aceptan PIN, usuario ni contraseña como argumentos o variables.

## Ejemplos

Auditoría inicial sin SIM:

```bash
just configure-wwan-oxxocel --check
```

Instalación del soporte y creación del perfil:

```bash
just configure-wwan-oxxocel --apply
```

Conectar manualmente después de insertar la SIM. Si NetworkManager solicita el
PIN, se introduce de forma interactiva y no se guarda en el perfil:

```bash
just configure-wwan-oxxocel --connect
```

Usar otro nombre de perfil sin modificar el APN:

```bash
WWAN_OXXOCEL_PROFILE='OXXO Cel ThinkPad' \
  just configure-wwan-oxxocel --apply
```

Consultar los mensajes recibidos:

```bash
just configure-wwan-oxxocel --sms-list
```

## Protecciones de seguridad

- `--check`, `--plan`, `--status` y `--sms-list` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`.
- No se guardan PIN, usuarios, contraseñas, IMEI ni identificadores del módem.
- El perfil no tiene autoconexión y usa una métrica de ruta alta (`700`) para
  conservar Wi-Fi como conexión preferida.
- El roaming queda desactivado inicialmente (`gsm.home-only yes`).
- No se modifican firmware, composición USB, BIOS, GRUB, particiones, `fstab` ni
  configuraciones de NetworkManager ajenas al perfil administrado.
- El script no usa `ofono`, porque ModemManager y oFono no deben administrar el
  mismo módem simultáneamente.
- No se ejecutan comandos AT ni se detiene ModemManager para acceder directamente
  al nodo MBIM.

## Fallos conocidos

### `sim-missing`

**Causa:** la SIM no está insertada, está mal orientada, el slot está deshabilitado
en firmware o la EM7455 todavía está en bajo consumo.

**Solución:** inserta la SIM, comprueba que WWAN esté habilitado en BIOS y ejecuta
`mmcli -L` y `just configure-wwan-oxxocel --status`. El APN no puede corregir una
SIM que el módem no detecta.

### `modem has no voice capabilities`

**Causa:** la EM7455 de esta ThinkPad no expone capacidades de voz a ModemManager.

**Solución:** las llamadas telefónicas nativas no son posibles con este módulo.
Usa el teléfono, una aplicación VoIP o investiga un reemplazo WWAN compatible con
voz/VoLTE, BIOS, antenas y el operador. No se instalará oFono como supuesto
arreglo.

### `nmcli` no puede modificar el perfil

**Causa:** NetworkManager no está gestionado por el usuario actual o falta la
política polkit de NetworkManager.

**Solución:** valida `systemctl is-active NetworkManager`, el grupo `netdev` y la
configuración de permisos antes de usar `--apply`. No ejecutes todo el script con
`sudo`.

### `failed to modify connection.permissions: permiso no válido «user:rafex:»`

**Causa:** algunas versiones de NetworkManager rechazan el campo reservado vacío
que se expresa como `user:rafex:`.

**Solución:** el instalador usa la forma compatible `user:rafex` y puede volver a
ejecutarse para completar el perfil creado parcialmente.

### `campo «NAME» no válido` al consultar el perfil

**Causa:** algunas versiones recientes de NetworkManager ya no aceptan los
alias abreviados `NAME`, `TYPE`, `AUTOCONNECT` o `DEVICE` en `nmcli -f` para
perfiles de conexión.

**Solución:** el instalador consulta los nombres completos de propiedades,
como `connection.id`, `connection.type` y `connection.autoconnect`.

### `hay otra conexión con el nombre «OXXO Cel»`

**Causa:** NetworkManager permite perfiles con nombres repetidos y puede
seleccionar uno distinto de forma ambigua si se modifica por nombre.

**Solución:** el instalador localiza el perfil GSM por nombre y tipo, obtiene su
UUID y realiza las modificaciones usando ese UUID. Los duplicados antiguos se
deben revisar y eliminar manualmente por UUID después de confirmar que no están
en uso.

### `ModemManager no detecta ningún módem WWAN`

**Causa:** el módem está deshabilitado, falta el driver, el dispositivo no está
presente o la BIOS no habilita WWAN.

**Solución:** revisa `lsusb`, `lsusb -t`, `lsmod | grep cdc_mbim`,
`nmcli radio` y el estado de ModemManager. No cambies la composición USB sin una
investigación específica del modelo.

### `--sms-list` no muestra mensajes

**Causa:** la SIM no está disponible, el módem no está habilitado o el firmware y
el operador no exponen el almacén SMS por MBIM.

**Solución:** conecta primero el perfil, confirma el registro en red y repite el
comando. La recepción de SMS depende de la SIM, firmware y operador.

## Changelog

### [Unreleased]

**feat:** configurar datos OXXO Cel manualmente y consultar SMS mediante ModemManager.

- Añadir perfil NetworkManager con APN `internet.mvne1.com`.
- Detectar dinámicamente el módem y documentar la ausencia de voz de la EM7455.

**fix:** aceptar la sintaxis de permisos de conexión de NetworkManager en Debian.

**fix:** usar propiedades completas de `nmcli` y reportar claramente fallos de `sudo` o `systemctl`.

**fix:** seleccionar y modificar el perfil WWAN por UUID para evitar duplicados.
