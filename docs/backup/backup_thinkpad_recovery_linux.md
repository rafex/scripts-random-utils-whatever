---
title: backup_thinkpad_recovery_linux.sh
description: Respaldo seguro y curado del estado de una ThinkPad Debian
tags:
  - backup
  - hardware
  - seguridad
---

# backup_thinkpad_recovery_linux.sh

Crea una instantánea del estado de la ThinkPad y una copia curada del perfil
`thinkpad-x1-yoga-1st` en un SSD externo validado. No modifica la instalación
actual.

- **Ruta:** `scripts/backup/backup_thinkpad_recovery_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `tar`, `sha256sum`, `findmnt`, `lsblk`, `mountpoint`, `file`; `sudo` para inventarios protegidos

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

El SSD debe estar montado previamente en:

```text
/run/media/rafex/ssd_rafex_1
```

El script comprueba que el dispositivo montado tenga exactamente la etiqueta
`ssd_rafex_1`. No monta discos automáticamente.

También funciona si el SSD está en exFAT. En ese caso copia el contenido sin
propietario ni permisos Unix, porque exFAT no puede conservarlos; al restaurar
en Linux se deben volver a aplicar los permisos.

## Uso

Desde la raíz del repositorio:

```bash
just backup-thinkpad --check
just backup-thinkpad --plan
just backup-thinkpad --apply
```

El resultado contiene un directorio y un archivo comprimido hermano:

```text
rafex-thinkpad-recovery-YYYYMMDD_HHMMSS/
rafex-thinkpad-recovery-YYYYMMDD_HHMMSS.tar.gz
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida entorno y destino sin crear archivos. |
| `--plan` | `--dry-run` | Muestra contenido y destino previstos sin cambios. |
| `--apply` | — | Crea el respaldo y verifica el archivo resultante. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `THINKPAD_BACKUP_ROOT` | `/run/media/$USER/ssd_rafex_1` | Permite pruebas con otro punto de montaje; la etiqueta `ssd_rafex_1` sigue siendo obligatoria. |

Los argumentos de la línea de comandos determinan el modo. La variable solo
determina el punto de montaje y no puede saltarse la validación de etiqueta.

## Ejemplos

### Forma recomendada

```bash
udisksctl mount -b /dev/sda3
just backup-thinkpad --check
just backup-thinkpad --plan
just backup-thinkpad --apply
```

### Verificar el resultado

```bash
cd /run/media/rafex/ssd_rafex_1/rafex-thinkpad-recovery-YYYYMMDD_HHMMSS
sha256sum -c manifest.sha256
tar -tzf ../rafex-thinkpad-recovery-YYYYMMDD_HHMMSS.tar.gz
```

### Restauración conceptual

Revisa primero `MIGRATION_REPORT.md` y usa el perfil versionado:

```bash
just install-profile thinkpad-x1-yoga-1st --dry-run
```

No restaures directamente `fstab`, `crypttab`, GRUB, UUID, Xorg, DPI ni
autorandr.

## Protecciones de seguridad

- `--check` y `--plan` no escriben archivos persistentes.
- El destino debe estar montado y tener la etiqueta exacta `ssd_rafex_1`.
- Se usa un staging temporal y solo se publica después de completar el inventario.
- En exFAT el contenido es portable, pero no conserva propietario ni permisos Unix.
- Se excluyen `.ssh`, perfiles Wi‑Fi, credenciales Git, tokens, cookies,
  keyrings privados, caches, logs privados y `mise/installs`.
- Los archivos de texto pasan por una redacción de patrones sensibles y luego se
  inspecciona el staging antes de publicarlo.
- Se guardan hashes SHA-256 y se verifica también la extracción del `.tar.gz`.
- `fstab`, `crypttab`, GRUB y fuentes APT quedan marcados como referencia.
- El script no instala paquetes, no modifica servicios, no monta discos y no
  modifica el repositorio remoto.

## Fallos conocidos

### `el destino no está montado`

**Causa:** el SSD externo no está montado en la ruta esperada.

**Solución:** identifica la partición y móntala sin `sudo`, por ejemplo:

```bash
lsblk -f
udisksctl mount -b /dev/sda3
```

### `la etiqueta del destino no coincide`

**Causa:** se seleccionó un disco distinto de `ssd_rafex_1`.

**Solución:** cancela la operación y confirma la etiqueta con `lsblk -f`.

### `se detectaron posibles secretos en el staging`

**Causa:** un archivo portable contiene una asignación o bloque que parece una
clave, token o contraseña.

**Solución:** no se publica el respaldo. Revisa el archivo temporal indicado,
retira el secreto de la configuración o excluye esa configuración antes de
reintentar.

### `141` al ejecutar `usb-perms --check`

**Causa:** es un fallo independiente del backup en una tubería truncada por
`head` bajo `pipefail`.

**Solución:** no afecta al backup; corregir el script USB antes de usar ese
diagnóstico como criterio de aceptación.

### Sesiones tmux activas tras una auditoría

**Causa:** las pruebas de configuración de tmux deben usar un socket aislado;
detener el servidor del socket predeterminado puede cerrar las sesiones
interactivas aunque no modifique ningún archivo.

**Solución:** este repositorio no intenta detener el servidor principal.
Comprueba configuraciones con un socket temporal (`tmux -L nombre-prueba ...`)
y conserva cualquier texto importante antes de ejecutar diagnósticos.

## Changelog

### [Unreleased]

- **feat:** añadir respaldo transaccional y curado de ThinkPad con inventarios,
  exclusión de secretos, reporte de migración y verificación SHA-256.
