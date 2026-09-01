---
title: install_printers_linux.sh
description: Instala CUPS, SANE y controladores Debian para la Epson XP-241 y la Xerox Phaser 3020.
tags:
  - instalación
  - impresión
  - escáner
---

# install_printers_linux.sh

Instala la base de impresión y escaneo para la ThinkPad. No crea colas ni
comparte impresoras; la configuración de las colas se realiza después con
`configure_printers_linux.sh`.

- **Ruta:** `scripts/install/install_printers_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query, systemctl, sudo.

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

- Debian o un derivado compatible con candidatos APT.
- `sudo` para `--apply`.
- Para configurar las colas, conectar las impresoras por USB o incorporarlas a
  la misma red local.

## Uso

```bash
just install-printers --check
just install-printers --plan
just install-printers --apply
just install-printers --status
```

Después de instalar, ejecutar `just configure-printers --status` y
`just configure-printers --apply` con las impresoras encendidas.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Consulta paquetes y CUPS sin modificar. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin escribir. |
| `--apply` | — | Instala paquetes y habilita `cups.service`; requiere sudo. |
| `--status` | — | Muestra paquetes, servicio, colas y escáneres visibles. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. Los argumentos de la línea de comandos
son la única fuente de configuración.

## Ejemplos

```bash
just install-printers --check
just install-printers --plan
just install-printers --apply
just install-printers --status
```

## Protecciones de seguridad

- Solo `--apply` usa `sudo`.
- No se habilita `cups-browsed`, `saned` ni la compartición remota.
- No se abren puertos en UFW ni se modifican NetworkManager, WWAN o mDNS.
- No se descargan binarios propietarios automáticamente.
- La Xerox usa inicialmente el controlador Debian Splix y la Epson ESC/P-R.

## Fallos conocidos

### `faltan candidatos APT`

**Causa:** falta una fuente Debian válida, el índice APT está desactualizado o
el paquete aún no está disponible en la arquitectura.

**Solución:** revisa las fuentes Debian, ejecuta `sudo apt-get update` y repite
`--check`.

### `cups.service no está activo`

**Causa:** el daemon no pudo iniciarse o la instalación fue interrumpida.

**Solución:** revisa `systemctl status cups.service` y
`journalctl -u cups.service`; no ejecutes CUPS como root manualmente.

## Changelog

### [Unreleased]

- **feat:** añadir instalación reproducible de CUPS, SANE y controladores Debian.
