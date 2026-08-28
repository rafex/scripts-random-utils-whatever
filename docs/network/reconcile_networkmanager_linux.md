---
title: reconcile_networkmanager_linux.sh
description: Entrega las interfaces físicas de Debian a NetworkManager y aparta la configuración de ifupdown.
tags:
  - red
  - networkmanager
  - migracion
---

# reconcile_networkmanager_linux.sh

Migra de forma controlada una instalación que todavía usa `ifupdown`, `ifup@*.service`,
`dhcpcd` o un `wpa_supplicant` independiente para que NetworkManager administre las
interfaces físicas.

- **Ruta:** `scripts/network/reconcile_networkmanager_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `sudo`, `apt-get`, `systemd`, `NetworkManager`/`nmcli`

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

- Ejecutar `--check` y `--plan` antes de aplicar.
- Tener `sudo` configurado para el usuario actual.
- Ejecutar `--apply` desde la consola local de la ThinkPad. La migración reinicia
  NetworkManager y puede cortar SSH.
- Mantener una segunda forma de acceso: consola local, teclado y pantalla.
- Conocer los SSID y contraseñas que se volverán a registrar. No se copian secretos
  desde ifupdown, `wpa_supplicant` ni perfiles de NetworkManager.

## Uso

Desde la raíz del repositorio:

```bash
just reconcile-networkmanager --check
just reconcile-networkmanager --plan
just reconcile-networkmanager --apply
```

Después de aplicar, valida el estado:

```bash
nmcli device status
nmcli general status
nmcli device wifi list
```

Reconecta cada Wi-Fi de forma interactiva:

```bash
nmcli device wifi connect "NOMBRE_DEL_WIFI" --ask
```

NetworkManager guardará el perfil en su ubicación normal y gestionará DHCP,
`wpa_supplicant` y DNS según la configuración de la instalación.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita servicios, políticas, ifupdown y dispositivos sin cambiar nada. Es el modo predeterminado. |
| `--plan` | `--dry-run` | Muestra las acciones que se realizarían sin usar `sudo` ni modificar el sistema. |
| `--apply` | — | Instala dependencias y realiza la migración. |
| `--allow-ssh-disconnect` | — | Confirma explícitamente una ejecución remota que puede dejar SSH sin red. Úsalo solo con acceso de recuperación. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no usa `.env` ni variables de entorno para credenciales o parámetros
de red. `SSH_CONNECTION` se detecta automáticamente para impedir una aplicación
accidental por SSH. La opción explícita `--allow-ssh-disconnect` tiene prioridad
sobre esa protección.

## Ejemplos

Auditoría recomendada:

```bash
just reconcile-networkmanager --check
```

Revisión previa sin cambios:

```bash
just reconcile-networkmanager --plan
```

Aplicación local en la ThinkPad:

```bash
just reconcile-networkmanager --apply
```

Compatibilidad de emergencia desde SSH, solo si existe acceso local o remoto
alternativo para recuperar la red:

```bash
ssh thinkpad 'cd ~/repository/github/rafex/scripts-random-utils-whatever && \
  just reconcile-networkmanager --apply --allow-ssh-disconnect'
```

## Protecciones de seguridad

- `--check`, `--plan` y `--dry-run` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`; nunca la lee,
  almacena ni transmite.
- La configuración original se respalda antes de reemplazarla en
  `/var/backups/rafex-networkmanager/`, con permisos `0700`.
- `/etc/network/interfaces` se conserva en el respaldo y queda con solo loopback;
  los archivos no-loopback de `interfaces.d` se apartan en el mismo respaldo.
- Se detienen y deshabilitan únicamente los servicios independientes
  `networking.service`, `wpa_supplicant.service` y `dhcpcd.service` cuando están
  activos/habilitados. NetworkManager seguirá usando su propio supplicant.
- No se modifican particiones, `fstab`, GRUB, contraseñas Wi-Fi ni perfiles de
  NetworkManager existentes.
- No se ejecuta `ifdown` sobre la interfaz activa: se detienen las unidades
  `ifup@<interfaz>.service` y luego se reinicia NetworkManager.

## Fallos conocidos

### `--apply se ejecutó por SSH`

**Causa:** Reiniciar NetworkManager puede cortar la conexión usada para ejecutar
el script.

**Solución:** Ejecuta desde la consola local. Solo usa
`--allow-ssh-disconnect` si tienes acceso alternativo y aceptas la interrupción.

### La Wi-Fi queda desconectada después de la migración

**Causa:** La migración no copia secretos ni crea perfiles automáticamente.

**Solución:** Conecta el SSID con `nmcli device wifi connect "SSID" --ask` o usa
`nmtui`/el applet de NetworkManager.

### Una interfaz sigue como `unmanaged`

**Causa:** Puede existir otra política en `/etc/NetworkManager`, una regla udev o
una configuración externa que no fue detectada.

**Solución:** Ejecuta `just reconcile-networkmanager --check`, revisa las líneas
reportadas y confirma `nmcli general permissions` y el contenido de
`/etc/NetworkManager/conf.d/`.

### Se necesita volver temporalmente a ifupdown

**Causa:** Una aplicación o configuración heredada aún depende de ifupdown.

**Solución:** No restaures archivos directamente sobre `/etc/network/interfaces`.
Usa el archivo fechado correspondiente en `/var/backups/rafex-networkmanager/`,
revisa su contenido y restaura manualmente desde la consola; después detén
NetworkManager para evitar dos gestores simultáneos.

## Changelog

### [Unreleased]

- **feat:** añade migración segura de ifupdown/dhcpcd a NetworkManager.
- **docs:** documenta respaldos, reconexión Wi-Fi y protección contra pérdida de SSH.

