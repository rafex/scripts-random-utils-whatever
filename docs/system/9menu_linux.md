---
title: Configuración base de 9menu en Linux
description: Menú ligero de acciones frecuentes para i3 en la ThinkPad X1 Yoga
tags:
  - i3
  - 9menu
  - thinkpad
---

# Configuración base de 9menu en Linux

El perfil `thinkpad-x1-yoga-1st` instala un menú 9menu pequeño para acciones
frecuentes. Se abre con la tecla de herramientas/engranaje (`XF86Tools`) o con
`Mod+F9`. La tecla `XF86WakeUp` queda reservada para suspender el equipo.

- **Ruta del menú:** `dotfiles/profiles/thinkpad-x1-yoga-1st/config/9menu/laptop.menu`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `9menu`, `alacritty`, `firefox`, `thunar`, `pavucontrol`, `rofi` y las herramientas del perfil

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

- Sesión gráfica Xorg con i3.
- Paquete `9menu` instalado.
- Perfil ThinkPad instalado o el archivo copiado a
  `~/.config/9menu/laptop.menu`.
- Scripts del perfil disponibles en `~/.local/bin/`.

## Uso

Abrir directamente:

```sh
9menu -popup -label "ThinkPad" -file ~/.config/9menu/laptop.menu
```

En el perfil i3 se puede usar:

```text
XF86Tools
```

o:

```text
Mod+F9
```

Se selecciona con clic izquierdo o derecho, o con las flechas y `Enter`.
`exit` cierra el menú. La opción seleccionada ejecuta el comando asociado y el
menú desaparece porque se usa `-popup`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `-popup` | — | Cierra 9menu después de seleccionar una acción. |
| `-label "ThinkPad"` | — | Define el título de la ventana. |
| `-file <archivo>` | — | Lee las entradas desde un archivo de menú. |
| `XF86Tools` | — | Abre el menú desde la tecla de herramientas si X11 la reporta. |
| `Mod+F9` | — | Atajo alternativo independiente del teclado multimedia. |
| `XF86WakeUp` | — | Suspende mediante `loginctl suspend`; el firmware gestiona el despertar. |

## Variables de entorno

No se requieren variables de entorno. La ruta de comandos usa `HOME` para
encontrar los scripts instalados en `~/.local/bin/`.

## Ejemplos

Probar una entrada mínima:

```sh
9menu -popup -label "Prueba" "Terminal:exec alacritty" "Audio:exec pavucontrol" exit
```

Probar el menú completo del perfil:

```sh
9menu -popup -label "ThinkPad" -file ~/.config/9menu/laptop.menu
```

Recargar i3 después de actualizar su configuración:

```text
Mod+Shift+R
```

## Protecciones de seguridad

- El archivo contiene únicamente comandos locales conocidos.
- No se usa `sudo` desde el menú.
- No se incluyen comandos destructivos ni apagado directo; la opción de energía
  abre el centro de control existente, que confirma las acciones sensibles.
- `XF86WakeUp` solo solicita suspensión mediante `loginctl`; el despertar lo
  gestiona el firmware y no requiere un comando adicional.
- No añadir entradas provenientes de archivos no confiables: 9menu ejecuta el
  comando asociado mediante un shell.

## Fallos conocidos

### `9menu: command not found`

**Causa:** el paquete no está instalado o el perfil no se ha reinstalado.
**Solución:** instalar `9menu` con APT o ejecutar de nuevo el instalador del
perfil ThinkPad.

### La tecla `XF86Tools` no abre el menú

**Causa:** el firmware o Xorg no expone esa tecla con ese keysym.
**Solución:** usar `Mod+F9`; comprobar el keysym real con `xev` y ajustar el
binding solo si se identifica una tecla diferente.

### La tecla `XF86WakeUp` no suspende

**Causa:** el firmware o Xorg no expone esa tecla con ese keysym.
**Solución:** comprobar el keysym real con `xev`; como alternativa, usar el
atajo de i3 configurado para suspensión desde el centro de control.

### El menú aparece sin iconos

**Causa:** 9menu es un menú textual y no soporta iconos de aplicaciones.
**Solución:** usar `rofi -show drun -show-icons` para el lanzador visual.

## Changelog

### [Unreleased]

- **feat:** añadir menú 9menu base para acciones frecuentes de la ThinkPad.
- **docs:** documentar atajos, formato de entradas y límites de seguridad.
