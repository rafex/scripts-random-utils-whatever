---
title: ThinkPad X1 Yoga — investigación de apagado incompleto y TPM
description: Evidencia de septiembre de 2026 y prueba pendiente Intel PTT frente a Discrete TPM
tags:
  - thinkpad
  - hardware
  - diagnostico
---

# ThinkPad X1 Yoga: apagado incompleto y TPM

## Estado de la investigación — 2026-09-04

**Causa aún no confirmada. Security Chip deshabilitado; prueba de apagado pendiente.** Este informe
conserva extractos de las consultas realizadas por SSH y en `thinkpad:0`, junto
con observaciones del usuario. No contiene seriales, UUID de discos, claves,
direcciones de red ni capturas completas de la terminal.

Equipo: ThinkPad X1 Yoga de primera generación, tipo 20FR, Intel i7-6600U,
16 GB RAM. BIOS N1FET82W (1.56), EC N1FHT36W (1.19), Intel ME 11.8.93.4323.
La fecha 2022-12-06 de la pantalla principal es la publicación del BIOS,
no la lectura del reloj RTC. No se reflasheó el BIOS durante esta investigación.

## Síntomas observados por el usuario

- Tras apagar Debian, una pulsación breve no vuelve a encender la máquina.
- El problema existía antes de regenerar los initramfs.
- En una ocasión recuperó el encendido mediante el orificio emergency reset.
- Posteriormente pudo encender manteniendo pulsado el botón, tanto con cargador
  como, en otra prueba, sin cargador y sin emergency reset.
- Sospecha consumo de batería durante el supuesto apagado. No se ha medido aún
  el consumo residual ni confirmado físicamente el estado eléctrico final.
- La prueba desde Puppy Linux Live USB se propuso; su resultado no está registrado.

## Evidencia del sistema

### Reloj

Consulta `timedatectl` a las 17:11 locales:

```text
Local time: 2026-09-04 17:11:18 CST
Universal time: 2026-09-04 23:11:18 UTC
RTC time: 2026-09-04 23:11:18
Time zone: America/Mexico_City (CST, -0600)
System clock synchronized: yes
NTP service: active
RTC in local TZ: no
```

La diferencia de seis horas es coherente con RTC en UTC. No constituye evidencia
de pila RTC agotada; no volver a corregir el BIOS por ese desfase únicamente.

### Arranque y apagado

El sistema arrancó con `7.1.12+deb14-amd64` y llegó a la sesión gráfica y SSH
después de la regeneración de initramfs. Las imágenes usan zstd, como las
anteriores; esa operación no cambió vmlinuz ni GRUB.

El journal del apagado anterior mostró:

```text
17:01:57 Finished systemd-poweroff.service - System Power Off.
17:01:57 Reached target poweroff.target - System Power Off.
17:01:57 Shutting down.
17:01:57 Syncing filesystems and block devices.
17:01:57 Sending SIGTERM to remaining processes...
17:01:57 Journal stopped
```

Esto acredita una secuencia ordenada hasta el cierre del journal, **no el corte
físico de alimentación**. La pérdida de SSH después de otra orden poweroff
tampoco demuestra por sí sola un apagado eléctrico completo.

### TPM y otros mensajes

En los arranques revisados aparecen:

```text
tpm tpm0: Operation Timed out
tpm tpm0: Operation Timed out
tpm_crb_acpi MSFT0101:00: probe with driver tpm_crb_acpi failed with error -62
```

Se observaron ya en el arranque del 1 de septiembre con kernel 7.1.8 y en los
posteriores con 7.1.12. Persisten a las 18:01 del 4 de septiembre. Su antigüedad
no los descarta como causa: el síntoma también era anterior.

- Un error DMAR/DMA también estaba presente antes de regenerar initramfs.
- En el reinicio de las 16:34 se registró `watchdog did not stop!`, junto con
  systemd usando el watchdog para supervisar el reinicio; no prueba por sí solo
  una avería.
- No se encontraron kernel panic, MCE ni temperatura crítica en las consultas
  realizadas. Esto no descarta errores que no llegasen a persistirse.
- CPU alrededor de 46 °C y temperatura compuesta del NVMe alrededor de 30 °C.
  Los sensores secundarios NVMe devolvieron temperaturas negativas imposibles;
  no deben usarse para diagnosticar temperatura real.

### Alimentación

AC detectado (`online=1`), batería 76 %, umbrales TLP 75/80, comportamiento `auto`.
El estado `Not charging` es compatible con esos umbrales. El controlador reportó
47360 mWh tanto de diseño como de carga completa y cero ciclos (o no soportados).
Estos datos no certifican salud de batería ni prueban que el cargador funcione
correctamente bajo todas las condiciones.

## Comprobación de dependencias TPM antes de modificar BIOS

La fotografía del menú Security Chip confirma:

```text
Security Chip Selection: Intel PTT
Security Chip: Enabled
Intel TXT: Disabled
```

La ayuda del propio BIOS identifica Intel PTT como TPM 2.0 y Discrete TPM como
TPM 1.2. Son implementaciones y versiones diferentes.

Consultas de solo lectura realizadas con sudo en `thinkpad:0`:

```text
LUKS keyslot types: ['luks2']
LUKS token types: []
```

