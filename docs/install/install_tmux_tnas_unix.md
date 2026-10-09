---
title: install_tmux_tnas_unix.sh
description: Compila tmux estático para el TNAS ARM64 en Podman remoto e instala en el home de admin.
tags:
  - instalación
  - TNAS
  - tmux
  - Podman
---

# install_tmux_tnas_unix.sh

Compila tmux 3.7c como binario estático para Linux ARM64, usando una conexión
Podman remota, y puede instalarlo en `/home/admin/bin` del TerraMaster sin
modificar los paquetes ni rutas del sistema.

- **Ruta:** `scripts/install/install_tmux_tnas_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `podman`, `ssh`, `scp`, `mktemp`, `install`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Tener una conexión Podman remota seleccionada; por defecto usa `debian-server-wifi`.
- El servidor Podman debe poder ejecutar imágenes ARM64 mediante emulación.
- Tener acceso SSH por clave o contraseña al TNAS con usuario `admin`.
- El script descarga fuentes fijadas de tmux, libevent y ncurses y valida sus SHA-256.

## Uso

Desde la raíz del repositorio:

```bash
just build-tmux-tnas
just install-tmux-tnas
```

El primer comando deja el binario en `dist/tmux-3.7c-linux-arm64`. El segundo
lo recompila, lo copia a `/home/admin/bin/tmux` y conserva una copia de
respaldo si ya existía un binario en esa ruta.

Para una sesión remota reconectable:

```bash
ssh -p 9222 admin@192.168.3.56
/home/admin/bin/tmux new -s discoExterno2
```

Dentro de tmux, inicia el script de copia. Desconecta SSH normalmente y luego
vuelve a adjuntarte con:

```bash
/home/admin/bin/tmux attach -t discoExterno2
```

La sesión resiste la desconexión de SSH, pero termina si el TNAS se reinicia o
pierde alimentación.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--build` | — | Compila y guarda el binario localmente en `dist/`. Es la acción predeterminada. |
| `--install` | — | Compila y luego instala el binario en el home de `admin` del TNAS. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Las variables de entorno permiten cambiar la conexión, el destino SSH y el
directorio local del artefacto; no se leen archivos `.env`.

| Variable | Default | Descripción |
|---|---|---|
| `PODMAN_CONNECTION` | `debian-server-wifi` | Nombre de la conexión Podman remota. |
| `TNAS_SSH_TARGET` | `admin@192.168.3.56` | Usuario y host para la instalación remota. |
| `TNAS_SSH_PORT` | `9222` | Puerto SSH del TNAS. |
| `TMUX_TNAS_OUTPUT_DIR` | `dist/` en el repo | Carpeta local donde se escribe el binario compilado. |
| `TMPDIR` | `/tmp` | Directorio temporal local. |

## Ejemplos

### Forma recomendada

```bash
just build-tmux-tnas
just install-tmux-tnas
```

### Con una conexión Podman remota distinta

```bash
PODMAN_CONNECTION=debian-server-wifi just build-tmux-tnas
```

### Con otro TNAS

```bash
TNAS_SSH_TARGET=admin@192.168.3.56 TNAS_SSH_PORT=9222 just install-tmux-tnas
```

## Protecciones de seguridad

- Usa tmux 3.7c, libevent 2.1.12 y ncurses 6.5 con checksums fijados.
- Construye para ARM64 dentro del Podman remoto y verifica versión y enlace estático.
- Instala únicamente en `/home/admin/bin`; no modifica TOS ni paquetes `opkg`.
- Sube primero a un nombre temporal y reemplaza el binario de forma atómica; conserva respaldo previo.
- No borra ni modifica datos de usuario.

## Fallos conocidos

### `no está disponible la conexión Podman`

**Causa:** el nombre de conexión configurado no existe o el servidor remoto está apagado.

**Solución:** revisa `podman system connection list` y define `PODMAN_CONNECTION` con la conexión remota activa.

### `la compilación no produjo un binario` o falla de ejecución ARM64

**Causa:** el Podman remoto no tiene emulación ARM64 habilitada o falló la compilación de una dependencia.

**Solución:** conserva el registro del error, revisa que el servidor pueda ejecutar una imagen `--arch arm64` y vuelve a compilar.

### `Permission denied` al instalar en el TNAS

**Causa:** el usuario SSH no puede escribir en `/home/admin/bin`.

**Solución:** ejecuta la instalación con la cuenta `admin` propietaria de ese directorio; el script no usa `sudo`.

## Changelog

### [Unreleased]

- Preparado para compilar e instalar tmux estático en el TNAS.

### v1.0.0 — 2026-10-08

**feat:** agregar compilación ARM64 de tmux con Podman remoto.

- Añade instalación aislada en el home del usuario `admin`.
- Documenta sesiones persistentes para tareas largas.
