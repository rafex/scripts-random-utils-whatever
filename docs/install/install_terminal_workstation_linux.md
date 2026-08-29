---
title: install_terminal_workstation_linux.sh
description: Preparación de estación de terminal y desarrollo
tags:
  - instalación
---

# install_terminal_workstation_linux.sh

Prepara una estación Debian para terminal, desarrollo, Neovim/LazyVim, runtimes
instalados manualmente e integrados en mise, OpenCode y contenedores rootless
con Podman.

- **Ruta:** `scripts/install/install_terminal_workstation_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `sudo`, `apt-get`; `curl` para herramientas upstream

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

- Debian con repositorios `main`, `contrib`, `non-free` y
  `non-free-firmware` habilitados.
- Usuario normal con `sudo` configurado. Si es una instalación nueva, ejecuta
  primero `configure_sudo_linux.sh` desde una consola root.
- Conexión a Internet para APT, instaladores oficiales, LazyVim, Boda y OpenCode.
- El script debe ejecutarse como `rafex`, nunca como `root`.

## Uso

Diagnóstico y plan sin cambios:

```sh
just install-terminal-workstation --check
just install-terminal-workstation --plan --stage terminal
```

Aplicación completa:

```sh
just install-terminal-workstation --apply --stage all
```

`all` instala las etapas recomendadas, incluyendo Podman y los runtimes de
build. Maven, Gradle y GraalVM descargan runtimes grandes; puedes ejecutarlos
por separado con la etapa `build-runtimes` si prefieres controlar ese paso.

Después de aplicar, cierra y abre Alacritty. Debe conectarse a la sesión tmux
fija `thinkpad`, usando fuente DejaVu Sans Mono tamaño `7` para la pantalla
1920x1080 de la ThinkPad. También se instala `rxvt-unicode` como alternativa;
el lanzador `urxvt -e ~/.local/bin/start-thinkpad-tmux` usa la misma sesión.
Las conexiones SSH no se envuelven automáticamente en tmux.

La etapa `terminal` instala TPM en `~/.tmux/plugins/tpm` y declara los plugins
del perfil developer. Si una descarga falla, la configuración sigue siendo
usable y tmux muestra los plugins pendientes; dentro de una sesión ejecuta
`Ctrl-b I` para instalarlos o actualizarlos.

Los runtimes Java, Node.js, Maven y Gradle se descargan únicamente mediante sus
instaladores propios. `mise` solo crea enlaces, selecciona versiones y genera
shims; no debe ejecutarse `mise install`. El manifiesto
`~/.local/share/rafex-runtimes/registry.tsv` distingue instalaciones propias de
legacy.

También instala `~/.local/bin/reload-bash` y la función `reload-bash` en
`~/.bashrc`, para recargar la configuración de la shell después de cambiar
Java, mise o aliases. La activación de mise se ejecuta al final y llama a
`mise hook-env`. El selector `runtime-use` mantiene `JAVA_HOME` en
`~/.local/share/java-runtimes/current-java`, cuyo destino sigue la versión Java
activa.

También instala `ll` como función Bash. Con `eza` muestra permisos, tamaño
legible, fecha ISO, información Git, encabezado y directorios primero; si
`eza` no está disponible usa `ls` con colores y agrupación de directorios.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica sin modificar nada |
| `--plan` | `--dry-run` | Muestra las acciones previstas |
| `--apply` | — | Instala paquetes y escribe configuración |
| `--stage <etapa>` | — | `terminal`, `terminal-config`, `editor`, `runtimes`, `build-runtimes`, `containers`, `opencode` o `all` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `BODA_VERSION` | `0.2616.0` | Versión de Boda instalada mediante Cargo |
| `HOME` | entorno | Directorio del usuario; no debe apuntar a una ruta compartida |

No se aceptan contraseñas ni tokens mediante variables de entorno.

## Ejemplos

### Forma explícita recomendada

```sh
just install-terminal-workstation --apply --stage all
```

### Solo terminal y tmux

```sh
just install-terminal-workstation --apply --stage terminal

