---
title: install_tigervnc_viewer_linux.sh
description: Instala el cliente VNC TigerVNC desde Debian.
tags:
  - instalación
  - vnc
  - thinkpad
---

# install_tigervnc_viewer_linux.sh

Instala el cliente VNC de TigerVNC para conectarse a escritorios remotos. No
instala ni habilita un servidor VNC y no abre puertos.

- **Ruta:** `scripts/install/install_tigervnc_viewer_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `apt`, `dpkg`, `sudo` solo durante `--apply`

---

## Índice

## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

La ThinkPad debe ejecutar Debian y tener habilitados los repositorios que
contengan `tigervnc-viewer`.

## Uso

```bash
just install-tigervnc-viewer --check
just install-tigervnc-viewer --plan
just install-tigervnc-viewer --apply
just install-tigervnc-viewer --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquete, candidato y binario sin modificar. |
| `--plan` | — | Muestra la instalación prevista sin modificar. |
| `--apply` | — | Instala `tigervnc-viewer` mediante APT. |
| `--status` | — | Muestra el estado instalado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no utiliza variables de entorno ni archivo `.env`.

## Ejemplos

```bash
just install-tigervnc-viewer --apply
vncviewer HOST:5900
```

Para una conexión TLS o con autenticación, usa las opciones disponibles en
`vncviewer` y confirma la configuración del servidor remoto.

## Protecciones de seguridad

- Solo instala el paquete cliente mediante APT.
- No inicia `vncserver`, no habilita servicios y no modifica UFW.
- No ejecuta conexiones automáticamente.

## Fallos conocidos

### `paquete no instalado`

**Causa:** todavía no se ejecutó `--apply` o el repositorio no ofrece el
paquete.

**Solución:** ejecuta `--plan` y revisa la configuración de APT antes de usar
`--apply`.

### `Can't open display`

**Causa:** el cliente se ejecutó fuera de una sesión gráfica X11.

**Solución:** ejecútalo desde la sesión i3/Openbox local o configura un
`DISPLAY` válido.

## Changelog

### [Unreleased]

- **feat:** añadir instalador independiente del cliente TigerVNC para la
  ThinkPad.
