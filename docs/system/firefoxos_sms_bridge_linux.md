---
title: firefoxos_sms_bridge_linux.sh
description: Administra una cola SMS autenticada entre la ThinkPad y un Firefox OS Flame.
tags:
  - sistema
  - firefox-os
  - sms
  - podman
---

# firefoxos_sms_bridge_linux.sh

Expone una cola local para que una aplicación hospedada en el Flame presente
los mensajes en Mensajes. El envío final siempre se confirma manualmente en el
teléfono.

- **Ruta:** `scripts/system/firefoxos_sms_bridge_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `python3`, `podman`, `ip`; aplicación y publicador versionados en el repositorio

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

Instala primero:

```bash
just install-firefoxos-sms-bridge --apply
```

La configuración fija los siguientes listeners:

| Servicio | Dirección | Uso |
|---|---|---|
| Consola | `127.0.0.1:8786` | Crear mensajes, emparejar, consultar historial y revocar. |
| Flame | `192.168.3.91:8787` | Instalar/usar la aplicación y consultar la cola autenticada. |

La ThinkPad y el Flame deben estar en la misma red autorizada. El Flame debe
tener conectividad HTTP hacia `192.168.3.91`.

## Uso

Iniciar el publicador rootless:

```bash
just firefoxos-sms --serve-podman
just firefoxos-sms --status
```

Abrir en el Flame:

```text
http://192.168.3.91:8787/install.html
```

Instalar y abrir la aplicación. Generar un código de emparejamiento desde la
ThinkPad:

```bash
just firefoxos-sms --pair
```

Introducir el código de un solo uso en la aplicación del Flame. Para crear un
SMS desde la ThinkPad:

```bash
just firefoxos-sms --enqueue \
  --to +5255XXXXXXX \
  --body "Mensaje de prueba"
```

La aplicación consulta cada cinco segundos mientras está abierta. Al pulsar
**Abrir en Mensajes**, se precargan destinatario y texto; el usuario debe
confirmar el envío dentro de Mensajes.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida aplicación, publicador, red y Podman sin iniciar nada. |
| `--plan` | `--dry-run` | Muestra contenedor, listeners y estado previsto sin modificar nada. |
| `--serve-podman` | `--serve` | Construye si hace falta e inicia el contenedor administrado rootless. |
| `--stop` | `--stop-podman` | Detiene únicamente el contenedor administrado. |
| `--status` | — | Muestra el estado del contenedor sin revelar tokens ni mensajes. |
| `--pair` | — | Genera un código temporal de emparejamiento. |
| `--revoke` | — | Revoca el token del Flame. |
| `--enqueue` | — | Agrega un mensaje; requiere `--to` y `--body`. |
| `--to <número>` | — | Destinatario E.164, por ejemplo `+5255XXXXXXX`. |
| `--body <texto>` | — | Texto de un solo segmento SMS. |
| `--request-id <id>` | — | Identificador idempotente opcional para evitar duplicados. |
| `--history` | — | Muestra el historial local al usuario de la ThinkPad. |
| `--purge` | — | Retira entradas que ya superaron la retención de 30 días. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_DATA_HOME` | `~/.local/share` | Base del estado privado del puente. |
| `PATH` | Rutas del sistema | Se anteponen rutas estándar para Podman, Python e `ip`. |

No se leen archivos `.env` ni se aceptan tokens mediante variables de entorno.
Los puertos y la IP se mantienen deliberadamente fijos en esta primera versión
para que la regla de firewall sea explícita.

## Ejemplos

### Forma explícita/recomendada

```bash
just firefoxos-sms --check
just firefoxos-sms --plan
just firefoxos-sms --serve-podman
just firefoxos-sms --status
```

### Emparejar y enviar

```bash
just firefoxos-sms --pair
just firefoxos-sms --enqueue --to +5255XXXXXXX --body "Hola desde Rafex"
```

### Consola web local

