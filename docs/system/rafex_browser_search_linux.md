---
title: rafex_browser_search_linux.sh
description: Abre DuckDuckGo con el navegador Firefox disponible.
tags:
  - sistema
  - thinkpad
---

# rafex_browser_search_linux.sh

Helper único para `XF86Search` y el alias `Mod+Shift+B`. Evita repetir la
lógica del navegador dentro de la configuración de i3.

- **Ruta:** `scripts/system/rafex_browser_search_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash; Firefox o Firefox ESR; `notify-send` opcional

---

## Índice
## Requisitos

Debe existir `firefox` o `firefox-esr` en `PATH`.

## Uso

```bash
just rafex-browser-search
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| ninguna | — | Abre DuckDuckGo en una pestaña nueva. |

## Variables de entorno

No utiliza variables de entorno ni archivo `.env`.

## Ejemplos

```bash
just rafex-browser-search
```

## Fallos conocidos

### `Firefox no está instalado`

**Causa:** no se encontró `firefox` ni `firefox-esr`.

**Solución:** instalar un navegador Firefox y repetir la acción.

## Changelog

### [Unreleased]
- **feat:** centraliza la apertura de DuckDuckGo para los atajos ThinkPad.
