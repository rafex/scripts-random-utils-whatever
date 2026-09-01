---
title: configure_printers_linux.sh
description: Crea colas CUPS idempotentes para Epson XP-241 y Xerox Phaser 3020.
tags:
  - impresión
  - cups
  - epson
  - xerox
---

# configure_printers_linux.sh

Descubre impresoras USB, IPP, IPPS o mDNS y crea las colas estables
`Epson_XP_241` y `Xerox_Phaser_3020`. La Xerox queda como predeterminada cuando
está disponible.

- **Ruta:** `scripts/install/configure_printers_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, CUPS (`lpadmin`, `lpinfo`, `lpstat`), `sudo` para crear colas y `scanimage` para mostrar escáneres.

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

Instala primero la base:

```bash
just install-printers --apply
```

Después enciende la impresora y conéctala por USB o a la misma red local que la
ThinkPad. Para descubrimiento de red se usa mDNS/IPP; no se fija una dirección
IP ni se guardan contraseñas.

## Uso

```bash
just configure-printers --check
just configure-printers --plan
just configure-printers --apply
just configure-printers --status
just printer-test --printer xerox
just printer-test --printer epson
```

Para escanear, la XP-241 es el dispositivo multifunción y la Xerox Phaser 3020
se considera únicamente impresora:

```bash
just scan-document --list
just scan-document --output ~/Documents/escaneo.png
simple-scan
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra colas, dispositivos y escáneres sin modificar. |
| `--plan` | `--dry-run` | Muestra las colas que se crearían sin escribir. |
| `--apply` | — | Crea o conserva las colas; puede solicitar sudo. |
| `--status` | — | Muestra estado de CUPS, descubrimiento y SANE. |
| `--test-print` | — | Envía una página de prueba a una cola existente. |
| `--printer epson\|xerox\|all` | — | Limita la operación a una impresora. |
| `--device-uri <URI>` | — | Usa una URI explícita cuando hay varias coincidencias. |
| `--replace` | — | Recrea una cola con URI distinta; puede eliminar trabajos pendientes. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. Se usan las URI reportadas por
`lpinfo -v` o la URI explícita de `--device-uri`.

## Ejemplos

```bash
# Detectar las impresoras conectadas
just configure-printers --check

# Configurar ambas y dejar Xerox como predeterminada
just configure-printers --apply

# Configurar solo una URI concreta mostrada por lpinfo -v
just configure-printers --apply --printer epson --device-uri 'usb://EPSON/...' 

# Confirmar que la impresión normal no requiere sudo
just printer-test --printer xerox
```

Si hay varias URI para un mismo modelo, el configurador las mostrará y se debe
repetir el comando con la URI elegida. No se debe incluir `usuario:contraseña@`
en una URI.

## Protecciones de seguridad

- Las colas tienen nombres fijos para evitar duplicados.
- Una cola con otra URI no se sobrescribe sin `--replace`.
- `--replace` se reserva para una decisión explícita y puede eliminar trabajos
  pendientes de esa cola.
- Solo la administración inicial de CUPS requiere sudo; imprimir y escanear se
  ejecutan como el usuario normal.
- No se habilita `cups-browsed`, `saned`, un bridge de red ni compartición remota.
- No se guardan credenciales de impresoras ni contraseñas Wi-Fi.

## Fallos conocidos

### `no se detecta el dispositivo`

**Causa:** la impresora está apagada, no está conectada, no está en la misma
red, o el dispositivo USB está siendo retenido por otro servicio.

**Solución:** conecta y enciende la impresora; revisa `lpinfo -v`,
`avahi-browse -rt _ipp._tcp` y repite `--status`.

### `no se encontró un PPD Debian para Xerox Phaser 3020`

**Causa:** Splix no fue instalado o la versión disponible no expone el PPD del
modelo.

**Solución:** ejecuta `lpinfo -m | grep -Ei 'phaser|3020|splix'`. No se
instalará automáticamente el antiguo controlador propietario de Xerox; debe
evaluarse de forma separada y con un checksum verificado.

### `no se detecta un escáner Epson`

**Causa:** la XP-241 no está conectada, el backend SANE no la reconoce por esa
interfaz o la impresora está en otra red.

**Solución:** revisa `sane-find-scanner`, `scanimage -L` y el USB ID. La
impresión puede funcionar aunque el escáner requiera el controlador oficial de
Epson; el script no instala binarios externos automáticamente.

## Changelog

### [Unreleased]

- **feat:** añadir colas CUPS idempotentes para Epson XP-241 y Xerox Phaser 3020.
