---
title: install_ulauncher_linux.sh
description: Instalación reproducible de Ulauncher 5.16.1 desde el DEB oficial
tags:
  - instalación
  - i3
  - Debian
---

# install_ulauncher_linux.sh

Descarga e instala Ulauncher 5.16.1 (paquete arch-independiente `all`)
desde la release oficial de GitHub. Verifica tamaño, SHA-256 y los
metadatos del DEB antes de pasarlo a APT. Opcionalmente agrega un atajo
de prueba en i3 (`$mod+u`) sin modificar el binding existente de rofi
(`$mod+space`).

- **Ruta:** `scripts/install/install_ulauncher_linux.sh`
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

- Debian (el paquete es `Architecture: all`, no depende de la
  arquitectura del host).
- `sudo` para `--apply`.
- Conexión HTTPS a GitHub para descargar el artefacto.
- La release fijada es Ulauncher `5.16.1`; el script no acepta otra
  versión sin actualizar deliberadamente el nombre del artefacto y su
  checksum en el repositorio.

Ulauncher no está empaquetado en Debian ni tiene repositorio APT propio
para Debian: la release oficial publica el artefacto
`ulauncher_5.16.1_all.deb` y el digest SHA-256 usado por este script:

```text
7212d846c8519615e55f99790ac7f6267e5cc812f0da4b4a6d3afe89ddc12b9f
```

