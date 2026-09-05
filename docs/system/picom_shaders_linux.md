---
title: shaders GLSL de Picom para Linux
description: Variantes GLSL pequeñas y seguras para Picom v13 en la ThinkPad.
tags:
  - sistema
  - picom
  - shaders
---

# shaders GLSL de Picom para Linux

Conjunto local de shaders para Picom v13. Solo se aplica un shader a las
ventanas que lo declaran en las reglas; el compositor continúa controlando por
separado la transparencia, el blur y las sombras.

- **Ruta:** `dotfiles/profiles/thinkpad-x1-yoga-1st/config/picom/shaders/`
- **SO requerido:** Linux con Xorg, Picom v13 y backend GLX
- **Dependencias:** Picom compilado con OpenGL; no requiere herramientas externas en tiempo de ejecución.

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

Instala Picom upstream y sus archivos de configuración con:

```bash
just install-picom-upstream --apply
```

El instalador copia los shaders a `~/.config/picom/shaders/`. Las rutas son
relativas a `~/.config/picom/picom.conf`.

## Uso

La configuración administrada usa `nord.glsl` solo para Alacritty:

```conf
{
  match = "class_g = 'Alacritty'";
  opacity = 0.93;
  blur-background = true;
  shader = "shaders/nord.glsl";
}
```

Reinicia Picom después de modificar una regla:

```bash
just picom-toggle --disable
just picom-toggle --enable
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `neutral.glsl` | — | Renderizado normal de Picom; fallback de diagnóstico. |
| `nord.glsl` | — | Gradación fría muy sutil; variante activa en Alacritty. |
| `paper.glsl` | — | Gradación cálida y ligera para el tema Paper. |
| `everforest.glsl` | — | Gradación verde muy ligera para Everforest. |
| `dracula.glsl` | — | Gradación violeta muy ligera para Dracula. |

## Variables de entorno

No utiliza variables de entorno. Picom resuelve las rutas de shader relativas
al archivo de configuración.

## Ejemplos

```bash
# Fallback neutro si el driver no acepta la gradación Nord.
sed -i 's#shaders/nord.glsl#shaders/neutral.glsl#' ~/.config/picom/picom.conf
just picom-toggle --disable
just picom-toggle --enable
```

Para conservar el archivo administrado, cambia la regla correspondiente en el
perfil y vuelve a ejecutar `just install-picom-upstream --apply`.

## Protecciones de seguridad

- Los shaders son archivos locales de texto GLSL; no ejecutan shell ni acceden
  a red, disco o dispositivos.
- Conservan el alfa de la ventana y delegan el procesamiento estándar a
  `default_post_processing()`.
- Conky, EWW, i3bar, tint2 y las ventanas de escritorio no reciben shader.
- No se aplica ningún shader al escritorio ni a Firefox en la configuración
  inicial.
- Si hay artefactos, `just picom-toggle --disable` desactiva el compositor sin
  modificar el gestor de ventanas.

## Fallos conocidos

### `shader compilation failed`

**Causa:** el driver GLX no acepta la interfaz GLSL del shader o Picom no se
está ejecutando con backend GLX.

**Solución:** selecciona `neutral.glsl`, reinicia Picom y consulta el log. Si
continúa fallando, desactiva Picom y conserva el paquete de Debian como
fallback.

### La variante no cambia el aspecto

**Causa:** ninguna regla apunta al archivo, la ventana no coincide con la
condición o Picom no se reinició.

**Solución:** comprueba la regla de Alacritty, ejecuta el reinicio indicado y
revisa `picom --diagnostics` si está disponible en la versión instalada.

## Changelog

### [Unreleased]

- **feat:** añadir shaders neutro, Nord, Paper, Everforest y Dracula para Picom v13.
- **style:** activar únicamente la gradación Nord sutil en Alacritty.
