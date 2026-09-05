---
title: configure_lid_suspend_linux.sh
description: Suspensión al cerrar la tapa con systemd-logind
tags:
  - hardware
  - thinkpad
---

# configure_lid_suspend_linux.sh

Configura suspensión al cerrar la tapa con batería o cargador. No suspende ni
reinicia el equipo durante la instalación.

- **Ruta:** `scripts/hardware/configure_lid_suspend_linux.sh`
- **SO requerido:** Linux (usa systemd-logind y sysfs; no compatible con macOS)
- **Dependencias:** Bash, systemd, awk, grep, herramientas Unix; sudo para aplicar como usuario

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

Linux con logind activo y suspensión `mem` anunciada por el kernel. Esta última
no garantiza que el hardware reanude correctamente. Probar suspensión/reanudación
manualmente antes de confiar en ella; en esta ThinkPad hubo problemas previos de
energía relacionados provisionalmente con TPM. No se modifica ese ajuste.

## Uso

```bash
just configure-lid-suspend --check
just configure-lid-suspend --plan
just configure-lid-suspend --apply
just configure-lid-suspend --status
```

Instala `/etc/systemd/logind.conf.d/90-rafex-lid-suspend.conf`. **Requiere reinicio
manual**: no reinicia logind para evitar interrumpir sesiones. `--status` muestra
configuración en disco e inhibidores, no certifica que logind ya la haya cargado.
La política usa suspend para batería/cargador/dock y respeta inhibidores de sueño.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnóstico y detección de conflictos; predeterminado. |
| `--plan` | — | Muestra política propuesta sin escribir. |
| `--status` | — | Muestra estado y opciones presentes, sin escribir. |
| `--apply` | — | Instala configuración con permisos root:root 0644. |
| `--docked suspend\|ignore` | — | Comportamiento con dock o varios monitores; por defecto suspend. |
| `--help` | `-h` | Ayuda. |

## Variables de entorno

| Variable | Uso |
|---|---|
| `PATH` | Localiza utilidades del sistema. Usar un PATH confiable. |

No usa `.env` ni variables de configuración. Las opciones CLI deciden la política.

## Ejemplos

```bash
# Suspender también con monitor externo
just configure-lid-suspend --apply
# Mantener el equipo encendido con tapa cerrada y monitor externo/dock
just configure-lid-suspend --apply --docked ignore
# Diagnóstico con entorno explícito
PATH=/usr/sbin:/usr/bin:/sbin:/bin bash scripts/hardware/configure_lid_suspend_linux.sh --check
```

Después de reiniciar manualmente, guardar trabajo, cerrar la tapa y probar
reanudación con batería y cargador. Verificar el bloqueo de pantalla por separado;
este script no lo configura. Consultar `journalctl -b -u systemd-logind` y
`journalctl -b -u systemd-suspend.service`. La conexión SSH se perderá al suspender.

## Protecciones de seguridad

No instala paquetes, no altera i3/Openbox, TPM, GRUB, TLP, s2idle/deep ni inhibidores.
Rechaza un destino no administrado, enlaces y opciones explícitas contradictorias
en otros archivos leídos por logind. No reescribe estos últimos. Cambios idénticos
no generan otro respaldo. Cada modificación del drop-in existente conserva una
copia `.bak-FECHA.XXXXXX` y usa reemplazo atómico.

Reversión: restaurar con sudo la copia exacta indicada sobre el drop-in y reiniciar
manualmente. Si era la primera instalación, retirar solo el drop-in administrado
y reiniciar; no borrar el directorio ni otros archivos. No hay reinicio automático.

## Fallos conocidos

### `Opciones conflictivas`

**Causa:** otro archivo declara valores diferentes, incluso si tendría menor prioridad.
**Solución:** revisar el archivo indicado y decidir manualmente qué política conservar.

### La tapa no suspende aunque el archivo está instalado

**Causa:** falta reiniciar, un escritorio posee `handle-lid-switch`, un inhibidor
de sueño está activo o el sensor no genera eventos. Logind puede esperar unos
30 segundos tras arrancar/reanudar antes de procesar la tapa.
**Solución:** revisar los inhibidores y registros; no matar procesos ni forzar la
suspensión ignorando bloqueos. Si un escritorio controla la tapa, configurar allí
su política después de identificarlo.

### Suspende pero no reanuda

**Causa:** posible problema independiente de firmware/controlador/hardware.
**Solución:** dejar de probar automáticamente; revisar registros y diagnóstico
de energía. Esta política no soluciona fallos de reanudación.

Los ajustes, la prioridad de drop-ins y los inhibidores están documentados en el
[manual de logind de Debian](https://manpages.debian.org/testing/systemd/logind.conf.5.en.html).

## Changelog

### v1.0.0 — 2026-09-05

**feat:** política de tapa idempotente, dock configurable, diagnóstico y respaldo,
sin reiniciar sesiones ni forzar suspensión durante apply.
