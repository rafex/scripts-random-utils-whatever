---
title: eww_widgets_linux.sh
description: Controla el dashboard EWW de Rafex sin reservar espacio del escritorio.
tags:
  - sistema
  - eww
---

# eww_widgets_linux.sh

Controla la columna interactiva `rafex-widgets` de EWW del perfil ThinkPad.

- **Ruta:** `scripts/system/eww_widgets_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** bash, `eww` instalado por `install_eww_linux.sh`, `flock` (`util-linux`) y `DISPLAY` para abrir la ventana.

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

Ejecuta dentro de i3 u Openbox con una sesión X11. El instalador debe haber
creado `~/.config/eww/eww.yuck`, `~/.config/eww/eww.scss` y los helpers de
`~/.local/bin/`.

La ventana usa el monitor primario (`<primary>`), `windowtype desktop`,
`stacking bg` y no tiene `reserve`. Por
eso queda detrás de ventanas normales, no mueve el área útil de i3 y vuelve a
verse cuando el escritorio queda libre. Sus botones solo son utilizables
cuando la columna está expuesta. Los controles muestran iconos Unicode: pantalla
con sol y `−/+` para brillo, teclado con `−/+`, altavoz con `−/+` y mute, y
símbolos específicos para red, micrófono, captura, bloqueo y energía.

## Uso

```bash
just eww-widgets --status
just eww-widgets --open dashboard
just eww-widgets --close dashboard
just eww-widgets --toggle dashboard
just eww-widgets --reload
```

El autostart se instala en i3 y Openbox. En i3 usa `exec` en lugar de
`exec_always`, por lo que una recarga de la configuración no vuelve a lanzar
el dashboard. El helper también usa un bloqueo exclusivo temporal para
serializar aperturas, cierres, toggles y recargas; de esta forma dos llamadas
simultáneas no crean una segunda instancia. El atajo `Super+Control+W` alterna
la ventana sin duplicarla.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--open dashboard` | — | Inicia el daemon de usuario si hace falta y abre una sola ventana. |
| `--close dashboard` | — | Cierra únicamente `rafex-widgets`. |
| `--toggle dashboard` | — | Muestra u oculta la ventana administrada. |
| `--reload` | — | Recarga la configuración si el daemon ya está activo. |
| `--status` | — | Consulta archivos, daemon, ventanas y `DISPLAY`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `DISPLAY` | sesión actual | Pantalla X11 destino. |
| `XDG_CONFIG_HOME` | `~/.config` | Raíz de la configuración EWW. |

## Ejemplos

```bash
just install-eww --apply
just eww-widgets --open dashboard
just eww-widgets --toggle dashboard
just eww-widgets --close dashboard
```

Para recuperar el escritorio si EWW falla, cambia a otra TTY, termina solo el
daemon del usuario con `~/.local/bin/eww kill` y vuelve a entrar a X11. También
puedes desactivar el bloque administrado de EWW en i3/Openbox y conservar los
archivos para una prueba posterior.

## Protecciones de seguridad

- Se ejecuta como usuario normal; nunca usa `sudo` ni root.
- Solo permite la ventana fija `rafex-widgets` y no mata procesos EWW ajenos.
- No usa `wmctrl`, `dock`, `panel`, `reserve` ni reposicionamiento posterior.
- No muestra SSID, IP, IMEI, IMSI, APN, MAC, rutas privadas ni secretos.
- Los botones llaman a una allowlist de `eww_actions_linux.sh`; no aceptan
  comandos arbitrarios desde Yuck.

## Fallos conocidos

### `DISPLAY ausente`

**Causa:** se ejecutó desde SSH sin reenvío o fuera de la sesión gráfica.

**Solución:** ejecuta `just eww-widgets --open dashboard` desde la sesión X11
local. `--status` sí funciona sin `DISPLAY`.

### El atajo vuelve a abrir el dashboard

**Causa:** versiones recientes de EWW ya no ofrecen la consulta `windows`;
el helper antiguo confundía una consulta fallida con una ventana cerrada.

**Solución:** el helper usa `active-windows` y, ante un error de consulta, no
abre ni cierra ninguna ventana. Ejecuta `just eww-widgets --status` para ver
las ventanas activas y `just eww-widgets --reload` para reconstruir la
ventana administrada.

### `EWW se abre dos veces al iniciar sesión`

**Causa:** un autostart con `exec_always` o dos llamadas simultáneas podían
consultar el estado antes de que EWW registrara la ventana.

**Solución:** ejecuta `just install-eww --apply`, que instala el autostart
idempotente con `exec`. El helper usa `flock` en una ruta temporal privada y
espera hasta 15 segundos para que termine la otra operación. Si el problema
continúa, revisa `eww-widgets --status` y elimina únicamente bloques EWW
duplicados administrados, conservando el resto de la configuración.

### La ventana no aparece sobre una aplicación

**Causa:** es intencional: el tipo `desktop` y `stacking bg` la colocan detrás
de las ventanas normales.

**Solución:** cambia de escritorio o minimiza la aplicación; no se debe
convertir en `dock` o `fg`, porque podría reservar espacio o quedar encima.

## Changelog

### [Unreleased]
- **style:** añadir emojis e indicadores `−/+` a todos los controles rápidos del dashboard.
- **fix:** evitar aperturas duplicadas con `exec` en i3 y un bloqueo exclusivo por usuario.
- **fix:** consultar ventanas con `active-windows` de EWW v0.6 y evitar que el atajo vuelva a abrir el dashboard cuando no pudo leer su estado.
- **fix:** cerrar y abrir únicamente `rafex-widgets` al recargar para aplicar de nuevo `desktop` y `stacking bg` sin afectar ventanas EWW ajenas.

### v1.0.0 — 2026-09-01

**feat:** añadir control básico de un widget EWW sin autostart.