Abre en la ThinkPad:

```text
http://127.0.0.1:8786/
```

La consola permite agregar mensajes y consultar el historial. Nunca escucha
en la IP LAN.

### Retirar el acceso

```bash
just firefoxos-sms --revoke
just firefoxos-sms --stop
```

## Protecciones de seguridad

- La cola acepta únicamente números E.164 y un solo segmento SMS.
- GSM-7 se limita a 160 unidades; Unicode se limita a 70 caracteres.
- Solo puede existir un mensaje `queued`; los nuevos se rechazan hasta procesar el anterior.
- El historial se conserva localmente 30 días dentro de un directorio `0700`.
- El código dura 10 minutos, es de un solo uso y admite cinco intentos.
- El token se almacena únicamente como hash y puede revocarse.
- Los endpoints administrativos solo están publicados en loopback.
- El contenedor usa Podman rootless, sistema de archivos de solo lectura,
  capacidades descartadas, sin privilegios nuevos, límite de memoria y PID.
- No se registran números, textos, tokens, cookies ni credenciales.
- No se usa ADB, `adb shell`, ADB por red, `sudo`, comandos del módem ni UFW automático.
- La aplicación Flame no declara permiso `sms` ni tipo privilegiado.
- `presented` solo significa que se abrió Mensajes; no significa que el SMS
  fue enviado o entregado.

La API SMS directa se mantiene fuera de alcance: las aplicaciones hospedadas no
deben asumir acceso a permisos sensibles de Firefox OS. La aplicación histórica
de Gaia usaba la actividad `websms/sms` para preparar el compositor de Mensajes,
que es el mecanismo adoptado aquí. [Gaia SMS Activity Handler](https://github.com/mozilla-b2g/gaia/blob/v2.5/apps/sms/views/shared/js/activity_handler.js)

## Fallos conocidos

### `el puente no está activo`

**Causa:** se intentó emparejar o encolar antes de iniciar el publicador.

**Solución:** ejecuta `just firefoxos-sms --serve-podman` y verifica con
`just firefoxos-sms --status`.

### `ya existe un contenedor no administrado`

**Causa:** el nombre `rafex-firefoxos-sms` pertenece a otro contenedor.

**Solución:** inspecciona el contenedor manualmente. El helper nunca lo detiene
ni lo reemplaza.

### `el Flame no puede abrir el publicador`

**Causa:** falta una regla UFW, la IP no es accesible o el teléfono no está en
la red autorizada.

**Solución:** aplica manualmente una regla limitada al teléfono:

```bash
sudo ufw allow from IP_DEL_FLAME to any port 8787 proto tcp
```

Retírala al terminar:

```bash
sudo ufw delete allow from IP_DEL_FLAME to any port 8787 proto tcp
```

### `Este Flame no ofrece la actividad histórica de Mensajes`

**Causa:** la aplicación se abrió en un navegador moderno, o la compilación del
Flame no registra la actividad `websms/sms`.

**Solución:** prueba desde la aplicación instalada en el Flame v2.6. Si la
actividad no existe, la cola seguirá siendo consultable, pero no se intentará
enviar SMS directamente ni se añadirá un permiso privilegiado automáticamente.

### `ya existe un mensaje pendiente`

**Causa:** la política FIFO permite solo una entrada `queued`.

**Solución:** abre Mensajes y procesa la entrada, o cancélala desde la
aplicación del Flame antes de encolar otra.

### `el texto supera un segmento SMS`

**Causa:** el texto supera 160 unidades GSM-7 o 70 caracteres Unicode.

**Solución:** acorta el texto. La primera versión no permite concatenación para
evitar cargos inesperados.

## Changelog

### [Unreleased]

- Cambios pendientes de release.

### v1.0.0 — 2026-09-02

- **feat:** añade cola autenticada, publicador Podman rootless y aplicación
  hospedada para preparar SMS en Firefox OS Mensajes.
