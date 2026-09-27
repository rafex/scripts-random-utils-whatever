---
title: sync_age_to_thinkpad_unix.sh
description: Sincronización segura de ~/.age desde macOS/Linux hacia ThinkPad
tags:
  - respaldo
  - seguridad
  - age
---

# sync_age_to_thinkpad_unix.sh

Sincroniza el contenido de `~/.age` desde macOS o Linux hacia `~/.age` de una
ThinkPad mediante `rsync` sobre SSH.

- **Ruta:** `scripts/backup/sync_age_to_thinkpad_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `ssh`, `rsync`, `find`, `mktemp`

______________________________________________________________________

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

- `~/.age` debe existir en la máquina de origen y no ser un enlace simbólico.
- El destino SSH debe indicarse siempre con `--target`.
- SSH debe tener una huella ya verificada en `known_hosts`; el script no la
  modifica y usa `StrictHostKeyChecking=yes`.
- El usuario remoto debe tener `rsync`, un `HOME` escribible y no ser `root`.

No se requiere `sudo` en el origen ni en la ThinkPad.

## Uso

Validar sin copiar:

```sh
just sync-age-to-thinkpad --check --target thinkpad
```

Simular la sincronización:

```sh
just sync-age-to-thinkpad --plan --target rafex@192.168.3.91
```

Aplicar la copia:

```sh
just sync-age-to-thinkpad --apply --target thinkpad
```

Consultar un resumen sin mostrar nombres ni contenido:

```sh
just sync-age-to-thinkpad --status --target thinkpad
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--target <destino>` | — | Destino SSH obligatorio; acepta alias o `usuario@host` |
| `--source <directorio>` | — | Origen local; default `~/.age` |
| `--identity <archivo>` | — | Identidad privada SSH opcional |
| `--port <puerto>` | — | Puerto SSH opcional |
| `--check` | — | Valida dependencias y conectividad sin escribir |
| `--plan` | — | Ejecuta `rsync --dry-run` sin modificar archivos |
| `--status` | — | Muestra conteos y tamaños resumidos |
| `--apply` | — | Sincroniza y respalda reemplazos |
| `--help` | `-h` | Muestra la ayuda |

El destino remoto está fijado a `~/.age`; no se aceptan rutas remotas
arbitrarias.

## Variables de entorno

El script no usa variables de entorno administradas para elegir el destino,
la identidad o la contraseña. Deben indicarse mediante argumentos para evitar
que una sesión heredada cambie accidentalmente el destino.

| Variable | Default | Descripción |
|---|---|---|
| `HOME` | Entorno del usuario | Determina el `~/.age` de origen |
| `TMPDIR` | Sistema | Ubicación del temporal interno de `mktemp` |

## Ejemplos

### Forma recomendada con alias SSH

```sh
just sync-age-to-thinkpad --check --target thinkpad
just sync-age-to-thinkpad --apply --target thinkpad
```

### Con IP y usuario explícitos

```sh
just sync-age-to-thinkpad --apply --target rafex@192.168.3.91
```

### Con una clave SSH específica

```sh
just sync-age-to-thinkpad --apply \
  --target rafex@192.168.3.91 \
  --identity ~/.ssh/id_ed25519
```

### Origen alternativo con el mismo nombre `.age`

```sh
just sync-age-to-thinkpad --plan \
  --source /Volumes/Respaldo/.age \
  --target thinkpad
```

## Protecciones de seguridad

- La operación es unidireccional y nunca usa `--delete`.
- Los archivos reemplazados se guardan en:
  `~/.local/share/rafex/age-sync-backups/<fecha>/` del destino.
- Los respaldos remotos se crean con permisos `0700`; archivos y directorios
  sincronizados quedan con permisos privados equivalentes a `0600` y `0700`.
- Se rechazan enlaces simbólicos y archivos especiales dentro del origen.
- Se rechaza un `~/.age` remoto que sea un enlace simbólico.
- `--check`, `--plan` y `--status` no escriben archivos.
- Se usa `BatchMode=yes` para no registrar ni solicitar contraseñas dentro del
  script.
- La salida no enumera archivos, claves, tokens ni contenido.
- El script no toca `known_hosts`, claves SSH, `sudo`, ADB, Podman ni servicios.

Los respaldos se conservan para recuperación manual. No existe una acción de
rollback automática para evitar restaurar claves privadas por accidente.

## Fallos conocidos

### `no se pudo validar SSH, rsync remoto, HOME o ~/.age en el destino`

**Causa:** el host no está accesible en modo no interactivo, la huella SSH no
está verificada, falta `rsync`, el usuario remoto es `root` o su `HOME` no es
escribible.

**Solución:** prueba `ssh <destino>`, verifica la huella manualmente e instala
`rsync` en ambas máquinas con el gestor de paquetes correspondiente.

### `el origen contiene enlaces simbólicos`

**Causa:** las claves podrían salir del árbol esperado o cambiar de origen de
forma inesperada.

**Solución:** reemplaza los enlaces por archivos reales dentro de `~/.age` y
repite `--check`.

### `rsync no pudo completar la operación`

**Causa:** se perdió SSH, no hay permisos de escritura o el destino remoto
rechazó una ruta.

**Solución:** ejecuta primero `--plan`; revisa solo el estado resumido con
`--status` y confirma que el usuario remoto puede escribir en su HOME.

## Changelog

### [Unreleased]

- **feat:** agregar sincronización unidireccional segura de `~/.age` mediante
  `rsync` sobre SSH con respaldo remoto fechado.
