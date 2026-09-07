---
title: rofi_search_linux.sh
description: Menús y búsqueda de aplicaciones para i3
tags:
  - i3
  - rofi
---

# rofi_search_linux.sh

Lanza Rofi en modo aplicaciones, combinado o comandos. En el perfil ThinkPad
Ulauncher es el launcher principal de `$mod+space`; Rofi se conserva para
ventanas, navegador, ejecución, menús y confirmaciones.

- **Ruta:** `scripts/system/rofi_search_linux.sh`
- **SO requerido:** Linux (Xorg/i3)
- **Dependencias:** `rofi`

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

Debe ejecutarse dentro de una sesión Xorg.

## Uso

```sh
~/.local/bin/rofi-search.sh apps
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `apps` | — | Busca aplicaciones instaladas. |
| `combi` | — | Combina aplicaciones, ventanas y comandos. |
| `run` | — | Ejecuta comandos. |
| `browser` | — | Abre el navegador predeterminado. |

## Variables de entorno

Este script no requiere variables de entorno.

## Ejemplos

```sh
~/.local/bin/rofi-search.sh apps
~/.local/bin/rofi-search.sh combi
~/.local/bin/rofi-search.sh browser
```

## Fallos conocidos

### `Can't open display`

**Causa:** ejecución desde SSH sin `DISPLAY` válido.
**Solución:** usar la tecla de búsqueda dentro de i3.

### El binding de Ulauncher no muestra el launcher

**Causa:** Ulauncher no está instalado, su servicio de usuario no está
activo, o el perfil de i3 todavía no fue recargado después de cambiar el
binding.

**Solución:** instala Ulauncher con `just install-ulauncher --apply`,
recarga i3 con `$mod+Shift+r` y comprueba `systemctl --user status
ulauncher.service`. Rofi continúa disponible mediante los comandos de este
script, aunque ya no es el launcher de `$mod+space` en ThinkPad.

### Una instancia de Rofi queda colgada

**Causa:** una instancia previa de `rofi` puede quedar viva e invisible.

**Solución:** el script mata cualquier instancia previa de `rofi`
(`pkill -x rofi`) antes de lanzar una nueva en los modos `apps`, `combi` y
`run`. Esto solo afecta a Rofi administrado por este helper, no a Ulauncher.

## Changelog

### [Unreleased]

**feat:** añadir búsqueda de aplicaciones compatible con i3.

**fix:** matar instancias previas de `rofi` (`pkill -x rofi`) antes de
lanzar una nueva en los modos `apps`, `combi` y `run`, evitando que un
proceso colgado e invisible bloquee nuevas aperturas de Rofi.
