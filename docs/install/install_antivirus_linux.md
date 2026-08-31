---
title: install_antivirus_linux.sh
description: Instala ClamAV y prepara el escaneo manual o automático opcional de USB.
tags:
  - instalación
  - seguridad
  - clamav
---

# install_antivirus_linux.sh

Instala ClamAV, su daemon, FreshClam y ClamTk. Instala además el escáner
`scan-usb-clamav.sh` en `~/.local/bin`. El escaneo automático al montar USB es
opt-in y usa el event-hook de udiskie.

- **Ruta:** `scripts/install/install_antivirus_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query, systemctl, sudo; udiskie solo para `--auto-usb`.

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

- Debian con candidatos APT para `clamav`, `clamav-daemon`, `clamav-freshclam` y
  `clamtk`.
- Usuario normal con sudo para `--apply`.
- `clamdscan` lo proporciona `clamav-daemon`; no es un paquete separado en
  Debian.

## Uso

```bash
just install-antivirus --check
just install-antivirus --plan
just install-antivirus --apply
just install-antivirus --status
```

El flujo diario recomendado es instalar y luego escanear cada memoria de forma
manual con `just scan-usb --path ...`. FreshClam actualiza las firmas mediante
su servicio.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Consulta paquetes, servicios y hook sin modificar. |
| `--plan` | `--dry-run` | Muestra las acciones previstas. |
| `--apply` | — | Instala ClamAV, activa FreshClam/daemon e instala el escáner. |
| `--status` | — | Muestra paquetes, servicios y política activa. |
| `--auto-usb` | — | Añade explícitamente el hook de escaneo a udiskie. |
| `--disable-auto-usb` | — | Retira solo el hook administrado por este script. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. El hook usa la ruta de la sesión del
usuario para llamar a `~/.local/bin/scan-usb-clamav.sh`.

## Ejemplos

```bash
just install-antivirus --apply
just scan-usb --path /run/media/$USER/USB
just install-antivirus --apply --auto-usb
just install-antivirus --apply --disable-auto-usb
```

## Protecciones de seguridad

- No habilita `clamonacc` ni ejecuta el antivirus como mecanismo de acceso
  permanente.
- No borra, mueve ni pone en cuarentena archivos.
- No guarda contraseñas, claves, capturas ni credenciales.
- No cambia NetworkManager, UFW, udiskie fuera del hook administrado ni el
  montaje de discos.
- Si udiskie ya tiene un `event_hook` no administrado, aborta para no
  sobrescribirlo.

## Fallos conocidos

### `udiskie ya tiene un event_hook no administrado`

**Causa:** el usuario o una aplicación ya configuró un hook distinto.

**Solución:** integra manualmente ambos comandos y conserva una sola clave
`event_hook` antes de repetir `--auto-usb`.

### `clamav-daemon.service inactivo`

**Causa:** la base de firmas aún se está inicializando o el servicio no pudo
arrancar.

**Solución:** revisa `sudo journalctl -u clamav-daemon -u clamav-freshclam` y
espera a que FreshClam complete. El escaneo manual con `clamscan` puede usarse
cuando la base esté disponible.

## Changelog

### [Unreleased]

- **feat:** añadir ClamAV y escaneo USB seguro manual/opt-in.
