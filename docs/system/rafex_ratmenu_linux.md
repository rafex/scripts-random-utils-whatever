---
title: rafex_ratmenu_linux.sh
description: Menú activo de acciones Rafex para la ThinkPad mediante ratmenu.
tags:
  - sistema
  - menú
  - thinkpad
---

# rafex_ratmenu_linux.sh

Abre el menú ligero de aplicaciones, controles, capturas y energía mediante
ratmenu. Si ratmenu no está disponible, usa el menú 9menu versionado como
fallback.

- **Ruta:** `scripts/system/rafex_ratmenu_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `ratmenu` y helpers del perfil.

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos

### `ratmenu: fatal: cannot load font DejaVu Sans Mono-11`

**Causa:** el lanzador pasaba un nombre estilo Fontconfig/Xft a ratmenu, que
utiliza fuentes X11 mediante XCreateFontSet. En la ThinkPad el lanzamiento directo
terminó con código 1 y ese error; `xlsfonts -fn fixed` sí encontró el alias.
El atajo parecía no responder porque el menú terminaba antes de mostrarse.

**Solución:** desde v1.1.1 el lanzador usa `-font fixed`. Aplicar desde el
repositorio actualizado con `just install-ratmenu --apply`. No requiere reiniciar
ni cambiar bindings: los existentes ejecutan el mismo helper instalado.
Si `fixed` tampoco existe en otro servidor X11, revisar sus fuentes antes de
cambiar atajos o instalar fuentes Nerd/Fontconfig, que no resuelven este fallo.

### `ratmenu de Rafex ya está abierto; no se duplica`

**Causa:** `XF86Tools` o `Super+F9` se pulsó otra vez mientras el menú seguía
abierto. El lanzador identifica únicamente ventanas propias por su etiqueta
`Rafex ThinkPad` y mantiene un lock de usuario durante la apertura.

**Solución:** no se abre otra ventana. Selecciona una entrada o cierra el menú
existente. Ratmenu de otro usuario o sin la etiqueta de Rafex no se considera
administrado ni se cierra.

Validación manual: abrir `~/.local/bin/rafex-ratmenu.sh`, cerrar con Escape y
probar `Super+F9` y la tecla multimedia `XF86Tools`. La corrección del lanzamiento
no demuestra por sí sola qué keysym emite la tecla física; si solo falla esta
última, observar el evento antes de modificar bindings.
## Changelog

### v1.1.1 — 2026-09-05

**fix:** usar el alias X11 `fixed` en lugar de una fuente que impedía abrir
ratmenu en la ThinkPad. Sin cambios en suspensión ni bindings.

### v1.2.0 — 2026-09-05

**fix:** evitar ventanas duplicadas al pulsar repetidamente los accesos de
ratmenu, con detección de procesos administrados y lock por usuario.

## Requisitos

Debe ejecutarse dentro de i3 u Openbox. Las acciones sensibles conservan las
confirmaciones de los helpers existentes.

## Uso

```bash
just install-ratmenu --apply
just rafex-ratmenu
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | El menú no necesita argumentos. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `HOME` | sesión actual | Ubicación de helpers y configuración. |

## Ejemplos

```bash
~/.local/bin/rafex-ratmenu.sh
```

## Fallos conocidos

### `ratmenu no está instalado`

**Causa:** se intentó abrir el helper antes del instalador.

**Solución:** instala con `just install-ratmenu --apply`.

## Changelog

### [Unreleased]
- **feat:** crear menú activo ratmenu con respaldo 9menu.
- **fix:** activar fallback automático a 9menu cuando ratmenu no está disponible.
