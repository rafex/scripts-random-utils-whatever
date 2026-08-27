---
title: install_ufw_linux.sh
description: Instalar y configurar UFW para SSH, Mosh y servicios LAN opcionales
tags:
  - instalación
  - seguridad
  - red
---

# install_ufw_linux.sh

Instala UFW en Debian y aplica una política de firewall adecuada para una
laptop: entradas denegadas, salidas permitidas, SSH y Mosh habilitados. Los
servicios de desarrollo y streaming se habilitan únicamente con perfiles
opcionales y desde las redes LAN configuradas.

- **Ruta:** `scripts/install/install_ufw_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `dpkg-query`, `sudo`; el script instala `ufw`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Puertos evaluados](#puertos-evaluados)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian con APT y `sudo` configurado para el usuario actual.
- Ejecutar como usuario normal, no como `root`.
- Confirmar que SSH escucha en el puerto esperado antes de activar UFW.
- Para que Mosh funcione, el servidor debe tener instalado `mosh` y el cliente
  debe poder alcanzar el rango UDP `60000:61000`.

## Uso

Diagnóstico sin cambios persistentes:

```sh
just install-ufw --check
```

Revisar el plan predeterminado:

```sh
just install-ufw --plan
```

Aplicar la configuración base:

```sh
just install-ufw --apply
```

Consultar el estado actual:

```sh
just install-ufw --status
sudo ufw status numbered
```

La etapa `--apply` solicita la contraseña únicamente mediante `sudo -v` y
guarda la salida en un log fechado. No guarda la contraseña.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba UFW, política y reglas sin modificar el sistema. |
| `--plan` | `--dry-run` | Muestra los comandos y reglas que se aplicarían. |
| `--apply` | — | Instala UFW y aplica la política y el perfil seleccionado. |
| `--status` | — | Muestra `ufw status verbose`. |
| `--profile <perfil>` | — | Selecciona `base`, `dev`, `media` o `all`; default: `base`. |
| `--lan-only` | — | Restringe SSH y Mosh a las subredes de `UFW_LAN_SUBNETS`. |
| `--log-file <archivo>` | — | Guarda la salida en el archivo indicado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos CLI tienen prioridad sobre el modo por defecto. Las variables
se leen al iniciar el script; no se usan para contraseñas.

| Variable | Default | Descripción |
|---|---|---|
| `UFW_LAN_SUBNETS` | `192.168.0.0/24 192.168.1.0/24 192.168.3.0/24` | Subredes permitidas para perfiles `dev`, `media`, `all` y `--lan-only`. Separadas por espacios. |
| `UFW_INSTALL_LOG_FILE` | vacío | Archivo de log. `--log-file` tiene prioridad. |
| `UFW_INSTALL_LOG_DIR` | `~/.local/state/scripts-random-utils-whatever/logs/` | Directorio de logs automáticos para `--apply`. |

## Ejemplos

### Configuración base recomendada

```sh
just install-ufw --check
just install-ufw --plan
just install-ufw --apply
```

Abre:

- `22/tcp` para SSH.
- `60000:61000/udp` para Mosh.

### Base restringida a la LAN

```sh
just install-ufw --apply --lan-only
```

Esto evita exponer SSH y Mosh fuera de las tres redes privadas configuradas.

### Servicios de desarrollo

```sh
just install-ufw --plan --profile dev
just install-ufw --apply --profile dev
```

Añade `3000/tcp`, `5173/tcp`, `8443/tcp` y `30083/tcp` desde las subredes
LAN. Úsalo solo si realmente ejecutas esos servicios en la ThinkPad.

### Servicios de streaming y OBS

```sh
just install-ufw --apply --profile media
```

Añade `4455/tcp`, `8889/tcp`, `8882/udp` y `9000:9100/udp` desde la LAN.

### Todas las reglas opcionales y log explícito

```sh
UFW_LAN_SUBNETS='192.168.3.0/24 10.0.0.0/24' \
  just install-ufw --apply --profile all \
  --log-file "$HOME/ufw-thinkpad.log"
```

## Puertos evaluados

| Puerto | Uso | Tratamiento |
|---|---|---|
| `22/tcp` | SSH | Base, necesario para administración remota. |
| `60000:61000/udp` | Mosh | Base, necesario para sesiones Mosh. |
| `3000/tcp` | Servidores web de desarrollo | Opcional, LAN. |
| `5173/tcp` | Vite | Opcional, LAN. |
| `8443/tcp` | HTTPS de desarrollo | Opcional, LAN. |
| `30083/tcp` | FHS agent-server | Opcional, LAN; conservar solo si se usa. |
| `4455/tcp` | OBS WebSocket | Opcional, LAN; activar solo si OBS recibe conexiones. |
| `8889/tcp` | MediaMTX WHIP | Opcional, LAN. |
| `8882/udp` | MediaMTX ICE/media | Opcional, LAN. |
| `9000:9100/udp` | Streaming/media | Opcional, LAN. Incluye `9000/udp`; no se añade una regla duplicada. |

No se necesitan reglas entrantes para navegación web, actualizaciones, Git,
Firefox, VSCodium, Eclipse, Podman rootless, Bluetooth, audio, cámara o USB.
Esos usos normalmente generan conexiones salientes o se gestionan localmente.

## Protecciones de seguridad

- La política es `deny incoming`, `allow outgoing` y `deny routed`.
- UFW se habilita después de instalar y añadir primero SSH/Mosh.
- Los perfiles `dev` y `media` solo permiten las subredes de `UFW_LAN_SUBNETS`.
- No borra reglas existentes: únicamente añade las que faltan.
- No abre `9000/udp` por separado porque ya está incluido en `9000:9100/udp`.
- `--check` y `--plan` no realizan cambios persistentes por defecto.
- Antes de reemplazar nada no se modifican particiones, `fstab`, GRUB ni
  archivos de contraseñas.
- Si una ejecución `--apply` falla, se conserva toda la salida para diagnóstico
  en el log indicado.

## Fallos conocidos

### `ufw: command not found`

**Causa:** UFW aún no está instalado.
**Solución:** ejecutar `just install-ufw --apply`.

### Se pierde la sesión SSH después de activar UFW

**Causa:** el servicio SSH utiliza otro puerto o una regla previa no coincide.
**Solución:** desde la consola local, comprobar `sudo ss -lntp`, añadir el puerto
  real con `sudo ufw allow <puerto>/tcp` y revisar `sudo ufw status numbered`.

### Mosh conecta por SSH pero no mantiene la sesión

**Causa:** el rango UDP de Mosh está bloqueado o el servidor usa un rango
  personalizado.
**Solución:** comprobar `60000:61000/udp`, revisar la configuración del servidor
  Mosh y confirmar que la red intermedia permite UDP.

### Un servicio de desarrollo no es accesible

**Causa:** se aplicó el perfil `base` o el servicio escucha solo en `127.0.0.1`.
**Solución:** activar el perfil correspondiente (`dev` o `media`) y verificar
  con `ss -lntup` que el servicio escucha en una dirección alcanzable.

## Changelog

### [Unreleased]

- **feat:** añadir instalador UFW con perfiles base, desarrollo y media.
- **security:** limitar los puertos opcionales a subredes LAN y mantener por
  defecto el acceso entrante denegado.

