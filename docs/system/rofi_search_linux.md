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

## Changelog

### [Unreleased]

**feat:** añadir búsqueda de aplicaciones compatible con i3.