Se obtuvo este resumen con `cryptsetup luksDump --dump-json-metadata` sobre la
partición LUKS y un filtro Python que solo imprime tipos de slots/tokens.
No se extrajo material de claves. La entrada crypttab usa `none` y las opciones
`luks,discard,x-initrd.attach`, sin desbloqueo TPM.

No se encontraron referencias a TPM/Clevis en los archivos consultados de
crypttab, cryptsetup-initramfs, unidades locales systemd, PAM, environment y
profile.d. No aparecieron dispositivos `/dev/tpm*`. No se detectaron almacenes
tpm2-pkcs11 en las ubicaciones convencionales consultadas. Esto no constituye un
inventario exhaustivo de aplicaciones o credenciales externas.

Hay paquetes swtpm/libtpms para TPM virtuales. Su presencia no acredita uso del
TPM físico para desbloquear el disco.

El kernel tiene integrados:

```text
CONFIG_TCG_TPM=y
CONFIG_TCG_TIS=y
CONFIG_TCG_CRB=y
```

Por ello, copiar una blacklist de módulos de un reporte antiguo no basta para
desactivar esos controladores integrados.

## Casos relacionados y evaluación

- [Reporte Debian #939170, actualización de mayo de 2023](https://lists.debian.org/debian-kernel/2023/05/msg00184.html):
  X1 Yoga que alcanza power off pero mantiene actividad y consume batería.
  El autor informó éxito con blacklist TPM en Bullseye y fracaso de ese método
  en Bookworm.
- [Reporte original X1 Yoga Gen 1 en Void Linux](https://www.reddit.com/r/voidlinux/comments/ss2i14):
  el autor confirmó resolver apagado y suspensión cambiando Intel PTT por
  Discrete TPM en BIOS.
- [Reporte Ubuntu #2080943](https://bugs.launchpad.net/bugs/2080943),
  [correspondencia archivada](https://www.mail-archive.com/search?f=1&l=kernel-packages%40lists.launchpad.net&o=newest&q=2080943):
  botón sin respuesta después de apagar, recuperación con reset o pulsación larga.
  Participantes reportaron resolverlo deshabilitando Security Chip. También
  documentaron distinto resultado entre dos versiones de Live USB.
- [Manual Lenovo de esta generación](https://download.lenovo.com/pccbbs/mobiles_pdf/x1carbon_x1yoga_ug_en.pdf):
  procedimiento de recuperación ante falta de respuesta del botón.

Estos casos justifican probar la hipótesis TPM, no garantizan que sea la causa
de este equipo. El fracaso desde una sola Live USB no demuestra una avería física.

## Prueba manual acordada y reversión

1. Apagar el sistema de forma ordenada; observar el estado físico por separado.
2. Entrar en BIOS y cambiar únicamente Security → Security Chip → Security Chip
   Selection de Intel PTT a Discrete TPM, conservando el chip habilitado.
3. No ejecutar Clear Security Chip. Si BIOS advierte de borrado de claves,
   detenerse y revisar el mensaje antes de aceptarlo.
4. Guardar y arrancar Debian. Comprobar desbloqueo de disco y sesión normal.
5. Revisar mensajes TPM del nuevo arranque y el dispositivo/controlador detectado.
6. Apagar desde Debian, esperar un minuto y observar ventilador e indicadores.
   Comprobar encendido mediante pulsación breve con las mismas condiciones
   de alimentación. Registrar el resultado y repetir para confirmar consistencia.

Si la prueba no mejora el comportamiento, evaluar regresar a Intel PTT. No se
ha demostrado aún reversibilidad de claves tras cambiar la selección; leer
cualquier advertencia de firmware. Esta prueba no necesita limpiar ningún TPM.

**Resultado pendiente:** no marcar como corregido hasta validar apagado físico
y encendido normal. La prueba de autonomía requiere medición separada.

## Lecciones para siguientes diagnósticos

### Actualización de la prueba — 2026-09-04, 18:12 CST

Al intentar seleccionar Discrete TPM, BIOS mostró: `All encryption keys will
be cleared in the security chip`. Se indicó cancelar esa operación. Como
alternativa, el usuario deshabilitó Security Chip sin recibir advertencia de
borrado y volvió a arrancar Debian. No se probó Discrete TPM.

Consulta del arranque de las 18:11 con el mismo kernel `7.1.12+deb14-amd64`:

```text
ima: No TPM chip found, activating TPM-bypass!
/sys/class/tpm: sin dispositivos
systemctl --failed: 0 loaded units listed
```

El filtro del journal de kernel no devolvió los anteriores timeouts TPM,
el error -62 ni el fallo DMAR. Esto confirma el cambio de disponibilidad del
TPM; no confirma todavía que el apagado físico y posterior encendido funcionen.
Se procederá a un apagado normal y observación manual del usuario.

### Criterios de interpretación

- No confundir desaparición de SSH, pantalla negra o `poweroff.target` con
  confirmación física de apagado.
- No atribuir el desfase UTC a falla RTC.
- No descartar un error TPM solo porque estaba presente anteriormente.
- Un initramfs legible y un arranque exitoso no verifican el apagado.
- No copiar parámetros ACPI ni blacklists sin comprobar versión y configuración.
- Conservar como hipótesis lo que todavía no se haya probado en el equipo.
