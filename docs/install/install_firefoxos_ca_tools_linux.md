---
title: install_firefoxos_ca_tools_linux.sh
description: Instala certutil para preparar una base NSS de Firefox OS en Debian.
tags:
  - instalación
  - firefox-os
  - seguridad
---

# install_firefoxos_ca_tools_linux.sh

Instala las herramientas NSS de Debian necesarias para validar y preparar una
copia de `cert9.db`. No modifica el Flame, no descarga certificados y no
inicia ADB.

- **Ruta:** `scripts/install/install_firefoxos_ca_tools_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-cache`, `apt-get`, `dpkg-query`, `sudo` solo durante `--apply`.

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

- Debian o un derivado compatible con APT.
- Candidato APT para `libnss3-tools`.
- Usuario normal con `sudo` disponible únicamente para `--apply`.

Debian proporciona `certutil`, `modutil` y otras herramientas NSS mediante
[`libnss3-tools`](https://packages.debian.org/forky/libnss3-tools). Este
instalador no instala un navegador antiguo, WebIDE ni un compilador ARM.

## Uso

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
just install-firefoxos-ca-tools --status
```

La instalación de `certutil` es independiente de la adquisición y aplicación
de certificados. Después se utiliza `just firefoxos-ca`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, el candidato APT y el estado local. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin usar `sudo`. |
| `--apply` | — | Instala `libnss3-tools` mediante APT. |
| `--status` | — | Muestra el estado sin modificar el equipo ni el teléfono. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El script no usa variables de configuración ni archivos `.env`. La selección
del paquete es fija para evitar instalar herramientas o fuentes no previstas.

## Ejemplos

### Instalación recomendada

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
```

### Verificación posterior

```bash
just install-firefoxos-ca-tools --status
certutil -H | sed -n '1,8p'
```

### Siguiente fase

```bash
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- `--apply` solo instala el paquete declarado mediante APT.
- No se usa `sudo` para ADB ni para escribir el teléfono.
- No se añaden grupos, reglas udev, certificados ni excepciones HTTPS.
- No se compila ni se reemplaza `libnssckbi.so`.

## Fallos conocidos

### `sin candidato APT: libnss3-tools`

**Causa:** las fuentes Debian no ofrecen el paquete en la configuración
actual.

**Solución:** revisa las fuentes APT y vuelve a ejecutar `--check`. No se
descargan paquetes externos como sustituto.

### `certutil no está disponible`

**Causa:** la instalación todavía no se ha aplicado o el `PATH` no contiene
`/usr/bin`.

**Solución:** ejecuta `just install-firefoxos-ca-tools --apply` y abre una
nueva shell si corresponde.

## Changelog

### [Unreleased]

- **feat:** añadir instalación separada de herramientas NSS para Firefox OS.
