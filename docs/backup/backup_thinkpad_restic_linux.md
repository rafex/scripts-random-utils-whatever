---
title: backup_thinkpad_restic_linux.sh
description: Respaldos incrementales, cifrados y controlados de la ThinkPad
tags:
  - backup
  - restic
  - seguridad
---

# backup_thinkpad_restic_linux.sh

Administra dos repositorios Restic independientes en el SSD externo: uno para
la recuperación de la configuración y otro para los archivos personales. No
reemplaza la exportación puntual `backup_thinkpad_recovery_linux.sh`.

- **Ruta:** `scripts/backup/backup_thinkpad_restic_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `restic`, `secret-tool`, `findmnt`, `lsblk`, `mountpoint`, `systemctl`, `find`, `grep`

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

Instala las herramientas una sola vez:

```bash
just install-restic-backup --apply
```

Monta manualmente el SSD, sin que el script lo haga por ti. El punto esperado
es `/run/media/$USER/ssd_rafex_1`; el dispositivo debe tener exactamente la
etiqueta `ssd_rafex_1`. El SSD actual puede conservar exFAT: Restic guarda sus
objetos cifrados y no necesita reformatearlo.

Los repositorios son independientes:

```text
/run/media/$USER/ssd_rafex_1/rafex-restic/recovery/
/run/media/$USER/ssd_rafex_1/rafex-restic/personal/
```

Cada perfil tiene una contraseña distinta, almacenada únicamente en Secret
Service con el servicio `rafex-restic` y el atributo `profile`.

## Uso

Inicializa cada repositorio una sola vez:

```bash
just backup-thinkpad-restic --init --profile recovery
just backup-thinkpad-restic --init --profile personal
```

Después crea snapshots manualmente:

```bash
just backup-thinkpad-restic --backup
just backup-thinkpad-restic --backup --profile recovery
just backup-thinkpad-restic --backup --profile personal
```

El perfil `recovery` contiene configuraciones y scripts del entorno ThinkPad,
además del perfil versionado. El perfil `personal` contiene `Documents`,
`Projects`, `Pictures`, `Videos` y `Music`, cuando existen.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida dependencias, SSD, repositorios y claves sin escribir. |
| `--plan` | `--dry-run` | Muestra fuentes, exclusiones y destinos previstos sin escribir. |
| `--init` | — | Inicializa el perfil indicado y guarda su clave en Secret Service. |
| `--backup` | — | Crea snapshots; sin perfil procesa recovery y personal. |
| `--status` | — | Muestra estado, número de snapshots y timer sin revelar contenido. |
| `--verify` | — | Ejecuta `restic check`; acepta `--read-data` para verificar datos completos. |
| `--prune --plan` | — | Simula la retención sin eliminar snapshots. |
| `--prune --apply` | — | Aplica la retención después de escribir `PURGAR`. |
| `--restore` | — | Restaura un perfil a un directorio temporal seguro. |
| `--install-timer` | — | Instala y activa un timer de usuario cada 12 horas. |
| `--uninstall-timer` | — | Desactiva y retira las unidades del timer. |
| `--profile <perfil>` | — | `recovery`, `personal` o `all`, según la acción. |
| `--snapshot <id>` | — | Snapshot para restaurar; por defecto `latest`. |
| `--target <ruta>` | — | Destino absoluto; inicialmente debe estar bajo `/tmp` o `/var/tmp`. |
| `--non-interactive` | — | Para el timer: omite el snapshot si falta SSD o keyring. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos de la CLI tienen prioridad sobre los valores predeterminados.
Estas variables permiten pruebas controladas, pero el punto de montaje siempre
debe validar la etiqueta del SSD.

| Variable | Predeterminado | Descripción |
|---|---|---|
| `RAFEX_RESTIC_MOUNTPOINT` | `/run/media/$USER/ssd_rafex_1` | Punto de montaje validado. |
| `RAFEX_RESTIC_BACKUP_ROOT` | `$RAFEX_RESTIC_MOUNTPOINT/rafex-restic` | Directorio que contiene ambos repositorios. |
| `XDG_CONFIG_HOME` | `$HOME/.config` | Base para el estado y las unidades de usuario. |
| `HOME` | El del usuario | Raíz de las fuentes personales y de configuración. |

No se admite una variable de contraseña. Las claves se consultan con
`secret-tool` en el momento de la operación.

## Ejemplos

Comprobar antes de conectar el SSD:

```bash
just backup-thinkpad-restic --check
just backup-thinkpad-restic --plan
```

Inicializar y respaldar después de montar `/dev/sda3`:

```bash
udisksctl mount -b /dev/sda3
just backup-thinkpad-restic --init --profile recovery
just backup-thinkpad-restic --init --profile personal
just backup-thinkpad-restic --backup
```

Verificar el repositorio:

```bash
just backup-thinkpad-restic --verify
just backup-thinkpad-restic --verify --read-data
```

Poda manual con confirmación:

```bash
just backup-thinkpad-restic --prune --plan
just backup-thinkpad-restic --prune --apply
```

Restaurar sin tocar la instalación activa:

```bash
just backup-thinkpad-restic --restore --profile recovery \
  --snapshot latest --target /tmp/restore-test
