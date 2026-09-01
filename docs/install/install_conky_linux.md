---
title: install_conky_linux.sh
description: Instala Conky y un panel lateral seguro para i3 y Openbox en la ThinkPad.
tags:
  - instalación
  - conky
  - thinkpad
---

# install_conky_linux.sh

Instala `conky-all` desde Debian y configura un panel informativo en el lateral
izquierdo, debajo de i3bar o tint2, con el alto útil de la pantalla. El panel
usa una ventana X11 de tipo `override`, transparente y sin reglas de ventana
flotante, con un ancho fijo de 320 píxeles. No es gestionada por i3/Openbox ni
puede reservar una columna o desplazar ventanas. Las ventanas normales la cubren
completamente. Solo se ve cuando el escritorio queda libre. La plantilla usa `alignment = 'top_left'`, un margen
superior de 34 píxeles y una altura base de 1030 píxeles, ajustada a la
pantalla 1920×1080 de este perfil.

- **Ruta:** `scripts/install/install_conky_linux.sh`
- **SO requerido:** Linux (Debian o derivada)
- **Dependencias:** `bash`, `sudo`, `apt-get`, `apt-cache`, `dpkg-query`, `i3` opcional, `conky-all`

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

Se recomienda haber instalado el perfil `thinkpad-x1-yoga-1st`. La instalación
de paquetes requiere `sudo`; la configuración de usuario y el arranque normal
de Conky no requieren privilegios elevados.

## Uso

```bash
just install-conky --check
just install-conky --plan
just install-conky --apply
just install-conky --status
just conky-status
```

El instalador copia la plantilla a `~/.config/conky/conky.conf`, el helper a
`~/.local/bin/conky-status.sh` y el lanzador a
`~/.local/bin/conky-launch.sh`. La instancia se inicia al entrar en i3 u
Openbox.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Verifica Debian, el candidato APT, las plantillas y el estado sin escribir. |
| `--plan` | `--dry-run` | Muestra la instalación e integración previstas sin escribir. |
| `--apply` | — | Instala `conky-all` si falta, copia la configuración y añade los bloques administrados. |
| `--status` | — | Muestra archivos, bloques, número de instancias y presencia de `DISPLAY`. |
| `--help` | `-h` | Muestra la ayuda. |

El helper admite `--section network`, `--section power`, `--section temperature`,
`--section audio`, `--section lab` y `--section security`; consulta su
documentación para el detalle.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Base de la configuración de Conky, i3 y Openbox. |
| `CONKY_CONFIG` | `~/.config/conky/conky.conf` | Ruta de configuración usada por el lanzador. |
| `XDG_RUNTIME_DIR` | `~/.cache` | Directorio base del PID privado del lanzador. |

No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

### Instalación recomendada

```bash
just install-conky --check
just install-conky --plan
just install-conky --apply
```

### Diagnóstico sin sesión gráfica

```bash
just install-conky --status
just conky-status --check
```

Es normal que `DISPLAY=ausente` aparezca por SSH; el diagnóstico no intenta
abrir una ventana en ese caso.

### Recargar después de cambiar el tema

```bash
~/.local/bin/theme-toggle.sh --set nord
~/.local/bin/conky-launch.sh --reload
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura y no usan `sudo`.
- `--apply` usa `sudo` solo para instalar `conky-all` mediante APT.
- Se respaldan los archivos de usuario existentes antes de reemplazarlos.
- Los bloques de autoinicio de i3 y Openbox se reemplazan por sus marcadores, sin duplicarse.
- Conky usa `own_window_type = 'override'`; no se añade una regla `floating` en i3
  ni una regla de capa en Openbox, porque override no es gestionado por el WM.
- `override` no aparece en la lista de clientes de i3 y las ventanas normales lo
  cubren; la transparencia del fondo requiere ARGB/composición X11.
- El lanzador solo detiene su propio PID; nunca mata instancias ajenas.
- El panel no muestra SSID, IP, IMEI, IMSI, APN, nombres de archivos,
  credenciales, puertos ni comandos completos.
- No modifica i3bar, i3status, tint2, Xorg, NetworkManager, WWAN ni Picom.

## Fallos conocidos

### `conky-all no tiene candidato APT` aunque `apt search conky` lo encuentre

**Causa:** en una sesión en español, `apt-cache policy` puede mostrar
`Candidato:`. El instalador fuerza `LC_ALL=C` para interpretar de forma
estable la salida y comprobar el candidato real sin depender del idioma.

**Solución:** actualiza el repositorio y repite `just install-conky --apply`.

### `conky-all no tiene candidato APT`

**Causa:** las fuentes Debian no están disponibles o no se actualizaron.

**Solución:** revisa las fuentes APT y vuelve a ejecutar `apt-get update`; no
se añade ningún repositorio externo.

### `Conky no se inicia: no existe DISPLAY.`

**Causa:** el comando se ejecutó por SSH o fuera de la sesión X11.

**Solución:** inicia Conky desde i3/Openbox o ejecuta el lanzador dentro de la
sesión gráfica local.

### `El panel ocupa toda la pantalla o el texto no contrasta`

**Causa:** una configuración anterior podía usar una ventana `dock` de tamaño
completo o una ventana flotante. El panel actual es deliberadamente transparente
y depende de los colores del tema para conservar la legibilidad sobre el fondo de
pantalla.

**Solución:** ejecuta `just install-conky --apply` y recarga la instancia
administrada. La plantilla usa `DejaVu Sans Mono` tamaño 11, una ventana
`override` de 320 píxeles de ancho y `own_window_colour = '#00000000'` para
eliminar el fondo del panel. Los colores de texto los define el tema.

### `El panel aparece delante de las ventanas en i3`

**Causa:** una regla `floating enable` convierte Conky en una ventana flotante;
i3 mantiene las ventanas flotantes por encima de las ventanas en mosaico.

**Solución:** ejecuta `just install-conky --apply` y después
`~/.local/bin/conky-launch.sh --reload` desde la sesión gráfica. El instalador
migra la configuración administrada a `own_window_type = 'override'` y elimina
las reglas administradas de ventana flotante de i3/Openbox. También elimina
`maximum_height` y `border_color` no soportados por Conky 1.24.2, y conserva como
máximo una instancia administrada. El panel solo queda visible sobre el
escritorio vacío y las ventanas normales lo cubren.

### `Conky no se ve después de cambiar el wallpaper`

**Causa:** los gestores de iconos de escritorio pueden pintar una ventana por
encima de una ventana `override` y ocultar Conky incluso sobre el escritorio.

**Solución:** inicia o recarga Conky después de aplicar el fondo con
`~/.local/bin/conky-launch.sh --reload`. Si se usa otro gestor de escritorio,
debe configurarse para que no cubra el escritorio si se desea ver Conky.

### `existe otra instancia Conky del usuario`

**Causa:** hay otra instancia que no pertenece al PID administrado por Rafex.

**Solución:** el lanzador no la detiene. Revisa `pgrep -a conky` y decide
manualmente si esa instancia es necesaria.

## Changelog

### [Unreleased]

- `feat`: añade instalación e integración idempotente del panel Conky.
- `fix`: detecta candidatos APT correctamente en sesiones con localización
  distinta de inglés.
- `fix`: usa una ventana X11 `override` transparente, fuera del control de i3,
  y retira las reglas flotantes para que las ventanas normales cubran Conky.
