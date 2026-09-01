---
title: install_rafex_control_panel_linux.sh
description: Instala el panel GTK3/PyGObject del perfil Rafex ThinkPad.
tags:
  - instalación
  - gtk
  - thinkpad
---

# install_rafex_control_panel_linux.sh

Instala un panel GTK3 de acciones conocidas para i3 y Openbox.

- **Ruta:** `scripts/install/install_rafex_control_panel_linux.sh`
- **SO requerido:** Linux (Debian con X11)
- **Dependencias:** Python 3, `python3-gi`, GTK3 y sudo solo para APT.

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

Se ejecuta como usuario normal y necesita una sesión gráfica para mostrar la
ventana. No crea un servicio persistente.

## Uso

```bash
just install-rafex-control-panel --check
just install-rafex-control-panel --plan
just install-rafex-control-panel --apply
just install-rafex-control-panel --status
just rafex-control-panel
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba GTK, Python y la integración. |
| `--plan` | `--dry-run` | Simula la instalación. |
| `--apply` | — | Instala e integra el panel. |
| `--status` | — | Muestra el estado sin abrir la ventana. |

## Variables de entorno

No requiere variables. Respeta `HOME` y el `PATH` de la sesión.

## Ejemplos

```bash
just install-rafex-control-panel --apply
just rafex-control-panel
```

## Protecciones de seguridad

- Nunca se ejecuta como root.
- No acepta comandos arbitrarios ni edita archivos arbitrarios.
- Reutiliza helpers conocidos y deja APT en Synaptic/Just.
- Las acciones sensibles continúan usando confirmaciones del menú existente.
- Esta primera versión no añade nuevas reglas Polkit: las acciones del panel se
  ejecutan como usuario o delegan en las políticas ya instaladas. Se reservará
  una allowlist Polkit concreta para una operación administrativa real, evitando
  instalar permisos sin un helper que los necesite.

## Fallos conocidos

### `gi.repository.Gtk no está disponible`

**Causa:** faltan PyGObject o los introspection bindings GTK3.

**Solución:** ejecuta `just install-rafex-control-panel --apply`.

## Changelog

### [Unreleased]
- **feat:** añadir panel GTK3 de administración acotada.
