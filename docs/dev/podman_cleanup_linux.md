---
title: podman_cleanup_linux.sh
description: Limpieza controlada de almacenamiento de Podman
tags:
  - contenedores
---

# podman_cleanup_linux.sh

Limpia almacenamiento de Podman/Docker por niveles (0=análisis a 5=nuclear). Ejecuta análisis en paralelo (jobs background que monitorean disco y capas en tiempo real) y genera `REPORTE.md` con comparativa antes/después.

- **Ruta:** `scripts/dev/podman_cleanup_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `podman` y/o `docker`, `du`, `df`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

______________________________________________________________________

## Índice

- [Niveles de limpieza](#niveles-de-limpieza)
- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Análisis en paralelo](#analisis-en-paralelo)
- [Medidas de seguridad](#medidas-de-seguridad)
- [Ejemplos](#ejemplos)

> **Forma recomendada desde la raíz del repo:** usar `just podman-cleanup`.

______________________________________________________________________

## Niveles de limpieza

| Nivel | Flag | Acción Podman | Acción Docker | Riesgo |
|---|---|---|---|---|
| **0** | `--analyze` | Solo análisis, sin tocar nada | Igual | 🟢 |
| **1** | `--level 1` | `podman container prune -f` | `docker container prune -f` | 🟢 |
| **2** | `--level 2` | + `podman image prune -af` | + `docker image prune -af` | 🟡 |
| **3** | `--level 3` | + `podman builder prune -af` | + `docker builder prune -af` | 🟡 |
| **4** | `--level 4` | + `podman system prune -af --volumes` | + `docker system prune -af --volumes` | 🔴 |
| **5** | `--level 5` | + `rm -rf ~/.local/share/containers/storage/overlay/*` | + `sudo rm -rf /var/lib/docker/overlay2/*` | 🔴🔴 |

Los niveles 3+ requieren confirmación interactiva `y/N` (a menos que se use `--yes`).
Los niveles 4+ se niegan si hay contenedores running (a menos que se use `--force`).

El nivel 5 requiere `podman system reset` posterior para reinicializar el storage.

______________________________________________________________________

## Requisitos

- Linux
- Podman y/o Docker instalados
- `du`, `df`, `sleep` (coreutils)
- Para nivel 5 Docker: `sudo`

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
# Análisis (solo lectura)
just podman-cleanup --analyze

# Limpiar imágenes y contenedores stopped
just podman-cleanup -l 2

# System prune nuclear sin confirmación
just podman-cleanup -l 4 --yes
```

### Directamente

```sh
./scripts/dev/podman_cleanup_linux.sh [opciones]
```

El script **no requiere sudo** (Podman rootless, Docker requiere sudo ya instalado).

### Resultado

El script crea:

- `/tmp/podman-cleanup-<timestamp>/` — directorio con evidencia
- `/tmp/podman-cleanup-<timestamp>.tar.gz` — tarball para transporte
- `REPORTE.md` — comparativa antes/después con métricas

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--analyze` | | Nivel 0: solo análisis (default) |
| `--level <0-5>` | `-l` | Nivel de limpieza |
| `--yes` | | Saltar confirmación en niveles 3+ |
| `--force` | `-f` | Limpiar aunque haya contenedores running |
| `--docker` | | Incluir Docker además de Podman |
| `--podman-only` | | Solo Podman (default: auto-detecta ambos) |
| `--interval <seg>` | | Intervalo de monitoreo background (default: 2s) |
| `--output <dir>` | `-o` | Directorio de salida (default: autogenerado en /tmp) |
| `--help` | `-h` | Muestra la ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `PODMAN_CLEANUP_LEVEL` | `0` | Nivel de limpieza (0-5) |
| `PODMAN_CLEANUP_YES` | `0` | Saltar confirmación |
| `PODMAN_CLEANUP_FORCE` | `0` | Forzar con contenedores running |
| `PODMAN_CLEANUP_DOCKER` | `0` | Incluir Docker |
| `PODMAN_CLEANUP_OUTPUT` | autogen | Directorio de salida |
| `PODMAN_CLEANUP_INTERVAL` | `2` | Intervalo de monitoreo (seg) |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

______________________________________________________________________

## Análisis en paralelo

Mientras la limpieza corre en foreground, el script lanza en background:

| Componente | Descripción | Archivo |
|---|---|---|
| **Monitor de disco** | `df -h /` + overlay size + capas — cada 2s | `monitor.log` |
| **Top 10 capas (antes)** | Capas más grandes identificadas | `top-layers-before.txt` |
| **Top 10 capas (después)** | Capas remanentes post-limpieza | `top-layers-after.txt` |
| **Snapshot antes** | Disco, overlay, capas, contenedores, imágenes | `snapshot-before.txt` |
| **Snapshot después** | Mismas métricas post-limpieza | `snapshot-after.txt` |

El `REPORTE.md` muestra una tabla comparativa:

```
## Resultado
| Metrica | Antes | Despues | Delta |
|---------|-------|---------|-------|
| Disco usado | 390G (98%) | XXXG (XX%) | — |
| Overlay (size) | 309.3G | XX.XG | — |
| Capas (count) | 1591 | XXX | -XXX |
```

______________________________________________________________________

## Medidas de seguridad

1. **Dry-run por defecto** — sin `--level`, solo analiza (nivel 0)
1. **Backup de `images.json`** — copia a `$OUTDIR/images.json.bak` antes de tocar nada
1. **Confirmación `y/N`** en niveles 3, 4, 5 (omitible con `--yes`)
1. **Detección de contenedores running** — aborta niveles 4+ si los hay (excepto `--force`)
1. **Nivel 5 avisa** que necesita `podman system reset` posterior

______________________________________________________________________

## Ejemplos

```sh
# Solo análisis (nivel 0, default)
./scripts/dev/podman_cleanup_linux.sh --analyze

# Limpiar contenedores stopped + imagenes (nivel 2)
./scripts/dev/podman_cleanup_linux.sh -l 2

# Builder prune con confirmación (nivel 3)
./scripts/dev/podman_cleanup_linux.sh -l 3

# System prune nuclear, sin confirmacion, forzado
./scripts/dev/podman_cleanup_linux.sh -l 4 --yes --force

# Storage reset (rm -rf overlay) para storage corrupto
./scripts/dev/podman_cleanup_linux.sh -l 5 --yes

# Podman + Docker, nivel 2
./scripts/dev/podman_cleanup_linux.sh -l 2 --docker

# Monitoreo cada 5 segundos
PODMAN_CLEANUP_INTERVAL=5 ./scripts/dev/podman_cleanup_linux.sh -l 2

# Via just (recomendado)
just podman-cleanup --analyze
just podman-cleanup -l 2
just podman-cleanup -l 4 --yes

# Traer evidencia al local
scp servidor:/tmp/podman-cleanup-*.tar.gz .
tar xzf podman-cleanup-*.tar.gz
cat podman-cleanup-*/REPORTE.md
```

______________________________________________________________________

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-04

**feat:** Script inicial de limpieza de Podman/Docker por niveles.

- 6 niveles (0=análisis a 5=nuclear) con confirmación interactiva en 3+.
- Soporte dual Podman + Docker con auto-detección.
- Monitoreo background de disco, overlay y capas en tiempo real.
- Snapshot antes/después con comparativa en REPORTE.md.
- Backup de `images.json`, detección de contenedores running.
- Empaquetado en `.tar.gz` para transporte vía scp.
