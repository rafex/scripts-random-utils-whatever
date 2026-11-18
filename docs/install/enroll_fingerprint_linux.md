# enroll_fingerprint_linux.sh

Registra una huella del usuario actual y verifica que el lector la reconoce.

- **Ruta:** `scripts/install/enroll_fingerprint_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `fprintd-enroll`, `fprintd-verify`

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

Un lector reconocido por `fprintd` y acceso físico al sensor. Ejecuta el
comando como el usuario que registrará su huella.

## Uso

```bash
just enroll-fingerprint
```

Toca el lector cuando se solicite. La verificación empieza si el registro
termina correctamente.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | El wrapper no define opciones. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `PATH` | Permite localizar los comandos de `fprintd` y el wrapper instalado. |

## Ejemplos

Instala el comando desde la raíz del repositorio y ejecútalo:

```bash
mkdir -p ~/.local/bin
install -m 755 scripts/install/enroll_fingerprint_linux.sh ~/.local/bin/enroll-fingerprint
~/.local/bin/enroll-fingerprint
```

Si `~/.local/bin` no está en la ruta de búsqueda de la sesión:

```bash
PATH="$HOME/.local/bin:$PATH" enroll-fingerprint
```

## Fallos conocidos

### `No devices available`

**Causa:** `fprintd` no reconoce ningún lector.

**Solución:** comprueba que el controlador del sensor esté instalado y que el
lector aparezca al ejecutar `fprintd-list "$(id -un)"`.

## Changelog

### [Unreleased]

- **feat:** añade un comando para registrar y verificar una huella.
