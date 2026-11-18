# install_thinkpad_fingerprint_linux.sh

Instala el controlador del lector Validity VFS7500 (`138a:0090`) del ThinkPad
X1 Yoga de primera generación y registra el lector con `fprintd`.

- **Ruta:** `scripts/install/install_thinkpad_fingerprint_linux.sh`
- **SO requerido:** Linux (Debian Forky, amd64)
- **Dependencias:** `bash`, `usbutils`, `curl`, `sha256sum`, `tar`, APT, `sudo`, systemd. El instalador incorpora las dependencias de compilación mediante APT.

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

Debian Forky amd64 con el dispositivo USB `138a:0090`. Para instalar se requiere
una sesión de usuario con acceso a `sudo`, fuentes oficiales de Debian
actualizadas y conexión a GitHub. El modo de consulta requiere `fprintd`.

## Uso

El instalador verifica el USB, descarga una revisión fija de
[jamesyc/libfprint](https://github.com/jamesyc/libfprint/tree/073e79143d9ecd5832fd3196bf70a51d091382c0),
compila los paquetes contra las bibliotecas de Forky, instala
`libfprint-2-2` y `libfprint-2-vfs0090`, y reinicia `fprintd`. También instala
`~/.local/bin/enroll-fingerprint`.

Después de que aparezca `Validity VFS0090`, registra y verifica tu huella
como tu usuario con `enroll-fingerprint`. El instalador prepara el hardware.
La autenticación de `sudo` e `i3lock-color` todavía requiere configurar PAM
por separado después de verificar la huella.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el USB, los paquetes y los lectores de `fprintd`. Es el modo predeterminado. |
| `--apply` | — | Compila e instala el controlador si hace falta e instala el comando de registro. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `PATH` | Ruta de búsqueda de ejecutables. |
| `HOME` | Directorio del usuario al que se instala el comando de registro. |
| `TMPDIR` | Directorio temporal de compilación, si se define. |

## Ejemplos

```bash
just install-thinkpad-fingerprint --check
just install-thinkpad-fingerprint --apply
~/.local/bin/enroll-fingerprint
```

Para compilar en un directorio temporal alternativo existente:

```bash
TMPDIR=/var/tmp just install-thinkpad-fingerprint --apply
```

## Protecciones de seguridad

Se comprueba el SHA-256 del código fuente antes de extraerlo. La compilación
se ejecuta como usuario normal. APT instala los paquetes locales y conserva
las fuentes configuradas. El instalador comprueba si ya hay un comando
`enroll-fingerprint` distinto antes de escribir en el destino.

## Fallos conocidos

### `Depends: libgusb2 ... but it is not installable`

**Causa:** los binarios publicados para Debian 13 dependen de `libgusb2`,
mientras que el sistema Forky inspeccionado usa `libgusb2a`.

**Solución:** usa `--apply` para compilar el paquete sobre Forky.

### `No devices available`

**Causa:** el `libfprint` oficial no reconoce este lector. Con el controlador
instalado, el sensor también podría necesitar inicialización si el registro de
`fprintd` indica `Sensor not initialized`.

**Solución:** revisa `sudo journalctl -u fprintd -n 30`. Si indica que falta
inicializar el sensor, consulta las instrucciones del proyecto antes de
restablecerlo. En el ThinkPad donde se reprodujo esta instalación, el lector
apareció tras instalar el controlador.

## Changelog

### [Unreleased]

- **feat:** reproduce la instalación del controlador Validity en Debian Forky e instala el comando de registro.
