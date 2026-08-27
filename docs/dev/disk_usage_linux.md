---
title: disk_usage_linux.sh
description: Diagnóstico del uso de disco en Linux
tags:
  - desarrollo
---

# disk_usage_linux.sh

Diagnóstico rápido de uso de disco. Identifica qué está llenando el disco con sudo, genera evidencia en `/tmp` y un `REPORTE.md` con análisis automático y recomendaciones de limpieza.

- **Ruta:** `scripts/dev/disk_usage_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `sudo`, `du`, `df`, `journalctl`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Qué recolecta](#que-recolecta)
- [Análisis automático](#analisis-automatico)
- [Ejemplos](#ejemplos)

> **Forma recomendada desde la raíz del repo:** usar `just disk-usage`.

______________________________________________________________________

## Requisitos

- Linux con `sudo` disponible
- `du`, `df`, `find`, `journalctl`, `dpkg-query`
- `docker` o `podman` opcionales (detecta automáticamente)

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
just disk-usage
```

### Directamente

```sh
sudo scripts/dev/disk_usage_linux.sh [opciones]
```

El script requiere `sudo` para leer directorios del sistema (`/var`, `/etc`, `/root`, etc.). Si no se ejecuta como root, muestra error y aborta.

### Resultado

El script crea:

- `/tmp/disk-usage-<timestamp>/` — directorio con evidencia
- `/tmp/disk-usage-<timestamp>.tar.gz` — tarball para transporte
- `REPORTE.md` — análisis automático con semáforo 🔴🟡🟢

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--path <dir>` | `-p` | Raíz a analizar (default: `/`) |
| `--top <N>` | `-n` | Top N archivos/dirs más grandes (default: 20) |
| `--threshold <size>` | `-t` | Tamaño mínimo para listar archivos (default: `100M`) |
| `--deep <n>` | | Niveles de `du` profundo (default: 3) |
| `--old <hours>` | | Antigüedad para archivos viejos en horas (default: 2160 = 90 días) |
| `--output <dir>` | `-o` | Directorio de salida (default: autogenerado en /tmp) |
| `--help` | `-h` | Muestra la ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `DISK_DIAG_PATH` | `/` | Raíz a analizar |
| `DISK_DIAG_TOP` | `20` | Top N archivos/directorios |
| `DISK_DIAG_THRESHOLD` | `100M` | Tamaño mínimo |
| `DISK_DIAG_DEEP` | `3` | Niveles de `du` |
| `DISK_DIAG_OLD` | `2160` | Antigüedad en horas |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

______________________________________________________________________

## Qué recolecta

| Fase | Archivo | Contenido |
|---|---|---|
| 1 | `01-df-h.txt` | `df -h` |
| 1 | `02-df-i.txt` | `df -i` (inodos) |
| 1 | `03-lsblk.txt` | `lsblk` |
| 2 | `04-du-level-{1..3}.txt` | `du -xh -d N /` sorted |
| 3 | `05-large-files.txt` | Archivos > threshold sorted by size |
| 4 | `06-large-logs.txt` | Logs > 50MB en `/var/log` |
| 4 | `07-journal.txt` | `journalctl --disk-usage` |
| 4 | `08-docker.txt` | `docker system df` |
| 4 | `09-podman.txt` | `podman system df` |
| 4 | `10-caches.txt` | `/home/*/.cache`, `/var/cache` |
| 4 | `11-tmp.txt` | `/tmp` y `/var/tmp` |
| 4 | `12-snap-flatpak.txt` | `/snap`, `/var/lib/flatpak` |
| 4 | `13-core-dumps.txt` | Archivos `core*` en el filesystem |
| 4 | `14-old-files.txt` | Archivos > 10M no accedidos en 90+ días |
| 4 | `15-large-packages.txt` | Paquetes Debian más grandes instalados |
| 4 | `16-apt-autoclean.txt` | Simulación de `apt-get autoclean` |

______________________________________________________________________

## Análisis automático

El `REPORTE.md` incluye una tabla de hallazgos con semáforo:

| Check | Lógica | Severidad |
|---|---|---|
| Uso del disco | `> 95%` / `> 85%` | 🔴 / 🟡 |
| Directorio dominante | un solo dir > 50% / > 30% | 🔴 / 🟡 |
| Journal size | > 1G | 🟡 |
| Logs grandes | > 3 archivos | 🟡 |
| Contenedores | presencia de GB | 🟡 |
| Core dumps | cualquier archivo `core*` | 🔴 |
| Archivos antiguos | > 5 archivos de 90+ días | 🟡 |

______________________________________________________________________

## Ejemplos

```sh
# Diagnóstico completo de /
sudo ./scripts/dev/disk_usage_linux.sh

# Solo /var, archivos > 10M, top 30
sudo ./scripts/dev/disk_usage_linux.sh -p /var -t 10M --top 30

# Con variables de entorno
DISK_DIAG_THRESHOLD=500M DIST_DIAG_DEEP=2 sudo ./scripts/dev/disk_usage_linux.sh

# Via just (recomendado)
just disk-usage

# Traer evidencia al local
scp servidor:/tmp/disk-usage-*.tar.gz .
tar xzf disk-usage-*.tar.gz
cat disk-usage-*/REPORTE.md
```

______________________________________________________________________

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-04

**feat:** Script inicial de diagnóstico de uso de disco.

- `du` multinivel, `find` archivos grandes, `df`, logs, journal, docker/podman.
- Análisis automático con semáforo 🔴🟡🟢 en REPORTE.md.
- Recomendaciones de limpieza automáticas al final del reporte.
- Empaquetado en `.tar.gz` para transporte vía scp.
