---
title: install_conky_linux.sh
description: Instala Conky y un panel lateral seguro para i3 y Openbox en la ThinkPad.
tags:
  - instalación
  - conky
  - thinkpad
---

# install_conky_linux.sh

Instala `conky-all` desde Debian y configura un panel informativo translúcido
en el lateral izquierdo, debajo de i3bar o tint2, con el alto útil de la
pantalla. El panel reserva su propio espacio como dock en i3, no roba el foco
y funciona también con Openbox. La plantilla usa `own_window_type = 'dock'`,
`alignment = 'top_left'`, un margen superior de 34 píxeles y una altura fija de
1030 píxeles, ajustada a la pantalla 1920×1080 de este perfil.

- **Ruta:** `scripts/install/install_conky_linux.sh`
- **SO requerido:** Linux (Debian o derivada)
- **Dependencias:** `bash`, `sudo`, `apt-get`, `apt-cache`, `i3` opcional, `conky-all`

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
| `--apply` | — | Instala `conky-all`, copia la configuración y añade los bloques administrados. |
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
- Los bloques de i3 y Openbox se reemplazan por sus marcadores, sin duplicarse.
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

### `El texto no contrasta con el fondo`

**Causa:** una configuración anterior podía usar una ventana completamente
transparente y una fuente pequeña.

**Solución:** la plantilla administrada usa `DejaVu Sans Mono` tamaño 11, se
ubica en el lateral izquierdo y aplica un fondo de tema translúcido con
opacidad alta para conservar el contraste. El texto normal usa un color
contrastante con el fondo de cada paleta. En i3 usa un dock con altura completa
debajo de la barra; el borde y los colores se actualizan junto con el tema.

### `El panel cubre las ventanas en i3`

**Causa:** una configuración anterior usaba `own_window_type = 'normal'` o
`override`, que no reserva espacio y puede terminar encima de las ventanas.

**Solución:** actualiza el repositorio y ejecuta `just install-conky --apply`.
La plantilla actual usa `own_window_type = 'dock'`, reserva el lateral izquierdo
y elimina la regla flotante de i3. Si el panel ya estaba activo, usa
`~/.local/bin/conky-launch.sh --reload` desde la sesión gráfica.
Al ejecutar `just install-conky --apply`, el instalador también corrige ese
ajuste y la geometría en una configuración anterior que conserve el bloque
administrado de Rafex; una configuración sin ese bloque no se sobrescribe.

### `existe otra instancia Conky del usuario`

**Causa:** hay otra instancia que no pertenece al PID administrado por Rafex.

**Solución:** el lanzador no la detiene. Revisa `pgrep -a conky` y decide
manualmente si esa instancia es necesaria.

## Changelog

### [Unreleased]

- `feat`: añade instalación e integración idempotente del panel Conky.
- `fix`: detecta candidatos APT correctamente en sesiones con localización
  distinta de inglés.
- `fix`: usa un dock X11 lateral izquierdo de alto completo para que i3 reserve
  el espacio y Conky no cubra las ventanas de trabajo.
