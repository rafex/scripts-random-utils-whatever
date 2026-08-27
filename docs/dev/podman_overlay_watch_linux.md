---
title: podman_overlay_watch_linux.sh
description: Monitorización del almacenamiento overlay de Podman
tags:
  - contenedores
---

# podman_overlay_watch_linux.sh

Monitor del tamaño del overlay de Podman. Cuando supera un threshold (150GB por defecto) o el disco está > 85%, ejecuta `podman builder prune -af` automáticamente para evitar que el disco se llene. Soporta modo watch continuo, oneshot (para systemd timer / cron) y auto-instalación de timer systemd --user.

- **Ruta:** `scripts/dev/podman_overlay_watch_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `podman`, `du`, `df`, `bc`, `systemctl --user` (para `--install-timer`)
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Triggers de limpieza](#triggers-de-limpieza)
- [Modos de operación](#modos-de-operacion)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [systemd timer](#systemd-timer)
- [Log persistente](#log-persistente)
- [Ejemplos](#ejemplos)

> **Forma recomendada:** instalar el timer con `just podman-overlay-watch --install-timer`.

______________________________________________________________________

## Requisitos

- Linux
- Podman instalado (`podman builder prune`)
- `du`, `df`, `bc`
- `systemctl --user` para `--install-timer`

______________________________________________________________________

## Triggers de limpieza

El script ejecuta `podman builder prune -af` cuando se cumple **cualquiera** de estos:

| Trigger | Check | Default |
|---|---|---|
| **Primario:** overlay size | `du -sb ~/.local/share/containers/storage/overlay` | > 150GB |
| **Secundario:** disco lleno | `df -h /` (instantáneo) | > 85% |

El trigger secundario (disco) es un check rápido instantáneo con `df`. Sirve como red de seguridad cuando el disco se llena por otras razones.

______________________________________________________________________

## Modos de operación

| Modo | Flag | Descripción | Uso típico |
|---|---|---|---|
| **Watch** | `--watch` (default) | Bucle continuo: check cada N seg | Background process |
| **Oneshot** | `--oneshot` | Check único, limpia si supera threshold, sale | systemd timer / cron |
| **Install timer** | `--install-timer` | Instala units systemd --user | Setup inicial |
| **Uninstall timer** | `--uninstall-timer` | Elimina units systemd | Limpieza |

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
# Instalar timer systemd (cada 30 min)
just podman-overlay-watch --install-timer

# Check único
just podman-overlay-watch --oneshot

# Watch continuo
just podman-overlay-watch --watch
```

### Directamente

```sh
./scripts/dev/podman_overlay_watch_linux.sh [opciones]
```

El script **no requiere sudo** (opera con podman rootless y systemctl --user).

### Resultado (cuando se ejecuta prune)

El script crea evidencia solo cuando se dispara el prune:

- `/tmp/podman-overlay-watch-<timestamp>/` — snapshot antes/después + output del prune
- `REPORTE.md` — análisis con espacio liberado
- `/tmp/podman-overlay-watch-<timestamp>.tar.gz` — para transporte

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--watch` | | Monitor continuo (default) |
| `--oneshot` | | Check único, sale (para timer/cron) |
| `--install-timer` | | Instala timer systemd --user (cada 30 min) |
| `--uninstall-timer` | | Desinstala timer systemd |
| `--threshold <GB>` | `-t` | Umbral overlay en GB (default: 150) |
| `--disk-pct <%>` | `-d` | Trigger secundario: disco > P% (default: 85) |
| `--interval <seg>` | `-i` | Intervalo check modo watch (default: 300s = 5min) |
| `--prune-cmd <cmd>` | | Comando prune custom (default: `podman builder prune -af`) |
| `--dry-run` | | Reportar pero no ejecutar prune |
| `--log <archivo>` | | Log persistente (default: `~/.local/share/podman-overlay-watch.log`) |
| `--output <dir>` | `-o` | Directorio de salida para evidencia |
| `--help` | `-h` | Ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `PODMAN_OVERLAY_THRESHOLD` | `150` | Umbral overlay GB |
| `PODMAN_OVERLAY_DISK_PCT` | `85` | Trigger disco % |
| `PODMAN_OVERLAY_INTERVAL` | `300` | Intervalo seg (watch) |
| `PODMAN_OVERLAY_PRUNE_CMD` | `podman builder prune -af` | Comando prune |
| `PODMAN_OVERLAY_LOG` | `~/.local/share/podman-overlay-watch.log` | Log persistente |
| `PODMAN_OVERLAY_DRY_RUN` | `0` | Dry run (1=on) |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

______________________________________________________________________

## systemd timer

Con `--install-timer`, el script auto-instala un timer systemd --user:

**Service unit** (`~/.config/systemd/user/podman-overlay-watch.service`):

```ini
[Unit]
Description=Podman overlay size monitor — auto-prune build cache