# Actualizar aliases y configuraciones de usuario sin repetir APT
just install-terminal-workstation --apply --stage terminal-config
```

### Editor y runtimes

```sh
just install-terminal-workstation --apply --stage editor
just install-terminal-workstation --apply --stage runtimes
```

### Podman rootless

```sh
just install-terminal-workstation --apply --stage containers
podman run --rm docker.io/library/alpine:latest uname -a
```

### Runtimes adicionales

```sh
just install-terminal-workstation --apply --stage build-runtimes
just reconcile-runtimes --check
runtime-use --list java
```

## Protecciones de seguridad

- `--check`, `--plan` y `--dry-run` no modifican el sistema.
- La contraseña de sudo solo se solicita mediante `sudo -v`.
- No se almacenan contraseñas, API keys ni credenciales.
- Las configuraciones existentes reciben respaldos fechados antes de cambiarse.
- Los bloques administrados son idempotentes y no se duplican.
- LazyVim respalda `~/.config/nvim`, datos, estado y caché antes de instalarse.
- mise, Boda y OpenCode se instalan en el espacio del usuario.
- Podman se instala sin activar un daemon privilegiado.
- No se modifican particiones, `fstab`, GRUB ni opciones de montaje.

## Fallos conocidos

### `Alacritty ya tiene [terminal.shell]`

**Causa:** agregar otra tabla TOML produciría una configuración inválida.

**Solución:** conserva la tabla existente y configura manualmente el programa
`$HOME/.local/bin/start-thinkpad-tmux`, o elimina la tabla después de guardar un
respaldo y vuelve a ejecutar el instalador.

### `LazyVim no se instaló porque ~/.config/nvim todavía existe`

**Causa:** otro proceso creó la ruta después del respaldo o el directorio es un
enlace simbólico.

**Solución:** revisa el respaldo `.bak.YYYYMMDD_HHMMSS`, mueve manualmente la
configuración anterior y vuelve a ejecutar la etapa `editor`.

### `mise`, `boda` u `opencode` no aparecen en el PATH

**Causa:** la shell actual todavía no cargó el bloque administrado de `.bashrc`.

**Solución:** abre una nueva shell o ejecuta `source ~/.bashrc`; verifica que
`~/.local/bin` y `~/.cargo/bin` estén en `PATH`.

### `Podman rootless` no puede crear un contenedor

**Causa:** faltan rangos `subuid/subgid`, configuración del usuario o soporte de
la sesión para namespaces rootless.

**Solución:** revisa `podman info`, `/etc/subuid`, `/etc/subgid` y la salida de
`loginctl`; no ejecutes Podman con sudo como solución permanente.

### `Los plugins TPM aparecen como pendientes`

**Causa:** TPM necesita acceso a GitHub y los plugins son instalaciones locales
separadas del paquete `tmux`.

**Solución:** comprueba la conexión y ejecuta `Ctrl-b I` dentro de tmux. La
configuración no descarga plugins mediante `sudo`.

### `tmux-256color no está disponible`

**Causa:** el terminal remoto o el sistema no tiene la entrada terminfo.

**Solución:** conserva `TERM=xterm-256color` en Alacritty, instala
`kitty-terminfo` y utiliza `infocmp tmux-256color` para diagnosticar. Para rxvt,
comprueba `infocmp rxvt-unicode-256color`; el paquete `rxvt-unicode` proporciona
esa entrada en Debian.

## Changelog

### [Unreleased]

- **feat:** instalador idempotente de terminal, LazyVim, mise, OpenCode y
  Podman rootless para ThinkPad Debian.
- **fix:** ajustar Alacritty a tamaño de fuente 7 y evitar que el instalador
  lo restaure a 9 o 10.
- **feat:** instalar el selector `runtime-use` junto con la etapa de runtimes.
