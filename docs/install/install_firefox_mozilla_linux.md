---
title: install_firefox_mozilla_linux.sh
description: Instalación de Firefox DEB desde Mozilla
tags:
  - instalación
---

# install_firefox_mozilla_linux.sh

Configura el repositorio APT oficial de Mozilla e instala el paquete DEB
nativo `firefox`, sin instalar ni eliminar Firefox ESR automáticamente.

- **Ruta:** `scripts/install/install_firefox_mozilla_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `sudo`; el script instala `wget`, `gnupg` y `ca-certificates` si faltan

______________________________________________________________________

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

- Debian 12 o posterior con `apt-get`.
- `sudo` configurado para el usuario actual.
- Conectividad HTTPS a `packages.mozilla.org`.
- Ejecutar como usuario normal, no como root.

El repositorio usa el formato deb822 recomendado para Debian moderno:
`/etc/apt/sources.list.d/mozilla.sources`.

## Uso

Diagnostica sin cambios:

```sh
just install-firefox-mozilla --check
```

Revisa el plan:

```sh
just install-firefox-mozilla --plan
```

Configura el repositorio e instala Firefox nativo:

```sh
just install-firefox-mozilla --apply
```

El paquete instalado es `firefox`, no `firefox-esr`. El script instala
`firefox-l10n-es-mx` cuando Mozilla lo ofrece para la versión disponible.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica repositorio, clave, paquetes y preferencias sin cambios |
| `--plan` | `--dry-run` | Muestra acciones previstas sin modificar el sistema |
| `--apply` | — | Configura Mozilla APT e instala Firefox DEB nativo |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza variables de entorno para repositorios, claves ni
contraseñas. La contraseña de sudo se solicita únicamente mediante `sudo -v`.

## Ejemplos

### Forma explícita recomendada

```sh
just install-firefox-mozilla --apply
```

### Ejecución directa

```sh
bash scripts/install/install_firefox_mozilla_linux.sh --check
bash scripts/install/install_firefox_mozilla_linux.sh --plan
bash scripts/install/install_firefox_mozilla_linux.sh --apply
```

### Verificar el origen del paquete

```sh
firefox --version
apt-cache policy firefox
dpkg-query -W -f='${Package}\t${Version}\n' firefox firefox-esr 2>/dev/null
```

## Protecciones de seguridad

- Usa exclusivamente `https://packages.mozilla.org/apt`.
- Verifica la huella de la clave antes de instalarla:
  `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`.
- Usa `Signed-By` para limitar la clave al repositorio de Mozilla.
- Respaldará la clave, la fuente y las preferencias anteriores en
  `/var/backups/rafex-mozilla-firefox/` antes de reemplazarlas.
- No acepta, almacena ni transmite contraseñas.
- No elimina `firefox-esr` ni modifica perfiles de Firefox.
- No configura Snap, Flatpak, PPAs ni repositorios de terceros.

## Fallos conocidos

### `firefox-esr` ya está instalado

**Causa:** Debian puede traer Firefox ESR instalado por defecto.

**Solución:** el script conserva ESR deliberadamente. Comprueba ambos paquetes
con `apt-cache policy` y decide manualmente si deseas eliminar ESR después de
validar Firefox nativo.

### `no se pudo descargar la clave de Mozilla`

**Causa:** falta de conectividad HTTPS, DNS, proxy o `wget`.

**Solución:** verifica `curl -I https://packages.mozilla.org/apt` o instala
`wget` y repite `--apply`.

### `huella de clave inesperada`

**Causa:** la clave descargada no coincide con la huella publicada por Mozilla.

**Solución:** no continúes manualmente; revisa proxy, DNS y fecha del sistema.
El script no instala la clave si la huella no coincide.

### `gpg: Fatal: .../.gnupg: directory does not exist!`

**Causa:** algunas versiones de GnuPG requieren un `GNUPGHOME` válido incluso
cuando se usa `--no-default-keyring`; una instalación nueva puede no tener
creado `~/.gnupg`.

**Solución:** actualizar el repositorio y repetir `--apply`. El script usa un
directorio GnuPG temporal y aislado exclusivamente para verificar la clave;
no modifica `~/.gnupg`.

### `apt-get update` no valida `packages.mozilla.org`

**Causa:** fuente incompleta, clave incorrecta o reloj del sistema inválido.

**Solución:** ejecuta `just install-firefox-mozilla --check`, revisa los
respaldos y corrige la causa antes de repetir `--apply`.

## Changelog

### [Unreleased]

- **feat:** añadir repositorio APT oficial de Mozilla con verificación de
  huella e instalación de Firefox DEB nativo.
- **fix:** verificar la clave Mozilla con un `GNUPGHOME` temporal cuando el
  usuario aún no tiene configuración local de GnuPG.
