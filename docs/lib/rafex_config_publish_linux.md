---
title: rafex_config_publish_linux.sh
description: Biblioteca de publicación segura para configuraciones de usuario ThinkPad.
tags:
  - biblioteca
  - thinkpad
  - configuración
---

# rafex_config_publish_linux.sh

Biblioteca interna que implementa bloqueos, respaldos, hashes, enlaces
simbólicos y escrituras seguras para el publicador central ThinkPad.

- **Ruta:** `scripts/lib/rafex_config_publish_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, coreutils, `flock`

---

## Índice

## Requisitos

No se ejecuta directamente. Debe cargarse mediante `source` desde el publicador
`rafex_config_linux.sh`.

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
| `RAFEX_PUBLISH_CHECKOUT` | Checkout permitido para fuentes estáticas. |
| `RAFEX_PUBLISH_GENERATED_ROOT` | Árbol permitido para archivos generados. |
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

**feat:** añade primitivas comunes de publicación, backup y rollback.
