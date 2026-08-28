---
title: configure_thinkpad_s2idle_linux.sh
description: Hace permanente el modo s2idle para mejorar la reanudación de la ThinkPad X1 Yoga.
tags:
  - hardware
  - energia
  - thinkpad
---

# configure_thinkpad_s2idle_linux.sh

Configura `mem_sleep_default=s2idle` en GRUB para que la ThinkPad use de forma
persistente el modo de suspensión que fue probado con éxito. No reinicia la
computadora automáticamente.

- **Ruta:** `scripts/hardware/configure_thinkpad_s2idle_linux.sh`
- **SO requerido:** Linux (Debian con GRUB)
- **Dependencias:** Bash, `sudo`, `sed`, `grep`, `systemctl`, `update-grub`

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

- ThinkPad X1 Yoga con GRUB instalado.
- Acceso `sudo` para modificar `/etc/default/grub` y ejecutar `update-grub`.
- Haber probado previamente la suspensión con:

  ```bash
  echo s2idle | sudo tee /sys/power/mem_sleep
  systemctl suspend
  ```

- Una forma de recuperación local si el equipo no reanuda correctamente.

## Uso

Desde la raíz del repositorio:

```bash
just configure-thinkpad-s2idle --check
just configure-thinkpad-s2idle --plan
just configure-thinkpad-s2idle --apply
```

Después de aplicar y cuando sea conveniente:

```bash
sudo reboot
cat /sys/power/mem_sleep
```

La salida esperada después del reinicio es:

```text
[s2idle] deep
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra el modo actual, el parámetro del kernel y el contenido relevante de GRUB. |
| `--plan` | `--dry-run` | Muestra cambios previstos sin usar `sudo` ni modificar archivos. |
| `--apply` | — | Respalda GRUB, configura `mem_sleep_default=s2idle` y ejecuta `update-grub`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este script no usa `.env` ni acepta variables de entorno para modificar la
ruta de GRUB. El archivo objetivo es siempre `/etc/default/grub` para evitar
alterar otro sistema por accidente.

## Ejemplos

### Forma explícita recomendada

```bash
just configure-thinkpad-s2idle --check
just configure-thinkpad-s2idle --apply
```

### Ver el plan sin cambios

```bash
just configure-thinkpad-s2idle --plan
```

### Validar después de reiniciar

```bash
cat /sys/power/mem_sleep
grep -o 'mem_sleep_default=[^ ]*' /proc/cmdline
systemctl suspend
```

## Protecciones de seguridad

- `--check`, `--plan` y `--dry-run` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`.
- Crea un respaldo fechado en `/var/backups/rafex-thinkpad-s2idle/` antes de
  cambiar `/etc/default/grub`.
- Reemplaza de forma idempotente un valor previo de `mem_sleep_default` y no
  duplica el parámetro.
- Ejecuta `update-grub` después del cambio y restaura automáticamente el
  respaldo si `update-grub` falla.
- No reinicia automáticamente, no modifica particiones, `fstab`, LUKS ni
  Secure Boot.

## Fallos conocidos

### `update-grub no está disponible` o falla

**Causa:** el sistema no usa GRUB, el paquete está incompleto o hay un error
en la configuración de arranque.

**Solución:** no continúes con el cambio; revisa `sudo update-grub` y conserva
el respaldo. El script restaura `/etc/default/grub` si la ejecución falla.

### La salida sigue siendo `s2idle [deep]`

**Causa:** todavía no se ha reiniciado el equipo o el gestor de arranque no
aplicó el parámetro.

**Solución:** reinicia y verifica `/proc/cmdline` y `/sys/power/mem_sleep`.

### El equipo vuelve a fallar al despertar

**Causa:** algún dispositivo o controlador puede fallar incluso con `s2idle`.

**Solución:** usa el respaldo para revertir el cambio desde la consola local y
recopila `sudo journalctl -b -1 -k` antes de probar otro modo.

## Changelog

### [Unreleased]

- **feat:** configura de forma idempotente `mem_sleep_default=s2idle` para la ThinkPad.
- **docs:** documenta verificación, respaldo y reversión del parámetro de suspensión.