Fuente: [release 5.16.1 de Ulauncher](https://github.com/Ulauncher/Ulauncher/releases/tag/5.16.1).

## Uso

Comprobar el estado sin modificar la máquina:

```sh
just install-ulauncher --check
```

Revisar el plan:

```sh
just install-ulauncher --plan
```

Instalar Ulauncher:

```sh
just install-ulauncher --apply
```

Instalar y además agregar un atajo de prueba en i3 (`$mod+u`), sin tocar
`$mod+space`:

```sh
just install-ulauncher --apply --i3-shortcut
```

Consultar posteriormente la instalación:

```sh
just install-ulauncher --status
```

La aplicación se puede abrir como usuario normal (`ulauncher`) o, tras
`--i3-shortcut`, con `$mod+u` (usa `ulauncher-toggle`, el binario propio
de Ulauncher para alternar la ventana sin relanzar el proceso).

`ulauncher-toggle` necesita que el daemon `ulauncher.service` esté
corriendo (es quien realmente mantiene la ventana y responde por D-Bus);
`--apply` lo habilita y arranca (`systemctl --user enable --now
ulauncher.service`) para la sesión actual, y `--apply --i3-shortcut`
además agrega un `exec --no-startup-id systemctl --user start
ulauncher.service` en i3 para que siga arrancando en sesiones futuras —
ver [Fallos conocidos](#fallos-conocidos) para el porqué de este paso.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba herramientas y estado local sin cambios |
| `--plan` | `--dry-run` | Muestra la descarga, verificación e instalación previstas |
| `--apply` | — | Solicita sudo, descarga, verifica e instala el DEB |
| `--i3-shortcut` | — | Junto con `--apply`, agrega `bindsym $mod+u` en i3 |
| `--status` | — | Muestra versión y binario sin modificar |
| `--version <versión>` | — | Acepta únicamente la versión fijada `5.16.1` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso | Prioridad |
|---|---|---|
| `PATH` | Localiza `curl`, `wget`, `dpkg` y `sudo` | Entorno de la shell |
| `XDG_CONFIG_HOME` | Determina dónde se busca `i3/config` para `--i3-shortcut` | Entorno de la shell (default `$HOME/.config`) |

No se aceptan contraseñas, tokens ni credenciales mediante variables de
entorno, archivos `.env` o argumentos.

## Ejemplos

### Forma explícita recomendada

```sh
just install-ulauncher --apply
```

### Diagnóstico antes de instalar

```sh
just install-ulauncher --check
just install-ulauncher --plan
```

### Con atajo de prueba en i3

```sh
just install-ulauncher --apply --i3-shortcut
# luego, dentro de i3:
#   $mod+Shift+r   (recargar config)
#   $mod+u         (abrir/alternar Ulauncher)
```

### Comprobación posterior

```sh
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' ulauncher
ulauncher --version
```

## Protecciones de seguridad

- Solo acepta la release fijada `5.16.1` (asset `Architecture: all`).
- Usa exclusivamente la URL HTTPS oficial de GitHub de Ulauncher.
- Verifica tamaño exacto (1862092 bytes) y SHA-256 antes de leer los
  metadatos o instalar el DEB.
- Verifica `Package=ulauncher`, `Version=5.16.1` y `Architecture=all`.
- Instala el archivo local mediante APT para resolver dependencias de
  Debian.
- No añade repositorios externos ni importa claves APT.
- Si hay una versión más nueva instalada, no la reemplaza por una
  versión anterior fijada.
- El atajo de i3 se parcha con un bloque `# BEGIN rafex ulauncher`/
  `# END rafex ulauncher` idempotente (nunca duplica ni toca el resto
  del archivo), y respalda `~/.config/i3/config` como `config.bak.<fecha>`
  antes de modificarlo — reconocible por
  [find_safety_backups_unix.sh](../dev/find_safety_backups_unix.md).
- No modifica `$mod+space` (rofi) ni ningún otro binding existente.
- `--apply` habilita y arranca `ulauncher.service` (`systemctl --user
  enable --now`); nunca deshabilita ni detiene servicios existentes.
- `--check`/`--plan`/`--status` no escriben archivos ni solicitan sudo;
  `--check` sí consulta `systemctl --user is-active` (solo lectura) para
  diagnosticar si el daemon está corriendo.

## Fallos conocidos

### `tamaño inesperado`

**Causa:** la descarga está incompleta o interrumpida.

**Solución:** repite `--apply`; el script no entrega el archivo a APT
hasta que el tamaño coincide con el esperado (1862092 bytes).

### `SHA-256 inesperado`

**Causa:** la descarga está incompleta, el archivo cambió o la URL no
entregó el artefacto esperado.

**Solución:** no fuerces la instalación. Comprueba la conectividad y la
release oficial; el script no entrega el archivo a APT hasta que el
hash coincide.

### `no se encontró curl ni wget`

**Causa:** falta una herramienta de descarga.

**Solución:** durante `--apply` el instalador intenta instalar `curl` y
`ca-certificates` desde Debian. Si APT no tiene candidato, corrige las
fuentes oficiales y repite.

### `se conserva la versión más nueva ya instalada`

**Causa:** el equipo tiene una versión superior a `5.16.1`.

**Solución:** se conserva la versión superior para evitar un downgrade.
Cambia la versión fijada y el checksum en una modificación revisada del
repositorio si necesitas administrar una release posterior.

### `no se encontró ~/.config/i3/config; omitiendo atajo de prueba`

**Causa:** se usó `--i3-shortcut` antes de desplegar el perfil de
dotfiles (i3 aún no tiene configuración propia).

**Solución:** despliega primero el perfil (`just install-profile
thinkpad-x1-yoga-1st` o equivalente) y vuelve a correr `--apply
--i3-shortcut`.

### `$mod+u` no hace nada / `ulauncher-toggle` falla con `org.freedesktop.DBus.Error.ServiceUnknown: The name net.launchpad.ulauncher was not provided by any .service files`

**Causa (corregida, observada en vivo el 2026-09-06):** el paquete de
Ulauncher trae `ulauncher.service` con `WantedBy=graphical-session.target`,
pero en una sesión i3 sin systemd-logind/GNOME de por medio ese target
nunca se activa solo — así que el daemon nunca arrancaba, y
`ulauncher-toggle` no tenía nada que alternar. Versiones anteriores de
este script instalaban el paquete y el atajo de i3, pero nunca tocaban el
servicio, así que el atajo quedaba configurado y silenciosamente inútil.

**Solución:** vuelve a correr `--apply --i3-shortcut` con esta versión
del script: habilita y arranca `ulauncher.service` para la sesión actual,
y agrega un `exec --no-startup-id systemctl --user start
ulauncher.service` en i3 para sesiones futuras. Si el servicio sigue sin
levantar, revisa `systemctl --user status ulauncher.service` y
`journalctl --user -u ulauncher.service`.

## Changelog

### [Unreleased]

- **feat:** instalador Debian idempotente para Ulauncher 5.16.1 desde el
  DEB oficial de GitHub, con atajo de prueba opcional en i3.
- **fix:** `--apply` ahora habilita y arranca `ulauncher.service`
  (`systemctl --user enable --now`), y `--i3-shortcut` agrega un `exec`
  de autostart del servicio en i3 — antes el paquete y el atajo se
  instalaban pero el daemon nunca arrancaba (`WantedBy=graphical-session.target`
  nunca se activa en una sesión i3 sin systemd-logind/GNOME), así que
  `ulauncher-toggle` fallaba en silencio con
  `org.freedesktop.DBus.Error.ServiceUnknown`.
