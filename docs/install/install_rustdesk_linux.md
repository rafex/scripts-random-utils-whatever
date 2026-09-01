---
title: install_rustdesk_linux.sh
description: Instalación reproducible de RustDesk 1.4.9 desde el DEB oficial
tags:
  - instalación
  - escritorio remoto
  - Debian
---

# install_rustdesk_linux.sh

Descarga e instala RustDesk 1.4.9 para Debian amd64 desde la release oficial
de GitHub. Verifica el SHA-256 y los metadatos del DEB antes de pasarlo a APT.
Por seguridad, el servicio de acceso remoto queda detenido y deshabilitado por
defecto.

- **Ruta:** `scripts/install/install_rustdesk_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `dpkg`, `dpkg-deb`, `sha256sum`, `curl` o `wget`

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

- Debian amd64.
- `sudo` para `--apply`.
- Conexión HTTPS a GitHub para descargar el artefacto.
- La release fijada es RustDesk `1.4.9`; el script no acepta otra versión sin
  actualizar deliberadamente el nombre del artefacto y su checksum en el
  repositorio.

La release oficial publica el artefacto
`rustdesk-1.4.9-x86_64.deb` y el digest SHA-256 usado por este script:

```text
7244ba47c40e804172044bfbe659467c54ce46554c98e78c8c0406f1d612fda3
```

Fuente: [release 1.4.9 de RustDesk](https://github.com/rustdesk/rustdesk/releases/tag/1.4.9).

## Uso

Comprobar la arquitectura y el estado sin modificar la máquina:

```sh
just install-rustdesk --check
```

Revisar el plan:

```sh
just install-rustdesk --plan
```

Instalar RustDesk:

```sh
just install-rustdesk --apply
```

Consultar posteriormente el paquete y el servicio:

```sh
just install-rustdesk --status
```

La aplicación se puede abrir como usuario normal:

```sh
rustdesk
```

El paquete oficial puede crear e iniciar `rustdesk.service` durante su
instalación. El instalador corrige inmediatamente ese estado y deja el
servicio detenido y deshabilitado por defecto en cada ejecución de `--apply`.
Para usar acceso desatendido, hay que solicitarlo de manera explícita:

```sh
just install-rustdesk --apply --enable-service
```

El instalador no configura una contraseña de acceso remoto. Revisa cualquier
permiso desde RustDesk antes de usarlo en redes públicas.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, arquitectura, herramientas y estado local |
| `--plan` | `--dry-run` | Muestra la descarga, el checksum y la instalación prevista |
| `--apply` | — | Solicita sudo, descarga, verifica e instala el DEB |
| `--status` | — | Muestra versión, binario y estado del servicio sin modificar |
| `--version <versión>` | — | Acepta únicamente la versión fijada `1.4.9` |
| `--enable-service` | — | Deja `rustdesk.service` habilitado y activo durante `--apply`; sin esta opción se detiene y deshabilita |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso | Prioridad |
|---|---|---|
| `PATH` | Localiza `curl`, `wget`, `dpkg` y `sudo` | Entorno de la shell |
| `HOME` | No se usa para guardar configuración del instalador | No aplica |

No se aceptan contraseñas, tokens ni credenciales mediante variables de
entorno, archivos `.env` o argumentos.

## Ejemplos

### Forma explícita recomendada

```sh
just install-rustdesk --apply
```

### Diagnóstico antes de instalar

```sh
just install-rustdesk --check
just install-rustdesk --plan
```

### Ejecución directa

```sh
bash scripts/install/install_rustdesk_linux.sh --status
bash scripts/install/install_rustdesk_linux.sh --apply
```

### Comprobación posterior

```sh
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' rustdesk
rustdesk --version
systemctl is-enabled rustdesk.service
```

## Protecciones de seguridad

- Solo acepta Debian amd64 y la release fijada `1.4.9`.
- Usa exclusivamente la URL HTTPS oficial de GitHub de RustDesk.
- Verifica SHA-256 antes de leer los metadatos o instalar el DEB.
- Verifica `Package=rustdesk`, `Version=1.4.9` y `Architecture=amd64`.
- Instala el archivo local mediante APT para resolver dependencias de Debian.
- No añade repositorios externos ni importa claves APT.
- Detiene y deshabilita `rustdesk.service` durante `--apply`, salvo que se use
  `--enable-service` explícitamente.
- Si hay una versión más nueva instalada, no la reemplaza por una versión
  anterior fijada.
- `--check`, `--plan` y `--status` no escriben archivos ni solicitan sudo.
- No recoge ni imprime contraseñas, tokens, identificadores de sesión ni
  configuración de acceso remoto.
- RustDesk es software de acceso remoto: úsalo solo con consentimiento y
  autorización sobre los equipos administrados.

## Fallos conocidos

### `esta release solo está preparada para Debian amd64`

**Causa:** la release seleccionada publica un DEB para x86_64 y no corresponde
con la arquitectura del sistema.

**Solución:** utiliza una build oficial compatible con la arquitectura y
actualiza el instalador con un checksum verificado antes de añadir soporte.

### `SHA-256 inesperado`

**Causa:** la descarga está incompleta, el archivo cambió o la URL no entregó
el artefacto esperado.

**Solución:** no fuerces la instalación. Comprueba la conectividad y la release
oficial; el script no entrega el archivo a APT hasta que el hash coincide.

### `no se encontró curl ni wget`

**Causa:** falta una herramienta de descarga.

**Solución:** durante `--apply` el instalador intenta instalar `curl` y
`ca-certificates` desde Debian. Si APT no tiene candidato, corrige las fuentes
oficiales y repite.

### `se conserva la versión más nueva ya instalada`

**Causa:** el equipo tiene una versión superior a `1.4.9`.

**Solución:** se conserva la versión superior para evitar un downgrade. Cambia
la versión fijada y el checksum en una modificación revisada del repositorio si
necesitas administrar una release posterior.

### `El servicio remoto no está disponible`

**Causa:** la instalación no habilita el servicio ni el acceso desatendido.

**Solución:** abre RustDesk como usuario normal y configura explícitamente el
flujo de acceso que necesites; revisa después `systemctl status rustdesk`.

## Changelog

### [Unreleased]

- **feat:** añadir instalador Debian de RustDesk 1.4.9 con SHA-256 fijado.
