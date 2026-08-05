# podman_recover_linux.sh

Recupera el socket de Podman cuando falla la conexión (systemctl --user). Diagnostica el estado del socket file, las units `podman.socket` y `podman.service`, y la respuesta de `podman --remote info`. Si algo falla, restaura con reintentos y genera `REPORTE.md` con evidencia en `/tmp`.

- **Ruta:** `scripts/dev/podman_recover_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `systemctl --user`, `podman`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Diagnóstico](#diagnostico)
- [Recuperación](#recuperacion)
- [Modo watch](#modo-watch)
- [Ejemplos](#ejemplos)

> **Forma recomendada desde la raíz del repo:** usar `just podman-recover`.

---

## Requisitos

- Linux con `systemd` (--user)
- Podman instalado
- UID 1000 (o configurable: el script detecta el UID automáticamente)
- `loginctl enable-linger` habilitado para que los servicios --user sobrevivan al logout

---

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
# Diagnosticar y recuperar
just podman-recover

# Solo diagnosticar sin tocar nada
just podman-recover --check-only

# Monitor continuo
just podman-recover --watch
```

### Directamente

```sh
./scripts/dev/podman_recover_linux.sh [opciones]
```

El script **no requiere sudo** (opera con `systemctl --user`, rootless).

### Resultado

El script crea:
- `/tmp/podman-recover-<timestamp>/` — directorio con evidencia
- `/tmp/podman-recover-<timestamp>.tar.gz` — tarball para transporte
- `REPORTE.md` — diagnóstico y log de recuperación

---

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--retry <N>` | `-r` | Reintentos (default: 5) |
| `--interval <seg>` | `-i` | Intervalo entre reintentos (default: 2s) |
| `--watch` | | Monitor continuo: verifica y recupera si cae |
| `--check-only` | | Solo diagnosticar, no recuperar |
| `--force-reset` | | `systemctl --user reset-failed` desde el intento 1 |
| `--output <dir>` | `-o` | Directorio de salida (default: autogenerado en /tmp) |
| `--help` | `-h` | Muestra la ayuda |

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `PODMAN_RECOVER_RETRY` | `5` | Reintentos |
| `PODMAN_RECOVER_INTERVAL` | `2` | Intervalo (seg) |
| `PODMAN_RECOVER_WATCH` | `0` | Modo watch (1=on) |
| `PODMAN_RECOVER_OUTPUT` | autogen | Directorio de salida |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

---

## Diagnóstico

El script verifica 4 componentes:

| Componente | Check | Comando |
|---|---|---|
| Socket file | ¿Existe `/run/user/$UID/podman/podman.sock`? | `ls -l` |
| podman.socket | ¿Está active? | `systemctl --user is-active podman.socket` |
| podman.service | ¿Está active? | `systemctl --user is-active podman.service` |
| API response | ¿Responde? | `podman --remote info` |

El diagnóstico se muestra en consola y se guarda en `$OUTDIR/diagnose.txt`.

---

## Recuperación

Si algún componente falla, el script ejecuta el siguiente bucle de recuperación:

```
Intentos 1-3:
  1. systemctl --user restart podman.socket
  2. systemctl --user start podman.service
  3. sleep 2s
  4. Verificar

Intentos 4-5:
  1. systemctl --user reset-failed podman.socket podman.service
  2. systemctl --user restart podman.socket
  3. systemctl --user start podman.service
  4. sleep 2s
  5. Verificar
```

Si falla tras 5 intentos:
- Muestra `journalctl --user -u podman` para diagnóstico
- Sugerencias: `loginctl enable-linger`, `systemctl --user daemon-reexec`, `df -h /run`

Con `--force-reset`, el `reset-failed` se ejecuta desde el intento 1.

---

## Modo watch

Con `--watch`, el script entra en bucle infinito:

```
while true:
    if socket + remote_info OK:
        log "OK"
    else:
        ejecutar recuperacion (5 intentos)
        log resultado
    sleep INTERVAL
```

Útil para dejar corriendo en background en el servidor:

```sh
./scripts/dev/podman_recover_linux.sh --watch --interval 10 &
```

---

## Ejemplos

```sh
# Diagnosticar y recuperar (default)
./scripts/dev/podman_recover_linux.sh

# Solo diagnosticar
./scripts/dev/podman_recover_linux.sh --check-only

# Forzar reset-failed desde el primer intento
./scripts/dev/podman_recover_linux.sh --force-reset

# 10 reintentos, 1s entre cada uno
./scripts/dev/podman_recover_linux.sh -r 10 -i 1

# Monitor continuo cada 10s
./scripts/dev/podman_recover_linux.sh --watch --interval 10

# Via just (recomendado)
just podman-recover
just podman-recover --check-only
just podman-recover --watch

# Traer evidencia al local
scp servidor:/tmp/podman-recover-*.tar.gz .
tar xzf podman-recover-*.tar.gz
cat podman-recover-*/REPORTE.md
```

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-04

**feat:** Script inicial de recuperación de socket Podman.

- Diagnóstico de socket file, podman.socket, podman.service, remote info.
- Recuperación con 5 reintentos y reset-failed escalado.
- Modo watch continuo con verificación y recuperación automática.
- Evidencia en /tmp con REPORTE.md y empaquetado .tar.gz.
