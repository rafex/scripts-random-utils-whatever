---
title: jdtls_linux.sh
description: Preparación de Java language server para Neovim
tags:
  - desarrollo
---

# jdtls_linux.sh

Lanza Eclipse JDT Language Server para editores como Neovim. Requiere JDTLS instalado en `/opt/github/eclipse.jdt.ls`.

- **Ruta:** `scripts/dev/jdtls_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `java`, JDTLS instalado

______________________________________________________________________

## Uso

```sh
./scripts/dev/jdtls_linux.sh [workspace_dir]
```

| Argumento | Default | Descripción |
|---|---|---|
| `workspace_dir` | `~/.local/share/nvim/jdtls-workspace/default` | Directorio de workspace |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `JDTLS_HOME` | `/opt/github/eclipse.jdt.ls` | Ruta de instalación de JDTLS |
| `JAVA_BIN` | `java` | Binario de Java a usar |

______________________________________________________________________

## Ejemplos

```sh
./scripts/dev/jdtls_linux.sh

./scripts/dev/jdtls_linux.sh /tmp/my-project

JDTLS_HOME=/opt/jdtls JAVA_BIN=/usr/lib/jvm/java-21/bin/java \
  ./scripts/dev/jdtls_linux.sh
```

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/jdtls`.
