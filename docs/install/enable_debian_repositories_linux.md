# enable_debian_repositories_linux.sh

Habilita los componentes oficiales de Debian `main`, `contrib`, `non-free` y
`non-free-firmware` en archivos de fuentes tradicionales y deb822.

- **Ruta:** `scripts/install/enable_debian_repositories_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `sudo`, `grep`, `awk`, `sed`, `find`

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

- Debian Linux con `apt-get`.
- `sudo` instalado y configurado para el usuario actual.
- Conectividad a los mirrors oficiales de Debian.
- El script debe ejecutarse como usuario normal, no como root.

## Componentes habilitados

El script garantiza, en este orden, las cuatro componentes oficiales de Debian:
`main contrib non-free non-free-firmware`.

| Componente | Contenido |
|---|---|
| `main` | Paquetes que cumplen las Directrices de Software Libre de Debian (DFSG). |
| `contrib` | Paquetes libres que dependen de paquetes fuera de la DFSG. |
| `non-free` | Paquetes que no cumplen la DFSG. |
| `non-free-firmware` | Firmware que no cumple la DFSG y se distribuye separadamente. |

Referencias oficiales: [Debian SourcesList](https://wiki.debian.org/SourcesList) y
[sources.list(5)](https://manpages.debian.org/unstable/apt/sources.list.5.en.html).

## Uso

Diagnostica primero:

```sh
just enable-debian-repositories --check
```

Revisa el cambio sin aplicarlo:

```sh
just enable-debian-repositories --plan
```

Aplica los componentes y actualiza los índices APT:

```sh
just enable-debian-repositories --apply
```

El script modifica solamente los archivos activos de `/etc/apt/sources.list`
y `/etc/apt/sources.list.d/`. Si no encuentra ninguna fuente activa, crea
`/etc/apt/sources.list.d/90-debian-all-components.list` usando la versión
Debian detectada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica componentes sin modificar nada |
| `--plan` | — | Muestra cambios previstos sin modificar nada |
| `--dry-run` | — | Alias de `--plan` |
| `--apply` | — | Habilita componentes y ejecuta `apt-get update` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza archivo `.env` ni variables de entorno para seleccionar
repositorios. Detecta `VERSION_CODENAME` desde `/etc/os-release` únicamente
cuando necesita crear fuentes de fallback.

## Ejemplos

### Forma explícita recomendada

```sh
just enable-debian-repositories --apply
```

### Forma directa

```sh
bash scripts/install/enable_debian_repositories_linux.sh --check
bash scripts/install/enable_debian_repositories_linux.sh --plan
bash scripts/install/enable_debian_repositories_linux.sh --apply
```

### Después de habilitar repositorios

```sh
apt-cache policy intel-media-va-driver-non-free
apt-cache policy firmware-intel-graphics
```

## Protecciones de seguridad

- Solicita sudo solamente mediante `sudo -v`.
- Nunca acepta ni almacena contraseñas.
- Crea respaldos fechados antes de modificar cada archivo en
  `/var/backups/rafex-debian-sources/`, fuera del directorio que APT escanea.
- Es idempotente y no duplica componentes.
- Respaldará y retirará el archivo legado `90-laptop-nonfree.list` si otra
  fuente Debian ya contiene las cuatro componentes.
- Reubica respaldos antiguos de `90-laptop-nonfree.list` que hayan quedado en
  `/etc/apt/sources.list.d/`.
- Conserva mirrors, suites, opciones y entradas existentes.
- Solo añade los cuatro componentes oficiales de Debian.
- No activa `backports`, `experimental`, `sid`, PPAs ni repositorios de
  terceros.
- Ejecuta `apt-get update` solo cuando hubo cambios en las fuentes.

## Fallos conocidos

### `sudo no está instalado`

**Causa:** Debian fue instalado sin `sudo`.

**Solución:** ejecuta primero
`configure_sudo_linux.sh --user rafex --apply` como root mediante `su -`.

### `No se encontraron entradas Debian activas`

**Causa:** las fuentes están ausentes, deshabilitadas o usan una extensión no
  compatible.

**Solución:** usa `--plan`; si no hay fuentes activas, el script propondrá
  crear un archivo oficial de fallback para la versión detectada.

### `apt-get update` falla después del cambio

**Causa:** mirror inaccesible, suite inválida, proxy o reloj del sistema
  incorrecto.

**Solución:** revisa el respaldo `.bak.YYYYMMDD_HHMMSS`, corrige conectividad
  o firma de repositorios y repite `sudo apt-get update`.

## Changelog

### [Unreleased]

- **feat:** habilitación idempotente de componentes Debian en formatos `.list`
  y `.sources`.
- **fix:** comprobar y agregar explícitamente también `main`.
