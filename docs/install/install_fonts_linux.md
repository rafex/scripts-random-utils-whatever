---
title: install_fonts_linux.sh
description: Instala fuentes para web, programación, interfaz y cobertura CJK en Debian.
tags:
  - instalación
  - fuentes
  - programación
---

# install_fonts_linux.sh

Instala fuentes latinas, de interfaz, emoji y programación. `fonts-noto-cjk`
queda separado porque ocupa más espacio y se instala con el perfil `cjk`.

- **Ruta:** `scripts/install/install_fonts_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query, fontconfig; sudo solo durante `--apply`.

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

- Debian con candidatos para el perfil elegido.
- `fontconfig` es opcional para instalar, pero permite refrescar caché y
  validar `fc-match`.

## Uso

```bash
just install-fonts --check --profile web-programming
just install-fonts --plan --profile cjk
just install-fonts --apply --profile web-programming
just install-fonts --apply --profile cjk
just install-fonts --status --profile web-programming
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Consulta paquetes y fuentes resueltas. |
| `--plan` | `--dry-run` | Muestra el plan sin modificar. |
| `--apply` | — | Instala el perfil seleccionado y refresca fontconfig. |
| `--status` | — | Muestra paquetes y familias elegidas por `fc-match`. |
| `--profile <valor>` | — | `web-programming`, `cjk` o `all`; predeterminado `web-programming`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración.

## Ejemplos

```bash
just install-fonts --apply --profile web-programming
fc-match sans
fc-match monospace
just install-fonts --apply --profile cjk
```

## Fallos conocidos

### `alguna fuente no tiene candidato APT`

**Causa:** el paquete no está disponible en las fuentes activas o el índice
APT está desactualizado.

**Solución:** revisa `apt-cache policy <paquete>` y las fuentes Debian. El
perfil CJK puede omitirse si no se necesita.

## Changelog

### [Unreleased]

- **feat:** añadir perfiles de fuentes web/programación y CJK.
