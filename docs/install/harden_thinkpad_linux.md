---
title: harden_thinkpad_linux.sh
description: Hardening por fases de una ThinkPad Debian con SSH, UFW, fail2ban y auditoría
tags:
  - instalación
  - seguridad
  - thinkpad
---

# harden_thinkpad_linux.sh

Endurece la ThinkPad Debian en dos fases: primero OpenSSH por la sesión remota
actual y después el sistema local. El script no acepta ni almacena contraseñas;
solicita autorización solamente mediante `sudo -v` en modos que la necesitan.

- **Ruta:** `scripts/install/harden_thinkpad_linux.sh`
- **SO requerido:** Linux (Debian Forky)
- **Dependencias:** `bash`, `apt-get`, `dpkg-query`, `sudo`; instala UFW y herramientas de seguridad en `--apply`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Fase SSH](#fase-ssh)
- [Fase local](#fase-local)
- [Estado y auditoría](#estado-y-auditoria)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Ejecutar como usuario normal con permisos `sudo`.
- Mantener una segunda terminal disponible antes de modificar SSH.
- La fase `ssh` requiere ejecutarse dentro de una sesión SSH, salvo que se use
  explícitamente `--local-console`.
- Debe existir una clave utilizable en `~/.ssh/authorized_keys` antes de
  desactivar la autenticación por contraseña.
- Ejecutar la fase local desde una red donde sea posible recuperar la sesión
  o desde la consola local si se cambia la conectividad.

## Uso

Diagnóstico sin cambios:

```sh
just harden-thinkpad --check
```

Revisar la fase SSH:

```sh
just harden-thinkpad --plan --stage ssh
```

Aplicar SSH desde la sesión actual:

```sh
just harden-thinkpad --apply --stage ssh
```

Comprobar una segunda conexión antes de continuar:

```sh
ssh -o BatchMode=yes thinkpad true
```

Aplicar los controles locales:

```sh
just harden-thinkpad --plan --stage local
just harden-thinkpad --apply --stage local
```

`--stage all` ejecuta ambas fases en orden, pero se recomienda usar fases
separadas para verificar SSH antes de activar el firewall y los servicios.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica SSH, paquetes y servicios sin cambios persistentes. |
| `--plan` | `--dry-run` | Muestra las acciones previstas sin aplicarlas. |
| `--apply` | — | Aplica la fase seleccionada y solicita autorización con `sudo -v`. |
| `--stage ssh` | — | Endurece OpenSSH y recarga el servicio sin reiniciarlo. |
| `--stage local` | — | Instala y configura UFW, fail2ban, AppArmor, auditd, actualizaciones, sysctl y USBGuard. |
| `--stage all` | — | Ejecuta `ssh` y luego `local`. |
| `--local-console` | — | Permite la fase SSH fuera de SSH, solo desde la consola local. |
| `--status` | — | Muestra el estado actual de los controles. |
| `--audit` | — | Ejecuta Lynis y debsums; no cambia la configuración. |
| `--log-file <archivo>` | — | Guarda la salida en el archivo indicado. |
| `--help` | `-h` | Muestra la ayuda. |

## Ejemplos

Ejecutar la fase SSH desde la Mac mediante el alias configurado:

```sh
ssh thinkpad 'cd ~/repository/github/rafex/scripts-random-utils-whatever && \
  just harden-thinkpad --apply --stage ssh'
```

Después de verificar una segunda conexión SSH, aplicar la fase local:

```sh
ssh thinkpad 'cd ~/repository/github/rafex/scripts-random-utils-whatever && \
  just harden-thinkpad --apply --stage local'
```

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `THINKPAD_HARDENING_LOG_FILE` | vacío | Archivo de log; `--log-file` tiene prioridad. |
| `THINKPAD_HARDENING_LOG_DIR` | `~/.local/state/scripts-random-utils-whatever/logs/` | Directorio de logs automáticos para `--apply` y `--audit`. |

## Fase SSH

El archivo administrado es:

```text
/etc/ssh/sshd_config.d/90-thinkpad-hardening.conf
```

Se aplican restricciones de root, contraseña, intentos y sesiones inactivas.
No se cambia el puerto `22` ni se añaden `AllowUsers` o `AllowGroups`.

Se conservan los valores existentes de forwarding para no romper los túneles
de desarrollo, X11 ni el flujo actual del usuario.

La operación valida `sshd -t` antes y después, usa `systemctl reload ssh` y
restaura el archivo anterior si la validación o la recarga fallan.

## Fase local

Instala:

```text
ufw fail2ban apparmor-utils apparmor-profiles apparmor-profiles-extra
auditd audispd-plugins unattended-upgrades debsums lynis usbguard needrestart
```

UFW reutiliza el instalador existente con el perfil `all`: SSH/Mosh quedan
accesibles desde cualquier red porque se usa autenticación por clave; los
puertos de desarrollo, OBS y MediaMTX se limitan a las LAN configuradas por
`UFW_LAN_SUBNETS`.

Fail2ban habilita únicamente el jail SSH con backend systemd y acción UFW:

```ini
[sshd]
enabled = true
backend = systemd
port = 22
banaction = ufw
maxretry = 5
findtime = 10m
bantime = 1h
```

AppArmor se mantiene activo y se audita; ningún perfil se cambia globalmente a
`enforce`. Auditd registra cambios en SSH, sudoers, identidades y seguridad sin
usar reglas inmutables. Unattended-upgrades instala solo seguridad diariamente
y no reinicia automáticamente.

Sysctl aplica ajustes defensivos compatibles con movilidad y Podman rootless.
No desactiva user namespaces, no toca i915, GRUB, `fstab` ni forwarding.

El estado también comprueba que existan los archivos administrados de Fail2ban
y auditd. Que el servicio `auditd` esté activo no implica que estas reglas
personalizadas estén instaladas.

```text
/etc/fail2ban/jail.d/sshd-thinkpad.local
/etc/audit/rules.d/99-thinkpad-hardening.rules
```

USBGuard queda en auditoría con dispositivos no reconocidos autorizados:

```text
ImplicitPolicyTarget=allow
PresentDevicePolicy=keep
InsertedDevicePolicy=apply-policy
IPCAllowedUsers=root
```

No se crea una allowlist ni se bloquean cámaras, lápiz, teclado, memorias o
adaptadores USB.

## Estado y auditoría

```sh
just harden-thinkpad --status
just harden-thinkpad --audit
```

Si se ejecuta por SSH sin una caché vigente de `sudo`, el estado privilegiado
se mostrará como pendiente. En ese caso ejecuta `sudo -v` en la ThinkPad y
repite el comando, o valida directamente:

```sh
sudo ufw status verbose
sudo fail2ban-client status sshd
sudo aa-status
sudo auditctl -s
sudo usbguard list-devices
sudo sshd -T
```

Los respaldos de archivos del sistema se guardan en:

```text
/var/backups/rafex-thinkpad-hardening/
```

Los logs de aplicación se guardan por defecto en:

```text
~/.local/state/scripts-random-utils-whatever/logs/
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no modifican archivos ni servicios.
- `--apply` solicita la contraseña únicamente a `sudo -v`.
- Nunca se escribe una contraseña en archivos, logs o argumentos.
- SSH se valida y recarga; no se reinicia para evitar interrumpir la sesión.
- Se hacen respaldos antes de reemplazar archivos bajo `/etc`.
- No se modifican particiones, LUKS, `fstab`, GRUB, Secure Boot ni contraseñas.
- No se instalan VPN, perfiles AppArmor en enforce ni USBGuard en bloqueo.
- No se desactiva `kernel.unprivileged_userns_clone`, para conservar Podman y
  sandboxing de aplicaciones.

## Fallos conocidos

### `no se encontró una clave SSH utilizable`

**Causa:** no existe una clave reconocible en `~/.ssh/authorized_keys`.
**Solución:** instala primero la clave pública con `just setup-ssh-trust` y
  verifica una conexión con `ssh -o BatchMode=yes thinkpad true`.

### `la etapa SSH requiere SSH_CONNECTION`

**Causa:** se intentó ejecutar la fase SSH desde una terminal local sin indicar
  la excepción explícita.
**Solución:** ejecútala por `ssh thinkpad` o usa `--local-console` desde la
  consola física.

### `sshd -t` falla después de escribir el drop-in

**Causa:** una directiva incompatible o un conflicto de configuración existente.
**Solución:** el script restaura el respaldo automáticamente; revisa el log y
  `sudo sshd -t` antes de reintentar.

### `fail2ban-client status sshd` no muestra el jail

**Causa:** fail2ban no pudo cargar el backend systemd o UFW no está activo.
**Solución:** revisar `sudo fail2ban-client -t`, `sudo journalctl -u fail2ban`
  y `sudo ufw status verbose`.

### `augenrules --load` no puede cargar reglas

**Causa:** una regla existente tiene sintaxis incompatible o el kernel no permite
  modificar las reglas actuales.
**Solución:** revisar `sudo augenrules --check` y el contenido de
  `/etc/audit/rules.d/`; no se añade `-e 2` para conservar recuperabilidad.

### Podman o una aplicación deja de funcionar tras sysctl

**Causa:** un ajuste del entorno concreto no es compatible con el sandbox.
**Solución:** revisar `/etc/sysctl.d/99-thinkpad-hardening.conf`, restaurar el
  respaldo y ejecutar `sudo sysctl --system` después de revertirlo.

## Changelog

### [Unreleased]

- **feat:** añadir hardening ThinkPad por fases SSH y local.
- **security:** incorporar UFW, fail2ban, AppArmor en auditoría, auditd mínimo,
  actualizaciones de seguridad, sysctl compatible y USBGuard no bloqueante.