[Service]
Type=oneshot
ExecStart=%h/.local/bin/podman_overlay_watch_linux.sh --oneshot
```

**Timer unit** (`~/.config/systemd/user/podman-overlay-watch.timer`):

```ini
[Unit]
Description=Run podman overlay monitor every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Unit=podman-overlay-watch.service

[Install]
WantedBy=timers.target
```

El `--install-timer`:

1. Copia el script a `~/.local/bin/podman_overlay_watch_linux.sh`
1. Crea los unit files
1. `systemctl --user daemon-reload`
1. `systemctl --user enable --now podman-overlay-watch.timer`
1. Ejecuta un primer check inmediato

Para verificar:

```sh
systemctl --user status podman-overlay-watch.timer
systemctl --user list-timers
journalctl --user -u podman-overlay-watch
```

Para desinstalar:

```sh
./scripts/dev/podman_overlay_watch_linux.sh --uninstall-timer
```

______________________________________________________________________

## Log persistente

Todas las acciones se registran en `~/.local/share/podman-overlay-watch.log`:

```
[2026-08-04 23:30:00] CHECK  overlay=4.02GB disk=11% status=OK
[2026-08-05 00:00:00] CHECK  overlay=4.12GB disk=11% status=OK
...
[2026-08-15 14:30:00] ALERT overlay=152.3GB > threshold 150GB — ejecutando prune...
[2026-08-15 14:31:15] PRUNE before=152.3GB after=8.1GB freed=144.2GB
```

______________________________________________________________________

## Optimización de rendimiento

El modo watch usa una estrategia de dos niveles para evitar `du -sb` en cada iteración (que puede ser lento en directorios grandes):

| Iteración | Check | Velocidad |
|---|---|---|
| Cada iteración | `df -h /` (disco %) | Instantáneo |
| Cada 10 iteraciones | `du -sb overlay/` (tamaño overlay) | ~30-60s |
| Inmediato | Si `df` muestra disco > 85% | Dispara `du -sb` inmediato |

______________________________________________________________________

## Ejemplos

```sh
# Watch continuo con threshold 100GB
./scripts/dev/podman_overlay_watch_linux.sh --watch -t 100

# Check único dry-run
./scripts/dev/podman_overlay_watch_linux.sh --oneshot --dry-run

# Instalar timer systemd
./scripts/dev/podman_overlay_watch_linux.sh --install-timer

# Watch cada 10 min con comando prune custom
./scripts/dev/podman_overlay_watch_linux.sh --watch -i 600 --prune-cmd "podman image prune -af"

# Via variables de entorno
PODMAN_OVERLAY_THRESHOLD=200 ./scripts/dev/podman_overlay_watch_linux.sh --oneshot

# Via just (recomendado)
just podman-overlay-watch --install-timer
just podman-overlay-watch --oneshot
just podman-overlay-watch --watch -t 100

# Verificar timer
systemctl --user status podman-overlay-watch.timer
systemctl --user list-timers

# Ver logs del timer
journalctl --user -u podman-overlay-watch
cat ~/.local/share/podman-overlay-watch.log
```

______________________________________________________________________

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-04

**feat:** Script inicial de monitor de overlay Podman con auto-prune.

- Trigger primario: overlay > 150GB (configurable).
- Trigger secundario: disco > 85% (instantáneo con df).
- Modos watch continuo y oneshot (para timer/cron).
- Auto-instalación de timer systemd --user.
- Log persistente en `~/.local/share/podman-overlay-watch.log`.
- Evidencia en /tmp solo cuando se dispara el prune.
- Optimización de rendimiento: df instantáneo + du -sb periódico.
