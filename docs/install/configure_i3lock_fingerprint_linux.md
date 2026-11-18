# configure_i3lock_fingerprint_linux.sh

Habilita la huella para desbloquear i3lock o i3lock-color con la contraseña
como respaldo.

- **Ruta:** `scripts/install/configure_i3lock_fingerprint_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, PAM, `libpam-fprintd`, `fprintd-list`, `sudo`, GNU `sed`, `grep`, `mktemp`, `cp`

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

Una huella registrada, `pam_fprintd.so` instalado y la configuración Debian
de i3lock con una línea `@include common-auth`. El bloqueador debe permitir
enviar un intento vacío al pulsar Enter.

## Uso

Pulsa **Enter** en la pantalla de bloqueo y toca el lector. Si falla o pasan
ocho segundos, escribe tu contraseña y pulsa **Enter**. Al enviar la contraseña,
PAM también puede esperar ocho segundos antes de validarla.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra si existe el bloque administrado. Es el valor predeterminado. |
| `--apply` | — | Guarda una copia y habilita la huella para la cuenta que invoca sudo. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `SUDO_USER` | La establece sudo. Identifica la cuenta a la que se aplica el cambio. |

## Ejemplos

```bash
just configure-i3lock-fingerprint --check
just configure-i3lock-fingerprint --apply
```

Desde la raíz del repositorio, con la ubicación de Bash explícita en `PATH`:

```bash
PATH="/usr/bin:/bin:$PATH" bash scripts/install/configure_i3lock_fingerprint_linux.sh --check
```

## Protecciones de seguridad

Solo modifica `/etc/pam.d/i3lock`, conserva `common-auth` y limita la regla de
huella al usuario que aplica el cambio. Guarda la configuración anterior en
un directorio privado de `/var/backups` e imprime su ruta.

## Fallos conocidos

### El lector no se activa al pulsar Enter

**Causa:** el bloqueador puede estar configurado para ignorar intentos vacíos.

**Solución:** revisa si se ejecuta con `--ignore-empty-password` o `-e` y quita
esa opción para permitir el intento con huella.

## Changelog

### [Unreleased]

- **feat:** habilita la huella en i3lock con contraseña de respaldo.
