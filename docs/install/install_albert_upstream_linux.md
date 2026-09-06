---
title: install_albert_upstream_linux.sh
description: Compila Albert v35.1.0 upstream en el espacio del usuario cuando el paquete OBS tiene dependencias incumplidas.
tags:
  - instalación
  - albert
  - i3
---

# install_albert_upstream_linux.sh

Compila la etiqueta oficial `v35.1.0` de Albert y coloca el resultado bajo
`~/.local` (binario, librería, plugins y recursos), sin tocar el paquete de
APT que gestiona [install_albert_linux.sh](install_albert_linux.md) ni
iniciar Albert automáticamente.

Alternativa a `install_albert_linux.sh` cuando el paquete publicado en el
repositorio OBS oficial tiene dependencias que Debian sid todavía no
satisface (ver [Fallos conocidos](#fallos-conocidos) del otro script):
compilar aquí mismo enlaza el binario contra las bibliotecas que
realmente están instaladas en esta máquina, evitando ese desfase de
versiones por completo.

- **Ruta:** `scripts/install/install_albert_upstream_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, git, CMake, Ninja/Make, un compilador C++,
  dependencias de desarrollo de Qt6, y `sudo` únicamente para instalar
  esas dependencias vía APT.

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

El instalador está pensado para Debian. Requiere conexión para clonar el
código oficial de Albert (y sus ~30 submódulos: `i18n`, `lib/QHotkey`,
`lib/QNotification` y cada `plugins/<nombre>`) durante `--apply`, y
espacio para las fuentes y la compilación bajo
`~/.local/share/rafex/albert/`.

La compilación fija la etiqueta oficial `v35.1.0` y comprueba que el
commit obtenido coincide exactamente con
`21d0b78dafc53d3ea9aebd139b26bf1ae8ea115b`. El resultado se instala
completo (binario, `libalbert`, plugins y recursos) bajo `~/.local` vía
`cmake --install`, así que no requiere `sudo` para el paso de
instalación en sí — solo para las dependencias de compilación que falten.

Las dependencias de compilación son las mismas que usa el Dockerfile
oficial de CI (`.docker/ubuntu.Dockerfile` en `albertlauncher/albert`),
con dos ajustes de nombre verificados en vivo contra Debian sid: el
paquete se llama `qt6-svg-dev` (no `libqt6svg6-dev`), y no hace falta
`libqt6opengl6-dev` porque en Debian esos encabezados ya vienen
provistos por `qt6-base-dev`.

## Uso

```bash
just install-albert-upstream --check
just install-albert-upstream --plan
just install-albert-upstream --apply
just install-albert-upstream --status
```

Instalar y además agregar un atajo de prueba en i3 (`$mod+a`), sin tocar
`$mod+space`:

```bash
just install-albert-upstream --apply --i3-shortcut
```

El atajo usa las mismas marcas `# BEGIN rafex albert`/`# END rafex
albert` que `install_albert_linux.sh`, así que cualquiera de los dos
instaladores (OBS o esta compilación) administra el mismo bloque sin
duplicarlo — el último que corras con `--i3-shortcut` es el que queda
apuntando al binario que instaló.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, dependencias y rutas sin modificar (default). |
| `--plan` | — | Muestra origen, commit, rutas y paquetes faltantes sin escribir. |
| `--apply` | — | Instala dependencias faltantes, clona/actualiza las fuentes, compila e instala en `~/.local`. |
| `--status` | — | Muestra versión, commit local e i3 sin modificar. |
| `--i3-shortcut` | — | Junto con `--apply`, agrega `bindsym $mod+a` en i3. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_DATA_HOME` | Cambia dónde viven las fuentes y la compilación; por defecto `~/.local/share`. |
| `XDG_CONFIG_HOME` | Determina dónde se busca `i3/config` para `--i3-shortcut`; por defecto `~/.config`. |

No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

### Forma recomendada: inspeccionar antes de compilar

```bash
just install-albert-upstream --check
just install-albert-upstream --plan
just install-albert-upstream --apply
```

### Con atajo de prueba en i3

```bash
just install-albert-upstream --apply --i3-shortcut
# luego, dentro de i3:
#   $mod+Shift+r   (recargar config)
#   $mod+a         (abrir Albert)
```

### Comprobación posterior

```bash
just install-albert-upstream --status
~/.local/bin/albert --version
```

## Protecciones de seguridad

- Solo `--apply` modifica el equipo.
- `sudo` se usa únicamente para `apt-get update`/`apt-get install` de
  dependencias de compilación faltantes; la compilación y la instalación
  en sí corren como usuario normal, sin `sudo`.
- El script rechaza ejecutarse como root.
- El origen Git debe ser exactamente
  `https://github.com/albertlauncher/albert.git`, las fuentes deben
  estar limpias (`git status --porcelain`, ignorando submódulos) y la
  etiqueta `v35.1.0` debe resolver exactamente al commit
  `21d0b78dafc53d3ea9aebd139b26bf1ae8ea115b` antes de compilar.
- Instala exclusivamente bajo `~/.local` (vía `CMAKE_INSTALL_PREFIX`);
  nunca toca `/usr`, el paquete de APT que gestiona
  `install_albert_linux.sh`, ni ningún archivo fuera de ese árbol.
- El atajo de i3 se parcha con un bloque `# BEGIN rafex albert`/
  `# END rafex albert` idempotente (nunca duplica ni toca el resto del
  archivo), y respalda `~/.config/i3/config` como `config.bak.<fecha>`
  antes de modificarlo — reconocible por
  [find_safety_backups_unix.sh](../dev/find_safety_backups_unix.md).
- No modifica `$mod+space` (rofi) ni ningún otro binding existente.
- No inicia Albert automáticamente.

## Fallos conocidos

### `la compilación no produjo build/bin/albert`

**Causa:** faltan dependencias de desarrollo, el checkout no corresponde
a `v35.1.0`, o CMake/Ninja terminaron con error (revisa la salida
completa de `cmake --build`, suele señalar qué plugin falló).

**Solución:** ejecuta `--check` para confirmar qué paquetes faltan, y
`--plan` para ver el commit y las rutas antes de reintentar. No inicies
el binario hasta que `--status` muestre `v35.1.0`.

### `commit inesperado para v35.1.0`

**Causa:** la etiqueta remota cambió, el checkout local fue alterado, o
el origen no es el repositorio oficial de `albertlauncher/albert`.

**Solución:** no fuerces la compilación. Conserva el árbol en
`~/.local/share/rafex/albert/` para inspección y revisa la etiqueta en
el repositorio oficial antes de actualizar el commit fijado en este
script.

### El paquete de APT y el binario compilado coexisten con resultados distintos

**Causa:** `install_albert_linux.sh` (OBS) y este script instalan en
rutas distintas (`/usr/bin/albert` vs `~/.local/bin/albert`); si algún
día ambos quedan instalados, `~/.local/bin` suele resolver primero en
`$PATH` — `--status` avisa de esta coexistencia.

**Solución:** no es un error; decide cuál prefieres con
`command -v albert` y ajusta `$PATH` u orden de instalación según
convenga. Ninguno de los dos scripts desinstala al otro.

## Changelog

### [Unreleased]

- **feat:** compilación reproducible de Albert v35.1.0 upstream en
  `~/.local`, con atajo de prueba opcional en i3 (mismo bloque que
  `install_albert_linux.sh`), como alternativa cuando el paquete OBS
  tiene dependencias incumplidas en Debian sid.
