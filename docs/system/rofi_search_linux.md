---
title: rofi_search_linux.sh
description: Buscador y lanzador de aplicaciones para i3
tags:
  - i3
  - rofi
---

# rofi_search_linux.sh

Lanza Rofi en modo aplicaciones, combinado o comandos. En Linux, Rofi cumple
la función de búsqueda/launcher que no ofrece i3 por sí mismo.

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

### `$mod+space` no hace nada hasta presionar `$mod+r`

**Causa:** una instancia previa de `rofi` queda colgada e invisible (sin
ventana en `wmctrl -l` pero viva en `ps aux`), bloqueando el lanzamiento
de una nueva por el mecanismo de instancia única de rofi. Confirmado en
vivo: `i3-msg -t get_binding_state` en modo `default`, proceso `rofi
-show drun -show-icons` vivo sin ventana asociada.

**Solución:** el script mata cualquier instancia previa de `rofi`
(`pkill -x rofi`) antes de lanzar una nueva en los modos `apps`, `combi`
y `run`. Asegúrate de que `$menu` en
`dotfiles/profiles/<perfil>/config/i3/config` apunte a
`~/.local/bin/rofi-search.sh apps` y no a `rofi` directamente.

## Changelog

### [Unreleased]

**feat:** añadir búsqueda de aplicaciones compatible con i3.

**fix:** matar instancias previas de `rofi` (`pkill -x rofi`) antes de
lanzar una nueva en los modos `apps`, `combi` y `run`, evitando que un
proceso colgado e invisible bloquee `$mod+space`.
