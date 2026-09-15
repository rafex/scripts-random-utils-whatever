---
title: rafex_browser_search_linux.sh
description: Abre DuckDuckGo con el navegador Firefox disponible.
tags:
  - sistema
  - thinkpad
---

# rafex_browser_search_linux.sh

Helper para el alias `Mod+Shift+B` y usos manuales. `XF86Search` está reservado
al catálogo de aplicaciones de Rofi, evitando mezclar la búsqueda web con el
launcher dentro de la configuración de i3.

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
- **feat:** conserva la apertura de DuckDuckGo para `Mod+Shift+B` y usos
  manuales después de reservar `XF86Search` para el catálogo de aplicaciones.
