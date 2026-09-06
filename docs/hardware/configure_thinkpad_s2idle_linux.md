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
persistente el modo de suspensión con más ciclos reales observados en esta
máquina (ver [Evidencia de pruebas](#evidencia-de-pruebas)). No reinicia la
computadora automáticamente.

- **Ruta:** `scripts/hardware/configure_thinkpad_s2idle_linux.sh`
- **SO requerido:** Linux (Debian con GRUB)
- **Dependencias:** Bash, `sudo`, `sed`, `grep`, `systemctl`, `update-grub`

---

## Índice

- [Requisitos](#requisitos)
- [Evidencia de pruebas](#evidencia-de-pruebas)
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

## Evidencia de pruebas

Prueba dirigida del 2026-09-06 comparando ambos modos en la misma ThinkPad
(kernel `7.1.12+deb14-amd64`), con el usuario físicamente presente. Log
completo en
`~/.local/state/scripts-random-utils-whatever/logs/suspend-test.log` en la
máquina.

| Modo | Ciclos observados | Duración | Resultado |
|---|---|---|---|
| `s2idle` | 2 (journal previo, 2026-09-05) | ~3 min y ~6h45min | Ambos limpios: `PM: suspend entry/exit` sin errores en el journal. |
| `deep` | 1 (prueba dirigida, 2026-09-06, `/sys/power/mem_sleep` cambiado solo en runtime) | ~50s | Limpio: `PM: suspend entry (deep)` → `Restarting tasks: Done` → `PM: suspend exit`. Ruido menor y auto-recuperado: reset de 3 dispositivos USB al reanudar (normal en cualquier resume) y un error transitorio de Bluetooth (`hci0: Reading supported features failed (-16)`) que no dejó Bluetooth bloqueado ni roto (`rfkill`/`bluetoothctl` normales después de reanudar). |

Detalle de la reanudación con `deep`: cerrar y volver a abrir la tapa
despertó la máquina de forma confiable; una sola pulsación de tecla no lo
hizo en el primer intento (sin confirmar si hacen falta varias pulsaciones
o si el teclado no es una fuente de wake válida en `deep` en este hardware
— pendiente de una prueba dedicada).

**Ambos modos despertaron correctamente** en esta prueba — no se reprodujo
ningún fallo de reanudación con `deep` en esta ronda. La elección de
`s2idle` como persistente sigue siendo razonable (más ciclos observados,
incluida una suspensión real de casi 7 horas, sin siquiera el ruido menor
de USB/Bluetooth que sí apareció con `deep`), pero **la evidencia de esta
prueba no muestra que `deep` esté roto en este hardware** con el TPM ya
deshabilitado (ver nota siguiente y
[thinkpad_shutdown_tpm_investigation.md](thinkpad_shutdown_tpm_investigation.md)).

> **Nota sobre TPM (hipótesis del usuario, no verificada con una prueba
> A/B):** el usuario reporta que, antes de deshabilitar por completo el
> TPM/Security Chip (ver la investigación de apagado incompleto), intentos
> previos de suspensión `deep` no lograban reanudar correctamente. La
> prueba de esta sección se hizo **con el TPM ya deshabilitado**, y resultó
> limpia. Esto es consistente con una posible relación entre el estado del
> TPM y la reanudación de `deep` en este equipo, pero no se ha confirmado
> con una prueba controlada (ej. volver a habilitar el TPM y repetir
> `deep` para comparar) — se documenta como hipótesis, no como causa
> confirmada.

Para reproducir la comparación sin tocar el default persistido en GRUB:

```bash
echo deep | sudo tee /sys/power/mem_sleep    # solo runtime, no toca GRUB
sudo systemctl suspend
# despierta la laptop (cerrar/abrir la tapa es el método confiable), luego:
cat /sys/power/mem_sleep                      # confirma que seguía en "deep"
sudo journalctl -k --since "-5 min" | grep -iE "PM: suspend|error|fail"
echo s2idle | sudo tee /sys/power/mem_sleep   # regresa al runtime persistido
```

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
| `--check` | — | Muestra el modo actual, el parámetro del kernel y el contenido relevante de GRUB; un parámetro pendiente se informa como aviso y no produce fallo. |
| `--plan` | `--dry-run` | Muestra cambios previstos sin usar `sudo` ni modificar archivos; termina correctamente aunque falte aplicar la configuración. |
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
- **fix:** `--check` y `--plan` ya no terminan con error cuando la configuración aún está pendiente.
- **docs:** documenta verificación, respaldo y reversión del parámetro de suspensión.
- **docs:** agrega evidencia real de prueba dirigida (2026-09-06) comparando
  `s2idle` y `deep` con el TPM ya deshabilitado — ambos modos reanudaron
  limpio; reemplaza la afirmación previa sin evidencia de que solo
  `s2idle` "fue probado con éxito".
