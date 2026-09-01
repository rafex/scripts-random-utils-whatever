---
title: eww_widgets_linux.sh
description: Abre y cierra widgets EWW opcionales sin reservar espacio.
tags:
  - sistema
  - eww
---

# eww_widgets_linux.sh

Controla el widget `status` de EWW del perfil Rafex.

- **Ruta:** `scripts/system/eww_widgets_linux.sh`
- **SO requerido:** Linux (X11)
- **Dependencias:** bash, `eww` instalado por `install_eww_linux.sh`.

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Fallos conocidos
## Changelog

## Requisitos

Ejecuta dentro de i3 u Openbox con `DISPLAY`. El widget no usa `reserve` y no
se activa automáticamente.

## Uso

```bash
just eww-widgets --open status
just eww-widgets --close status
just eww-widgets --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--open` | — | Inicia el daemon de usuario y abre una ventana. |
| `--close` | — | Cierra una ventana concreta. |
| `--status` | — | Consulta daemon y ventanas. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `DISPLAY` | sesión actual | Pantalla X11 destino. |

## Ejemplos

```bash
just eww-widgets --open status
just eww-widgets --close status
```

## Fallos conocidos

### `DISPLAY ausente`

**Causa:** se ejecutó desde SSH sin reenvío o fuera de la sesión gráfica.

**Solución:** ejecútalo desde la sesión X11 local.

## Changelog

### [Unreleased]
- **feat:** añadir control explícito de widgets EWW.
