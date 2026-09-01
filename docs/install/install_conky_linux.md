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
- [Incidente real y hallazgos](#incidente-real-y-hallazgos)
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

## Incidente real y hallazgos

Esta sección conserva el análisis de las iteraciones que terminaron en la
configuración actual. Su objetivo es evitar volver a introducir una solución
que visualmente parezca correcta en el escritorio vacío, pero que viole la
regla principal del perfil: Conky debe estar detrás de las ventanas y solo
verse cuando no haya una ventana normal encima.

### Errores de implementación que se deben evitar

1. **Usar `dock` o `panel` para Conky.** En i3 esas ventanas pueden participar
   en el cálculo del área útil o publicar reservas de espacio. El resultado
   observado fue una ventana de aproximadamente `1920x1040`, aplicaciones
   desplazadas y, en algunas recargas, estado `MAXIMIZED_VERT`. Conky no debe
   usarse como barra ni como panel reservador en este perfil.
2. **Añadir `floating enable` o intentar corregir la capa con el WM.** Una
   ventana flotante de i3 queda por encima de las ventanas en mosaico. Las
   reglas `for_window`, `wmctrl`, `no_focus` y similares no convierten una
   ventana flotante en un fondo fiable. La configuración actual no contiene
   reglas de ventana para Conky.
3. **Usar `own_window = false` esperando que el texto quede en el fondo.** Eso
   dibuja sobre la ventana raíz y depende de cómo se pinte el wallpaper; en
   esta ThinkPad el texto no quedó visible de forma confiable.
4. **Confiar en `desktop` bajo i3 sin comprobar una recarga.** Aunque puede
   verse bien en un escritorio vacío, i3 puede adoptar o maximizar esa ventana
   después de una recarga. Por ello no se considera suficiente una captura sin
   ventanas: hay que comprobar también el apilado con una ventana normal.
5. **Cambiar varias propiedades a la vez sin una prueba de regresión.** Durante
   las iteraciones se modificaron posición, fondo, transparencia, tamaño y
   reglas del WM demasiado cerca unas de otras. La configuración debe cambiarse
   de forma pequeña y validarse después de cada cambio.

### Hallazgo decisivo

La configuración que cumple el requisito en esta sesión X11 es:

```text
own_window = true
own_window_type = 'override'
own_window_class = 'RafexConky'
own_window_title = 'Rafex ThinkPad Monitor'
own_window_colour = '#00000000'
alignment = 'top_left'
minimum_width = 320
maximum_width = 320
```

`override` deja la ventana fuera de la gestión normal de i3/Openbox. En la
prueba real, Conky apareció en un escritorio vacío, desapareció visualmente
debajo de una terminal y no apareció en `_NET_CLIENT_LIST_STACKING`. Por eso
la propiedad de apilado se valida con una ventana normal abierta, no solo con
`pgrep` o una captura del escritorio vacío.

El fondo transparente es una propiedad distinta del apilado. `#00000000`
solicita transparencia, pero la transparencia ARGB/pseudo-transparencia puede
depender del compositor X11 y del controlador. Un rectángulo oscuro o una
transparencia imperfecta no debe corregirse cambiando `override` a `dock`,
`panel` o `floating`: primero se debe diagnosticar el compositor.

### Procedimiento de validación obligatorio

Después de modificar Conky, comprobar desde la sesión gráfica local:

```bash
pgrep -a -u "$USER" -x conky
~/.local/bin/conky-launch.sh --reload
i3 -C -c ~/.config/i3/config
grep -nE 'own_window|alignment|gap_|minimum_|maximum_height|border_color' \
  ~/.config/conky/conky.conf
```

La prueba visual mínima tiene dos estados:

1. En un escritorio vacío, Conky debe verse en la columna izquierda, debajo de
   la barra superior y sin ocupar todo el ancho.
2. En ese mismo escritorio, abrir una ventana normal que cubra la columna.
   Conky debe quedar completamente oculto; no debe desplazar la ventana ni
   permanecer por encima.

Como comprobación técnica adicional, una ventana `override` no debe aparecer
   como cliente administrado por i3 ni publicar `_NET_WM_STRUT` o
   `_NET_WM_STRUT_PARTIAL`. Si aparece `MAXIMIZED_VERT`, `MAXIMIZED_HORZ` o una
   geometría de pantalla completa, la prueba falla y no se debe publicar el
   cambio.

### Reglas de mantenimiento

- Mantener exactamente una instancia administrada por
  `~/.local/bin/conky-launch.sh`.
- Mantener únicamente el autoinicio `exec_always` de i3 y el autoinicio de
  Openbox; no añadir reglas `floating`, `above`, `dock` o `panel`.
- Recargar con `conky-launch.sh --reload`; no usar `kill-server`, `wmctrl` ni
  matar procesos ajenos.
- Antes de cambiar la configuración, conservar el respaldo fechado que crea
  `install-conky --apply`.
- Si falla el apilado, volver a revisar primero `own_window_type`, las reglas
  del WM y la lista de clientes antes de tocar Picom o el wallpaper.
- Si falla únicamente la transparencia, revisar el compositor X11 de la
  sesión (`_NET_WM_CM_S0` y el proceso de Picom) sin cambiar el modelo de
  apilado que ya fue validado.
- No considerar válida una modificación solo porque el panel se vea bonito:
  debe pasar simultáneamente la prueba de escritorio vacío y la prueba con
  una ventana normal abierta.

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
