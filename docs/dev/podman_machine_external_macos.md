---
title: podman_machine_external_macos.sh
description: Máquina Podman local con almacenamiento en el NVMe externo
tags:
  - contenedores
  - macos
---

# podman_machine_external_macos.sh

Prepara y administra una máquina Podman local en macOS, guardando la máquina virtual y el almacenamiento de imágenes y contenedores en el volumen externo `apfs_ext_1tb`.

- **Ruta:** `scripts/dev/podman_machine_external_macos.sh`
- **SO requerido:** macOS
- **Dependencias:** `bash`, `podman`, `diskutil`

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

- macOS con Podman instalado y disponible en `PATH`.
- Volumen APFS llamado `apfs_ext_1tb` montado y escribible en `/Volumes/apfs_ext_1tb`.
- Arquitectura y memoria suficientes para ejecutar una máquina con 6 CPU y 8 GiB de RAM.
- Aproximadamente 180 GB de capacidad virtual máxima para el disco de Podman (168 GiB en la unidad que usa Podman).

Podman ejecuta contenedores Linux dentro de una máquina virtual en macOS. Este script configura el proveedor Apple Hypervisor (`applehv`).

## Uso

Desde la raíz del repositorio:

```bash
just podman-machine-ext setup
just podman-machine-ext status
just podman-machine-ext stop
just podman-machine-ext start
```

También se puede ejecutar directamente con Bash:

```bash
bash scripts/dev/podman_machine_external_macos.sh setup
```

La máquina se llama `podman-apfs-ext-1tb`. Tras `setup` o `start`, su conexión será la predeterminada de Podman. El resto de las conexiones remotas se conserva y puede elegirse de forma explícita con `podman system connection default <nombre>`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `setup` | — | Prepara el almacenamiento externo, crea la máquina si no existe, la inicia y selecciona su conexión como predeterminada. |
| `start` | — | Inicia la máquina existente y vuelve a seleccionar su conexión como predeterminada. |
| `stop` | — | Detiene la máquina local. Requiere que el volumen siga montado. |
| `status` | — | Muestra el volumen, los enlaces, las máquinas y las conexiones. |
| `--help` | `-h` | Muestra la ayuda. |

La máquina se crea con 6 CPU, 8192 MiB de RAM y un disco virtual máximo de 168 GiB. Después de crearla, los recursos pueden ajustarse con `podman machine set`.

## Variables de entorno

| Variable | Descripción | Prioridad |
|---|---|---|
| `XDG_CONFIG_HOME` | Raíz donde Podman guarda su configuración; por defecto `$HOME/.config`. El subdirectorio `containers/podman/machine` se enlaza al NVMe. | Define la ruta de configuración usada por Podman. |
| `XDG_DATA_HOME` | Raíz donde Podman guarda datos; por defecto `$HOME/.local/share`. El subdirectorio `containers/podman/machine` se enlaza al NVMe. | Define la ruta de datos usada por Podman. |

El script no usa archivo `.env`. No ofrece argumentos CLI para cambiar el nombre del volumen, el punto de montaje ni el tamaño de disco.

## Ejemplos

**Forma recomendada, desde la raíz del repositorio:**

```bash
just podman-machine-ext setup
podman info
podman images
```

**Administrar la máquina directamente:**

```bash
bash scripts/dev/podman_machine_external_macos.sh status
bash scripts/dev/podman_machine_external_macos.sh stop
bash scripts/dev/podman_machine_external_macos.sh start
```

**Elegir una conexión remota conservada:**

```bash
podman system connection default bastion-tunnel
```

Para volver a la máquina local, ejecuta `just podman-machine-ext start`.

## Protecciones de seguridad

- `setup`, `start` y `stop` validan que `/Volumes/apfs_ext_1tb` corresponda al volumen APFS esperado; las operaciones de escritura también prueban que sea escribible.
- `setup` y `start` fallan si el volumen no está disponible. No continúan usando almacenamiento interno.
- `setup` conserva en el NVMe los directorios de máquina que ya existan en las rutas XDG. Si encuentra una máquina registrada, enlaces distintos o datos simultáneos en origen y destino, se detiene sin moverlos.
- El script no borra máquinas, imágenes, contenedores ni conexiones remotas.
- Desconectar el NVMe mientras la máquina esté activa puede interrumpir escrituras. Detén la máquina antes de expulsar el volumen.

## Fallos conocidos

### `el volumen apfs_ext_1tb no está montado`

**Causa:** el NVMe no está montado en `/Volumes/apfs_ext_1tb`.
**Solución:** conecta y monta el volumen con ese nombre antes de ejecutar `setup` o `start`.

### `hay máquinas Podman registradas`

**Causa:** Podman detecta otra máquina y el script no puede mover el directorio compartido sin arriesgar sus datos.
**Solución:** revisa `podman machine list`, detén y respalda la máquina afectada, y configura manualmente el almacenamiento antes de volver a ejecutar el script.

### `existen tanto ... como ...`

**Causa:** ya hay datos en la ruta interna y en la ruta externa que el script necesita enlazar.
**Solución:** compara y respalda ambos directorios; no borres ninguno hasta confirmar cuál contiene la configuración vigente.

### `el volumen apfs_ext_1tb no permite escritura`

**Causa:** el usuario no tiene permiso de escritura o el volumen está montado como solo lectura.
**Solución:** revisa los permisos y el estado del volumen en Utilidad de Discos.

### `la máquina ... no quedó disponible para Podman`

**Causa:** `podman machine start` puede informar que inició aunque el sistema invitado falle durante el arranque. En esta Mac con Podman 6.1.3 y `applehv`, el log mostró `ignition-files.service` fallando al crear el usuario `core` (`useradd: cannot lock /etc/group`) y la VM entró en modo de emergencia. Hay un reporte upstream de Podman con un fallo de arranque Apple Silicon/AppleHV similar, que también deja `LAST UP: Never`: [issue #28439](https://github.com/containers/podman/issues/28439).
**Solución:** revisa el log en `${TMPDIR:-/tmp}/podman/podman-apfs-ext-1tb.log` y la versión instalada de Podman/macOS. El script comprueba la conexión al motor y devuelve error si el invitado no está listo. No borres la VM ni el caché hasta respaldar los datos del NVMe.

## Changelog

### [Unreleased]
- `feat`: añadir administración de una máquina Podman local en el NVMe externo.
