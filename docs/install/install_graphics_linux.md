---
title: install_graphics_linux.sh
description: Instala GIMP y Krita con soporte de ayuda y localización española en Debian.
tags:
  - instalación
  - gráficos
  - thinkpad
---

# install_graphics_linux.sh

Instala las herramientas gráficas opcionales del perfil ThinkPad: GIMP, su
ayuda en español, Krita y su localización.

- **Ruta:** `scripts/install/install_graphics_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query; sudo solo durante `--apply`.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian con índices APT y candidatos para `gimp`, `gimp-help-es`, `krita` y
  `krita-l10n`.
- Ejecutar como usuario normal con permiso para usar sudo en `--apply`.

## Uso

```bash
just install-graphics --check
just install-graphics --plan
just install-graphics --apply
just install-graphics --status
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra paquetes, candidatos y comandos sin modificar. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin modificar. |
| `--apply` | — | Instala los paquetes desde Debian usando sudo. |
| `--status` | — | Consulta el estado actual. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. Calcula el idioma y las rutas mediante
la sesión actual y APT.

## Ejemplos

```bash
just install-graphics --check
just install-graphics --apply
```

## Fallos conocidos

### `algún paquete gráfico no tiene candidato APT`

**Causa:** las fuentes Debian no están habilitadas o los índices están
desactualizados.

**Solución:** revisa las fuentes, ejecuta de nuevo `--apply` y no añadas
repositorios de terceros desde este script.

## Changelog

### [Unreleased]

- **feat:** añadir instalación reproducible de GIMP y Krita.
