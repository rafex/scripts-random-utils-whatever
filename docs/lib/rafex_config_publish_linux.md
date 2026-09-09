---
title: rafex_config_publish_linux.sh
description: Biblioteca de publicación segura para configuraciones de usuario ThinkPad.
tags:
  - biblioteca
  - thinkpad
  - configuración
---

# rafex_config_publish_linux.sh

Biblioteca interna con primitivas de rutas, hashes, respaldos, bloqueo y
publicación atómica. El publicador central la usa junto con su registro de
snapshots; los instaladores especializados pueden reutilizar sus guards sin
convertirse en propietarios de todo `~/.config`.

- **Ruta:** `scripts/lib/rafex_config_publish_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, coreutils, `flock`

---

## Índice

## Requisitos

No se ejecuta directamente. Se carga mediante `source`; el publicador central
define las variables de sus árboles permitidos antes de cargarla.

## Uso

Las funciones comienzan con `rafex_publish_` y no deben llamarse desde scripts
que no hayan definido las variables del publicador.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | No tiene interfaz CLI; es una biblioteca interna. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `RAFEX_PUBLISH_CHECKOUT` | Checkout permitido para fuentes versionadas. |
| `RAFEX_PUBLISH_GENERATED_ROOT` | Árbol permitido para artefactos generados heredados. |
| `RAFEX_PUBLISH_STATE_DIR` | Estado, respaldos y bloqueo del publicador. |
| `RAFEX_PUBLISH_LOG` | Bitácora JSONL privada. |
| `RAFEX_PUBLISH_LOCK_FILE` | Archivo usado por `flock`. |

## Ejemplos

```bash
source scripts/lib/rafex_config_publish_linux.sh
```

No se proporciona un modo con variables o `.env`: las rutas se definen por el
publicador a partir de XDG y del checkout validado.

## Protecciones de seguridad

- Rechaza fuentes y enlaces fuera de los árboles permitidos.
- El snapshot activo se valida dentro de `~/.local/share/rafex-thinkpad/snapshots`.
- No usa `sudo`, Git, red ni comandos de sistema privilegiados.
- Usa archivos temporales y `mv` atómico.
- Registra hashes antes y después sin incluir el contenido de las
  configuraciones.
- El bloqueo evita dos publicaciones simultáneas.

## Fallos conocidos

### `destino no administrado`

**Causa:** existe un archivo regular o un enlace que no pertenece al checkout
esperado.

**Solución:** revisar el archivo y ejecutar `just rafex-config --adopt` solo si
se desea migrarlo con respaldo.

## Changelog

### [Unreleased]

**refactor:** mantiene primitivas comunes compatibles con el publicador de
snapshots y los instaladores especializados.
