---
title: rafex_control_panel.py
description: Panel gráfico de acciones conocidas del perfil ThinkPad.
tags:
  - sistema
  - gtk
  - thinkpad
---

# rafex_control_panel.py

Panel GTK3 de usuario para abrir controles existentes del perfil Rafex.

- **Ruta:** `scripts/system/rafex_control_panel.py`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** Python 3, PyGObject, GTK3 y helpers instalados.

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

Ejecuta como `rafex` desde una sesión gráfica. El instalador crea un wrapper
en `~/.local/bin/rafex-control-panel.sh`.

## Uso

```bash
just rafex-control-panel
~/.local/bin/rafex-control-panel.sh
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | La interfaz se controla con botones GTK. |

## Variables de entorno

No requiere variables. Usa `HOME`, `PATH` y `DISPLAY` de la sesión.

## Ejemplos

```bash
just install-rafex-control-panel --apply
just rafex-control-panel
```

## Protecciones de seguridad

No acepta texto como comando, no usa shell para sus acciones y rechaza la
ejecución como root. Las acciones administrativas se delegan a los helpers
existentes.

## Fallos conocidos

### `DISPLAY ausente`

**Causa:** se inició desde una terminal SSH sin sesión X11.

**Solución:** abre el panel desde i3/Openbox o usa el atajo gráfico.

## Changelog

### [Unreleased]
- **feat:** añadir clase GTK `RafexControlPanel`.