```

Timer opcional:

```bash
just backup-thinkpad-restic --install-timer
systemctl --user list-timers rafex-restic-backup.timer
```

## Protecciones de seguridad

- El runner se ejecuta como usuario normal y nunca llama a `sudo`.
- El destino debe estar montado y tener la etiqueta exacta `ssd_rafex_1`; no se
  monta ni reformatea ningún disco.
- `recovery` y `personal` usan repositorios y claves separados.
- Se excluyen SSH/GPG, credenciales Git, Wi-Fi, cookies, keyrings, tokens,
  caches, descargas temporales, archivos `.bak.*` y `mise/installs`.
- Se usa `--one-file-system` y no se lista el contenido de los snapshots.
- El perfil recovery se revisa para detectar claves privadas o asignaciones
  evidentes de secretos antes de iniciar un backup.
- La clave nunca aparece en archivos, variables persistentes, logs, Git ni
  argumentos de Restic.
- El timer solo crea snapshots; nunca hace `forget` ni `prune`. Si el SSD o el
  keyring no están disponibles, omite el ciclo sin guardar credenciales.
- La retención es manual: 14 diarios, 8 semanales, 12 mensuales y 3 anuales.
- Las restauraciones solo se permiten inicialmente en `/tmp` o `/var/tmp` y en
  directorios vacíos; no se puede sobrescribir `/` ni `$HOME`.
- Un solo SSD no protege contra robo, incendio o fallo del propio SSD. Para una
  política 3-2-1 hace falta una segunda réplica en otro destino.

### Diferencia con el respaldo portable

`backup_thinkpad_recovery_linux.sh` sigue siendo una exportación puntual
portable en tar.gz, útil para inspección o migración. No tiene snapshots,
deduplicación ni cifrado de Restic; este runner nuevo es el mecanismo
incremental principal.

### Restic, Borg y rsync

Restic fue elegido por cifrado, deduplicación, snapshots y restauración
selectiva. Borg es una alternativa excelente para un destino Linux dedicado,
preferentemente ext4/LUKS. Rsync deja carpetas navegables y es útil como copia
simple, pero no proporciona cifrado ni deduplicación propios.

## Fallos conocidos

### `el SSD no está montado o su etiqueta no es ssd_rafex_1`

**Causa:** el disco no está montado en el punto esperado o se eligió otro
dispositivo.

**Solución:** monta manualmente el SSD y comprueba `lsblk -f`. El script se
detiene para no escribir en un destino equivocado.

### `clave ausente o keyring bloqueado`

**Causa:** Secret Service no puede entregar la clave al usuario actual.

**Solución:** abre/desbloquea el keyring en la sesión gráfica. No crees una
  variable `RESTIC_PASSWORD` persistente ni guardes la clave en un archivo.

### `ya existe ... pero no se pudo validar su clave`

**Causa:** el repositorio tiene datos, pero la clave no está disponible o no es
la correcta.

**Solución:** no se sobrescribe. Recupera la contraseña desde el gestor de
secretos o desde el procedimiento de recuperación; no ejecutes otro `--init`.

### `se detectó un posible secreto en una configuración de recovery`

**Causa:** un archivo seleccionado contiene una clave privada o una asignación
que parece contener credenciales.

**Solución:** elimina el secreto de la configuración, rota la credencial si fue
expuesta y vuelve a intentar. El script cancela antes de crear el snapshot.

### Timer omitido

**Causa:** el SSD no está conectado o el keyring está bloqueado al ejecutarse
el servicio.

**Solución:** revisa `journalctl --user -u rafex-restic-backup.service`. El
timer no intenta montar discos ni reintenta con contraseñas alternativas.

### `--verify --read-data` tarda demasiado

**Causa:** lee todos los datos del repositorio y puede consumir I/O, CPU y
batería.

**Solución:** ejecútalo conectado a corriente y deja `--verify` para revisiones
rápidas entre verificaciones completas.

## Changelog

### [Unreleased]

- **feat:** añadir respaldos Restic separados, cifrados, incrementales y con
  retención manual.

