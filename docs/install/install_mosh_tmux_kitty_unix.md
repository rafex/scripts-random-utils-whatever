---
title: install_mosh_tmux_kitty_unix.sh
description: Instalación de Mosh, tmux y Kitty
tags:
  - instalación
---

# install_mosh_tmux_kitty_unix.sh

Instala Mosh y tmux en Debian, la definición terminfo de Kitty para el servidor
remoto, Mosh/tmux/Kitty en macOS y configura el portapapeles OSC 52 para copiar
desde tmux remoto hacia Kitty.

- **Ruta:** `scripts/install/install_mosh_tmux_kitty_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `ssh`; `sudo` en Debian; Homebrew en macOS

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

- Ejecutar el script como el usuario normal, no como root.
- En Debian, tener `sudo` configurado para el usuario. Si la ThinkPad aún no
  lo tiene, usa primero `configure_sudo_linux.sh` desde una consola root.
- En macOS, tener Homebrew instalado.
- Mosh necesita SSH para iniciar sesión y UDP para mantener la sesión. El
  servidor remoto debe tener `mosh-server` y el cliente local debe tener
  `mosh`.

## Uso

Ejecuta el script una vez en la ThinkPad y una vez en la MacBook:

```sh
just install-mosh-tmux-kitty --check
just install-mosh-tmux-kitty --plan
just install-mosh-tmux-kitty --apply
```

En Debian, `--apply` solicita la contraseña solamente mediante `sudo -v` e
instala `kitty-terminfo`, que proporciona la entrada `xterm-kitty` para el
servidor remoto.
En macOS, Homebrew gestiona la instalación de Mosh, tmux y Kitty.

Conecta desde Kitty en macOS:

```sh
mosh rafex@192.168.3.91 -- tmux new-session -A -s main
```

Dentro de tmux, usa `Ctrl-b [` para entrar al modo copia, selecciona con las
flechas o el mouse, pulsa `y` y luego pega normalmente con `Cmd-V` en Kitty.
El texto copiado desde la sesión remota llega al portapapeles local mediante
OSC 52; Mosh usa SSH para iniciar la sesión y UDP 60000–61000 para el canal
interactivo. [Mosh](https://mosh.org/), [portapapeles de tmux](https://github.com/tmux/tmux/wiki/Clipboard/6bbb34fb765e518506bdc90baec63c1b94651e42)

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica paquetes, configuración y firewall sin cambios |
| `--plan` | — | Muestra instalaciones y archivos previstos sin cambios |
| `--dry-run` | — | Alias de `--plan` |
| `--apply` | — | Instala paquetes y configura tmux/Kitty |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `TMUX_CONFIG` | `~/.tmux.conf` | Archivo de configuración de tmux |
| `KITTY_CONFIG_DIRECTORY` | `~/.config/kitty` | Directorio de configuración de Kitty en macOS |

Las opciones CLI no tienen prioridad sobre estas variables porque no existe
una opción CLI equivalente; las variables solo cambian las rutas de archivos.
No se aceptan contraseñas por variables de entorno.

## Ejemplos

### Forma explícita recomendada en la ThinkPad

```sh
just install-mosh-tmux-kitty --apply
```

### Forma explícita recomendada en macOS

```sh
just install-mosh-tmux-kitty --apply
mosh rafex@192.168.3.91 -- tmux new-session -A -s main
```

### Diagnóstico sin cambios

```sh
just install-mosh-tmux-kitty --check
```

### Ejecución directa sin Just

```sh
bash scripts/install/install_mosh_tmux_kitty_unix.sh --apply
```

## Protecciones de seguridad

- Nunca recibe ni almacena contraseñas.
- En Debian valida sudo con `sudo -v` antes de usar `apt-get`.
- Instala `kitty-terminfo` en Debian en lugar de copiar manualmente archivos
  terminfo desde macOS.
- Nunca ejecuta Mosh como root.
- Modifica solamente los archivos de configuración del usuario y crea
  respaldos fechados antes de agregar bloques.
- No sobreescribe un bloque administrado existente.
- Mantiene confirmación para lectura del portapapeles en Kitty mediante
  `read-clipboard-ask`.
- No abre reglas de firewall automáticamente; solo advierte si detecta UFW o
  nftables activos.

## Fallos conocidos

### `sudo no está instalado`

**Causa:** Debian fue instalado sin el paquete `sudo`.

**Solución:** ejecuta primero el bootstrap como root:

```sh
su -
bash /home/rafex/scripts-random-utils-whatever/scripts/install/configure_sudo_linux.sh \
  --user rafex --apply
```

### `Nothing received from the server on UDP port ...`

**Causa:** Mosh inició por SSH, pero un firewall bloquea el puerto UDP
seleccionado.

**Solución:** permite UDP `60000:61000` entre la Mac y la ThinkPad, o limita
Mosh a un rango más pequeño en tu firewall. El script no cambia el firewall
automáticamente.

### El texto no llega al portapapeles de macOS

**Causa:** Kitty/tmux no recargó la configuración o la selección no se copió
con la tecla `y` dentro del modo copia de tmux.

**Solución:** reinicia Kitty y tmux, comprueba `tmux show -g set-clipboard` y
repite `Ctrl-b [`, selección y `y`.

### `mosh` funciona pero no encuentra `tmux`

**Causa:** tmux no está instalado en la ThinkPad o no está en el `PATH` del
login iniciado por SSH.

**Solución:** ejecuta la etapa `--apply` en la ThinkPad y valida `command -v tmux` mediante SSH.

### `missing or unsuitable terminal: xterm-kitty`

**Causa:** la ThinkPad no tiene instalada la definición terminfo que Kitty
envía en la variable `TERM`.

**Solución:** actualiza el repositorio y ejecuta en la ThinkPad:

```sh
git pull --ff-only
just install-mosh-tmux-kitty --apply
infocmp -x xterm-kitty
tmux new -s thinkpad
```

Como solución temporal, puedes iniciar tmux con un terminal genérico:

```sh
TERM=xterm-256color tmux new -s thinkpad
```

## Changelog

### [Unreleased]

- **feat:** instalación multiplataforma de Mosh, tmux y Kitty con OSC 52.
- **fix:** instalar y verificar `kitty-terminfo` para sesiones remotas desde
  Kitty.
