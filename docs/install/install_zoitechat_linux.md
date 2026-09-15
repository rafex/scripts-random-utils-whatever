---
title: install_zoitechat_linux.sh
description: Instala ZoiteChat, cliente IRC GTK3 para Debian.
tags:
  - instalación
  - irc
  - gtk
  - thinkpad
---

# install_zoitechat_linux.sh

Instala ZoiteChat desde Debian. Es el sucesor de la línea XChat/HexChat y
ofrece una interfaz GTK3 para conectarse a redes IRC.

- **Ruta:** `scripts/install/install_zoitechat_linux.sh`
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

La ThinkPad debe ejecutar Debian y tener habilitado el repositorio que ofrece
`zoitechat`.

## Uso

```bash
just install-zoitechat --check
just install-zoitechat --plan
just install-zoitechat --apply
just install-zoitechat --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba paquete, candidato y binario sin modificar. |
| `--plan` | — | Muestra la instalación prevista sin modificar. |
| `--apply` | — | Instala `zoitechat` mediante APT. |
| `--status` | — | Muestra el estado instalado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no utiliza variables de entorno ni archivo `.env`.

## Ejemplos

```bash
just install-zoitechat --apply
zoitechat
```

En la configuración de red usa TLS cuando la red IRC lo permita. Para
Freenode se puede probar `irc.freenode.net:6697`; para Libera.Chat,
`irc.libera.chat:6697`.

## Protecciones de seguridad

- Solo instala el paquete desde los repositorios Debian configurados.
- No configura servidores, canales ni contraseñas.
- No inicia ZoiteChat automáticamente.
- Las credenciales deben introducirse únicamente en la aplicación y no deben
  copiarse al repositorio.

## Fallos conocidos

### `paquete no instalado`

**Causa:** todavía no se ejecutó `--apply` o el repositorio no ofrece el
paquete.

**Solución:** confirma el candidato con `--check` y revisa APT antes de usar
`--apply`.

### `no se puede conectar al servidor IRC`

**Causa:** servidor, puerto, TLS, DNS o firewall incorrectos.

**Solución:** usa el nombre oficial de la red, puerto TLS `6697`, y prueba la
conectividad sin introducir credenciales en comandos o logs.

## Changelog

### [Unreleased]

- **feat:** añadir instalador independiente de ZoiteChat para la ThinkPad.
