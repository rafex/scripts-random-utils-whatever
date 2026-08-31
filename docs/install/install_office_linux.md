---
title: install_office_linux.sh
description: Instala LibreOffice, diccionarios españoles y locale es_MX para la sesión del usuario.
tags:
  - instalación
  - oficina
  - español
---

# install_office_linux.sh

Instala LibreOffice y los paquetes de interfaz, ayuda y diccionarios en
español. Genera `es_MX.UTF-8` si falta y carga el idioma en la sesión del
usuario sin modificar `/etc/default/locale`.

- **Ruta:** `scripts/install/install_office_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, apt-cache, apt-get, dpkg-query, locale-gen; sudo solo durante `--apply`.

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

- Debian con candidatos APT para LibreOffice, traducciones, diccionarios y
  `locales`.
- Usuario normal con sudo para la instalación.

## Uso

```bash
just install-office --check
just install-office --plan --locale es_MX
just install-office --apply --locale es_MX
just install-office --status --locale es_MX
```

Después de aplicar, cierra y abre la sesión para que Bash y las aplicaciones
gráficas hereden el locale.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Consulta paquetes y locale sin modificar. |
| `--plan` | `--dry-run` | Muestra las acciones sin modificar. |
| `--apply` | — | Instala paquetes y configura la sesión. |
| `--status` | — | Muestra el estado actual. |
| `--locale <valor>` | — | Acepta `es_MX`, `es_MX.UTF-8` o `es_MX.utf8`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. El archivo administrado de sesión se
crea en `~/.config/rafex/locale.conf`.

## Ejemplos

```bash
just install-office --apply --locale es_MX
locale
libreoffice
```

## Protecciones de seguridad

- No modifica `/etc/default/locale`.
- Respalda `/etc/locale.gen` antes de generar el locale cuando existe.
- Respalda `~/.profile` y `~/.config/rafex/locale.conf` antes de reemplazarlos.
- No guarda credenciales ni usa archivos `.env`.
- Deshace un `LC_ALL` heredado únicamente al cargar el bloque administrado del
  perfil, evitando que fuerce mensajes en inglés.

## Fallos conocidos

### `locale es_MX.UTF-8 no generado`

**Causa:** falta el paquete `locales`, el locale no pudo generarse o la sesión
actual conserva un entorno anterior.

**Solución:** repite `--apply`, comprueba `locale -a` y abre una nueva sesión.

### `algún paquete de oficina no tiene candidato APT`

**Causa:** las fuentes Debian no ofrecen uno de los paquetes solicitados.

**Solución:** actualiza índices y revisa la versión de Debian sin añadir
repositorios externos desde este script.

## Changelog

### [Unreleased]

- **feat:** añadir LibreOffice y locale de sesión español.
