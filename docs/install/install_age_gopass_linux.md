---
title: install_age_gopass_linux.sh
description: Instalación de age y gopass con backend age opcional
tags:
  - instalación
  - seguridad
---

# install_age_gopass_linux.sh

Instala `age` desde Debian y el `gopass` oficial desde su repositorio firmado.
La instalación no inicializa el almacén ni crea credenciales automáticamente.

- **Ruta:** `scripts/install/install_age_gopass_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `apt-cache`, `curl`, `gpg`, `sudo`

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

- Debian o un derivado compatible con APT.
- `sudo` configurado para instalar paquetes y la fuente APT.
- Conectividad HTTPS a Debian y `packages.gopass.pw`.
- Una sesión gráfica o `pinentry` funcional si después se inicializa gopass.

El instalador utiliza la fuente APT oficial documentada por gopass:
<https://github.com/gopasspw/gopass/blob/master/docs/setup.md>.

El backend age de gopass está documentado como experimental y su formato en
disco puede cambiar:
<https://github.com/gopasspw/gopass/blob/master/docs/backends/age.md>.

## Uso

Comprobar el estado sin modificar nada:

```sh
just install-age-gopass --check
```

Ver las acciones previstas:

```sh
just install-age-gopass --plan
```

Instalar `age` y gopass:

```sh
just install-age-gopass --apply
```

Consultar instalación, fuente y almacén sin listar secretos:

```sh
just install-age-gopass --status
```

Inicializar explícitamente un almacén nuevo con age:

```sh
just init-gopass-age
```

El último comando es interactivo: gopass creará la identidad age y solicitará
la frase de protección. No la escribas en el repositorio ni en una variable.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Revisa paquetes y estado de la fuente sin escribir |
| `--plan` | `--dry-run` | Muestra la fuente, el pin y paquetes previstos |
| `--apply` | — | Configura el repositorio oficial e instala age/gopass |
| `--status` | — | Muestra versiones y estado, sin mostrar secretos |
| `--init-gopass-age` | `--init` | Inicializa un almacén vacío de forma interactiva |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Uso | Prioridad |
|---|---|---|
| `HOME` | Ubicación por defecto del almacén `~/.password-store` | Entorno del usuario |
| `PASSWORD_STORE_DIR` | Permite seleccionar otro directorio de almacén | Sustituye la ruta derivada de `HOME` |
| `SUDO_*` | Variables gestionadas por sudo | No se usan para guardar secretos |

La frase de protección la solicita gopass mediante su interfaz interactiva.
No se acepta como argumento ni se guarda mediante este script.

## Ejemplos

### Forma explícita recomendada

```sh
just install-age-gopass --apply
just init-gopass-age
```

### Configurar primero y consultar

```sh
just install-age-gopass --check
just install-age-gopass --plan
just install-age-gopass --status
```

### Usar otro almacén vacío

```sh
PASSWORD_STORE_DIR="$HOME/.password-store-lab" just init-gopass-age
```

### Cifrado general de archivos con age

Para archivos que no son entradas de gopass usa el helper `age-file` y un
recipient explícito:

```sh
just age-file --encrypt --input ~/.config/app/config.yml \
  --output ~/.config/app/config.yml.age --ssh-recipient ~/.ssh/id_ed25519.pub
```

## Protecciones de seguridad

- `age` se instala desde Debian.
- gopass se instala desde `packages.gopass.pw` con keyring separado, fuente
  `Signed-By` y un pin que no prioriza paquetes generales de ese repositorio.
- La huella del keyring se verifica antes de instalar la fuente.
- `--apply` no ejecuta `gopass setup`, no crea identidades y no almacena
  contraseñas.
- La inicialización rechaza un almacén no vacío para evitar sobrescribir uno
  existente.
- No se imprime el contenido de ningún secreto ni se añade el almacén al
  repositorio de scripts.
- La frase de protección del backend age es sensible y debe guardarse fuera
  del repositorio y de respaldos no cifrados.

## Fallos conocidos

### `gopass oficial no tiene candidato APT`

**Causa:** la fuente oficial no se pudo actualizar o APT está bloqueando su
  keyring.

**Solución:** revisa la conectividad HTTPS y ejecuta `just install-age-gopass
--check`; no instales el paquete Debian homónimo sin confirmar que sea el
proyecto `gopass.pw`.

### `la huella del keyring gopass no coincide`

**Causa:** el keyring descargado no coincide con la identidad fijada por el
instalador.

**Solución:** detén la instalación y revisa el keyring y la documentación
oficial. No fuerces APT ni desactives la verificación.

### `el almacén ... no está vacío`

**Causa:** `--init-gopass-age` protege un almacén existente y no lo convierte
  automáticamente.

**Solución:** usa el almacén existente con su backend actual o planifica una
  conversión explícita después de crear un respaldo verificable.

## Changelog

### [Unreleased]

- **feat:** añadir instalación segura de age y gopass oficial.
- **feat:** separar la inicialización interactiva del almacén age.
