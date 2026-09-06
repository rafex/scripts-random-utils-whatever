---
title: install_albert_linux.sh
description: Instalación de Albert (lanzador agnóstico de escritorio) desde el repositorio OBS oficial
tags:
  - instalación
  - i3
---

# install_albert_linux.sh

Configura el repositorio APT oficial de Albert (openSUSE Build Service)
e instala el paquete `albert` en Debian. Opcionalmente agrega un atajo
de prueba en i3 (`$mod+a`) sin modificar el binding existente de rofi
(`$mod+space`).

- **Ruta:** `scripts/install/install_albert_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `dpkg`, `sudo`; el script instala
  `wget`, `gnupg` y `ca-certificates` si faltan

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

- Debian con `apt-get`, `dpkg` y `Debian_Unstable` disponible en el
  repositorio OBS (esta implementación está fijada a esa carpeta, la
  correspondiente a Debian sid/testing).
- `sudo` configurado para el usuario actual.
- Conectividad HTTPS a `download.opensuse.org`.
- Ejecutar como usuario normal, no como root.

El script utiliza el repositorio OBS oficial de Albert:
<https://albertlauncher.github.io/installation/linux/>.

## Uso

Diagnosticar sin modificar nada:

```sh
just install-albert --check
```

Revisar el plan:

```sh
just install-albert --plan
```

Configurar el repositorio e instalar Albert:

```sh
just install-albert --apply
```

Instalar y además agregar un atajo de prueba en i3 (`$mod+a`), sin tocar
`$mod+space`:

```sh
just install-albert --apply --i3-shortcut
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica repositorio, clave y paquete sin cambios |
| `--plan` | `--dry-run` | Muestra acciones previstas sin modificar el sistema |
| `--apply` | — | Configura el repositorio oficial e instala `albert` |
| `--i3-shortcut` | — | Junto con `--apply`, agrega `bindsym $mod+a` en i3 |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza variables de entorno para repositorios, claves ni
contraseñas. La contraseña de sudo se solicita únicamente mediante
`sudo -v`. `XDG_CONFIG_HOME` (si está definida) determina dónde se busca
`i3/config` para `--i3-shortcut`.

## Ejemplos

### Forma explícita recomendada

```sh
just install-albert --apply
```

### Ejecución directa

```sh
bash scripts/install/install_albert_linux.sh --check
bash scripts/install/install_albert_linux.sh --plan
bash scripts/install/install_albert_linux.sh --apply
```

### Con atajo de prueba en i3

```sh
just install-albert --apply --i3-shortcut
# luego, dentro de i3:
#   $mod+Shift+r   (recargar config)
#   $mod+a         (abrir Albert)
```

## Protecciones de seguridad

- Usa exclusivamente
  `https://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_Unstable/`
  como origen APT.
- Descarga la clave oficial por HTTPS y verifica su SHA256 antes de
  instalarla: `e76f1190c7bed3dffa2b2a11d1822dd5721c1d1ebb32ce9cc23f55590d161d5c`.
- Comprueba además la huella PGP oficial:
  `A4B83CD05FDF5C5178482D4A1488EB46E192A257`.
- Usa `signed-by` para limitar la clave al repositorio de Albert.
- Respaldará la clave y la fuente anterior en
  `/var/backups/rafex-albert/` antes de reemplazarlas.
- El atajo de i3 se parcha con un bloque `# BEGIN rafex albert`/
  `# END rafex albert` idempotente (nunca duplica ni toca el resto del
  archivo), y respalda `~/.config/i3/config` como `config.bak.<fecha>`
  antes de modificarlo — reconocible por
  [find_safety_backups_unix.sh](../dev/find_safety_backups_unix.md).
- No modifica `$mod+space` (rofi) ni ningún otro binding existente.
- No acepta, almacena ni transmite contraseñas ni tokens.

## Fallos conocidos

### `no se pudo descargar la clave`

**Causa:** falta de conectividad HTTPS, DNS, proxy o `wget`.

**Solución:** verifica
`curl -I https://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_Unstable/Release.key`
y repite el modo `--apply` cuando exista conectividad.

### `checksum SHA256 inesperado para la clave`

**Causa:** la descarga no coincide con la clave oficial esperada o la
clave publicada en OBS cambió.

**Solución:** no continúes manualmente. Revisa
<https://albertlauncher.github.io/installation/linux/> y actualiza el
checksum del script mediante una revisión explícita.

### `no se encontró ~/.config/i3/config; omitiendo atajo de prueba`

**Causa:** se usó `--i3-shortcut` antes de desplegar el perfil de
dotfiles (i3 aún no tiene configuración propia).

**Solución:** despliega primero el perfil (`just install-profile
thinkpad-x1-yoga-1st` o equivalente) y vuelve a correr `--apply
--i3-shortcut`.

### `sudo apt-get install -y albert` falla con dependencias incumplidas (`libstdc++6 (>= 16.2.0-2) pero 16.2.0-1 va a ser instalado`)

**Causa (observada en vivo el 2026-09-06 en la ThinkPad):** el build de
Albert publicado en OBS para `Debian_Unstable` está compilado contra una
instantánea de Debian sid ligeramente más nueva que la que reflejan los
espejos de APT en ese momento (`libstdc++6` y varias libs de Qt6 aún no
alcanzaban la versión exigida). El repositorio y la clave sí quedan
configurados correctamente (`--check` los reporta `ok`); es únicamente el
paso `apt-get install` el que falla, y `set -e` aborta el script ahí
mismo — antes de llegar a `configure_i3_shortcut()`, así que tampoco
queda el atajo `$mod+a` en i3.

**Solución:** no es un bug de este script ni algo que debas forzar
(evita `--allow-downgrades`/pinning manual). Es un desfase temporal de
paquetes en Debian sid; repite `sudo apt-get update && sudo apt-get
install -y albert` en unos días, cuando sid absorba esas versiones más
nuevas. Puedes ver el detalle exacto de qué dependencia falta con:

```sh
apt-get install -s albert
```

Si no quieres esperar,
[install_albert_upstream_linux.sh](install_albert_upstream_linux.md)
compila la misma versión desde fuente en `~/.local`, enlazada contra las
bibliotecas que ya tienes instaladas — evita este desfase por completo,
a cambio de una compilación más pesada.

## Changelog

### [Unreleased]

- **feat:** instalador Debian idempotente para Albert desde el
  repositorio OBS oficial, con atajo de prueba opcional en i3.
