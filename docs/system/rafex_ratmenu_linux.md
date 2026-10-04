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
fallback. Las acciones de sesión y energía se registran por el helper
compartido en `~/.local/state/rafex/ratmenu-actions.jsonl`.

- **Ruta:** `scripts/system/rafex_ratmenu_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** bash, `ratmenu`, `python3` y helpers del perfil.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

Debe ejecutarse dentro de i3 u Openbox en X11. Las acciones sensibles
conservan las confirmaciones de los helpers existentes.

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
| `HOME` | Sesión actual | Ubicación de helpers y configuración. |
| `XDG_STATE_HOME` | `~/.local/state` | Permite cambiar la ubicación del historial de acciones. |

El helper identifica estas entradas con el origen `ratmenu`. El historial
común también puede incluir acciones iniciadas desde otros menús.

## Ejemplos

```bash
~/.local/bin/rafex-ratmenu.sh
tail -n 20 "${XDG_STATE_HOME:-$HOME/.local/state}/rafex/ratmenu-actions.jsonl"
```

## Fallos conocidos

### `ratmenu: fatal: cannot load font DejaVu Sans Mono-11`

**Causa:** Ratmenu usa fuentes X11 mediante XCreateFontSet; el nombre estilo
Fontconfig/Xft no existe como fuente X11. En la ThinkPad, `xlsfonts -fn fixed`
confirmó que el alias `fixed` sí está disponible.

**Solución:** desde v1.1.1 el lanzador usa `-font fixed`. Aplica el helper
actualizado con `just install-ratmenu --apply`. Si `fixed` no existe en otro
servidor X11, revisa sus fuentes antes de cambiar los bindings.

### `ratmenu de Rafex ya está abierto; no se duplica`

**Causa:** se abrió otra vez mientras una ventana administrada con la etiqueta
`Rafex ThinkPad` seguía activa.

**Solución:** selecciona una entrada o cierra el menú existente.

### Falló una acción de energía o sesión

**Causa:** el comando del sistema devolvió un error. El helper incluye el texto
del comando y su código de retorno en la notificación y el historial. En fallos
de suspensión o hibernación, el evento incluye capacidades de logind,
inhibidores, estado de sesión y modos de suspensión del kernel.

**Solución:** revisa el último evento en
`~/.local/state/rafex/ratmenu-actions.jsonl`. El archivo se crea con permisos
`0600`; el directorio usa `0700`.

### `ratmenu no está instalado`

**Causa:** se abrió el helper antes de instalar ratmenu y no hay fallback 9menu
disponible.

**Solución:** ejecuta `just install-ratmenu --apply`.

Validación manual del menú: abrir `~/.local/bin/rafex-ratmenu.sh`, cerrar con
Escape y probar `Super+F9` y la tecla multimedia `XF86Tools`. Esto no demuestra
por sí solo qué keysym emite la tecla física; si solo falla esa tecla, observa
el evento antes de modificar bindings.

## Changelog

### [Unreleased]

- **fix:** la entrada del panel de control informa la receta de instalación
  cuando el helper GTK todavía no existe.

### v1.3.0 — 2026-10-04

**feat:** registrar acciones de energía y sesión iniciadas desde Ratmenu.

- Etiquetar el origen Ratmenu en el historial JSONL compartido.
- Mostrar la salida del comando y su código de retorno cuando una acción falla.
- Añadir datos de logind, inhibidores y modos del kernel a fallos de suspensión
  e hibernación.

### v1.2.0 — 2026-09-05

**fix:** evitar ventanas duplicadas al abrir Ratmenu repetidamente.

- Detectar ventanas administradas y mantener un lock de usuario durante la apertura.

### v1.1.1 — 2026-09-05

**fix:** usar el alias X11 `fixed` para evitar que Ratmenu falle al abrirse.

### v1.1.0 — 2026-09-05

**feat:** incorporar Ratmenu con fallback a 9menu.

- Añadir el menú activo de acciones del perfil ThinkPad.
- Activar fallback automático a 9menu si ratmenu no está disponible.
