# connect_nas_linux

Monta el recurso TNAS por CIFS con SMB 3.1.1 y protege automáticamente el archivo local de credenciales.

- **Ruta:** `scripts/network/connect_nas_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `cifs-utils` (`mount.cifs`), `mountpoint`, `findmnt`, `sudo`, `awk`

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

- Linux con `mount.cifs`; instalar el cliente con `just install-nas-client --apply`.
- `sudo` con autorización para crear el punto de montaje y montar CIFS.
- Archivo de credenciales con `username=` y `password=`.
- Acceso de red al servidor y permisos sobre el recurso SMB.

## Uso

Ejecutar `just connect-nas` o directamente `bash scripts/network/connect_nas_linux.sh`. El script no acepta argumentos; su configuración se realiza con variables `NAS_*`.

## Opciones

No acepta opciones de línea de comandos.

| Opción | Alias | Descripción |
|---|---|---|
| — | — | Configurar el montaje mediante variables de entorno. |

## Variables de entorno

Los argumentos CLI no aplican. Las variables `NAS_*` prevalecen sobre sus valores predeterminados; `NAS_CREDENTIALS` prevalece sobre la ruta derivada de `XDG_CONFIG_HOME` y `HOME`.

| Variable | Predeterminado | Descripción |
|---|---|---|
| `NAS_SMB` | `//192.168.3.56/rafex` | Ruta UNC del recurso compartido. |
| `NAS_MOUNT_POINT` | `/mnt/tnas` | Ruta absoluta donde montar el recurso. |
| `NAS_CREDENTIALS` | `$XDG_CONFIG_HOME/samba/tnas.credentials` o `$HOME/.config/samba/tnas.credentials` | Archivo local con usuario y contraseña. |
| `NAS_SMB_VERSION` | `3.1.1` | Versión negociada con el servidor. |
| `NAS_UID`, `NAS_GID` | UID y GID del usuario actual | Propietario local de los archivos montados. |
| `NAS_FILE_MODE` | `0644` | Permisos locales para archivos. |
| `NAS_DIR_MODE` | `0755` | Permisos locales para directorios. |

## Ejemplos

Forma recomendada:

```bash
just connect-nas
```

Configurar otra ruta o recurso:

```bash
NAS_SMB=//nas.local/documentos NAS_MOUNT_POINT="$HOME/NAS/documentos" just connect-nas
```

Definir una ubicación XDG alternativa para las credenciales:

```bash
XDG_CONFIG_HOME="$HOME/.config" just connect-nas
```

No hay modo legacy con argumentos posicionales; se debe usar `NAS_*`.

## Protecciones de seguridad

- Rechaza enlaces simbólicos para el archivo de credenciales.
- Comprueba que el archivo incluya `username=` y `password=` sin mostrar sus valores.
- Ajusta el directorio de credenciales predeterminado a modo `700` y el archivo a `600` antes del montaje.
- No imprime la contraseña ni la incluye en la línea de comandos de `mount.cifs`.
- Si el punto ya está montado con el mismo recurso, informa que ya está conectado; si pertenece a otro montaje, falla para evitar ocultarlo.

## Fallos conocidos

### `falta 'mount.cifs'`

**Causa:** `cifs-utils` no está instalado o `mount.cifs` no está en `PATH`.
**Solución:** ejecutar `just install-nas-client --check` y luego `just install-nas-client --apply`.

### `el archivo de credenciales debe contener username= y password=`

**Causa:** falta una de las claves obligatorias o sus nombres están mal escritos.
**Solución:** editar el archivo configurado por `NAS_CREDENTIALS` y usar las claves `username` y `password`.

### Error de montaje CIFS

**Causa:** credenciales incorrectas, recurso inaccesible, permisos insuficientes o incompatibilidad de protocolo con SMB 3.1.1.
**Solución:** verificar conectividad y permisos del recurso; si el servidor requiere otra versión SMB, establecer `NAS_SMB_VERSION` con la versión admitida.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.1.0 — 2026-10-05

**fix:** alinear el montaje con TNAS local y fortalecer la validación y protección de credenciales.

- Usar `/mnt/tnas`, SMB 3.1.1 y UID/GID actuales como valores predeterminados.
- Corregir la captura del error de montaje y detectar puntos ocupados por otro recurso.
- Restringir permisos del directorio y archivo de credenciales.
