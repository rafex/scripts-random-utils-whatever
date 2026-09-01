---
title: age_file_linux.sh
description: Cifrado y descifrado de archivos con age
tags:
  - seguridad
  - cifrado
---

# age_file_linux.sh

Cifra o descifra archivos con `age` usando recipients o identidades explícitas.
Las frases de paso se solicitan de forma interactiva y no se pasan en la línea
de comandos.

- **Ruta:** `scripts/system/age_file_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `age`, `mktemp`, `mv`, `chmod`, `readlink`

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

- Ejecutar `just install-age-gopass --apply` previamente.
- La entrada debe ser un archivo regular legible.
- El directorio de salida debe existir.
- Las salidas se limitan a `HOME` o `/tmp` y no se siguen enlaces simbólicos.

## Uso

Comprobar que age está instalado:

```sh
just age-file --check
```

Planificar un cifrado con un recipient age:

```sh
just age-file --plan --encrypt --input archivo.txt \
  --output archivo.txt.age --recipient age1...
```

Cifrar con un recipient SSH, por ejemplo la clave pública existente:

```sh
just age-file --encrypt --input archivo.txt --output archivo.txt.age \
  --ssh-recipient ~/.ssh/id_ed25519.pub
```

Descifrar con la identidad correspondiente:

```sh
just age-file --decrypt --input archivo.txt.age --output archivo.txt \
  --identity ~/.config/age/keys.txt
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba que `age` esté disponible |
| `--plan` | `--dry-run` | Valida la operación y no escribe la salida |
| `--encrypt` | — | Cifra la entrada |
| `--decrypt` | — | Descifra la entrada |
| `--input <archivo>` | — | Archivo de entrada |
| `--output <archivo>` | `-o` | Archivo de salida bajo `HOME` o `/tmp` |
| `--recipient <id>` | `-r` | Recipient nativo age; se puede repetir |
| `--ssh-recipient <archivo>` | `-R` | Archivo de clave pública SSH; se puede repetir |
| `--identity <archivo>` | `-i` | Identidad age para descifrar; se puede repetir |
| `--passphrase` | `-p` | Cifra solicitando una frase de paso interactiva |
| `--force` | — | Permite reemplazar una salida existente |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso | Prioridad |
|---|---|---|
| `HOME` | Define el límite de rutas de salida permitidas | Entorno del usuario |
| `TMPDIR` | Puede influir en temporales internos de age | Entorno del proceso |

No se admiten frases de paso, recipients privados ni identidades por variables
de entorno administradas por el helper.

## Ejemplos

### Forma explícita recomendada con clave pública SSH

```sh
just age-file --encrypt --input ~/.config/app/config.yml \
  --output ~/.config/app/config.yml.age \
  --ssh-recipient ~/.ssh/id_ed25519.pub
```

### Con recipient age nativo

```sh
just age-file --encrypt --input secreto.txt --output secreto.txt.age \
  --recipient age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Con frase de paso interactiva

```sh
just age-file --encrypt --input notas.txt --output notas.txt.age --passphrase
```

### Descifrado y reemplazo explícito

```sh
just age-file --decrypt --input notas.txt.age --output notas.txt \
  --identity ~/.config/age/keys.txt --force
```

## Protecciones de seguridad

- Nunca acepta la frase de paso como valor de argumento.
- Usa un temporal en el mismo directorio de salida y lo mueve atómicamente.
- Establece permisos `0600` en la salida.
- No reemplaza salidas existentes salvo con `--force` explícito.
- Rechaza salidas que sean enlaces simbólicos y evita escribir sobre el mismo
  archivo de entrada.
- No imprime el contenido de la entrada, salida, identidad o secreto.
- Para compartir un archivo, conserva de forma independiente la identidad
  privada; solo el recipient público debe distribuirse.

## Fallos conocidos

### `la salida debe estar bajo HOME o /tmp`

**Causa:** la protección evita que el helper sobrescriba rutas del sistema.

**Solución:** elige una salida dentro de tu directorio personal o `/tmp` y
muévela manualmente con una operación consciente si hace falta.

### `cifrado requiere --recipient ... o --passphrase`

**Causa:** age necesita al menos un destinatario o cifrado simétrico.

**Solución:** usa `--recipient`, `--ssh-recipient` o `--passphrase`.

### Error al descifrar

**Causa:** falta la identidad privada correcta o la frase de paso no coincide.

**Solución:** verifica la identidad local; nunca sustituyas una clave privada
por una pública ni la pegues en un issue, log o repositorio.

## Changelog

### [Unreleased]

- **feat:** añadir wrapper seguro para operaciones de age sobre archivos.
