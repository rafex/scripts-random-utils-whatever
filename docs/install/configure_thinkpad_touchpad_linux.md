---
title: configure_thinkpad_touchpad_linux.sh
description: Configura scroll natural persistente únicamente para el touchpad ThinkPad.
tags:
  - instalación
  - xorg
  - touchpad
---

# configure_thinkpad_touchpad_linux.sh

Instala una regla Xorg/libinput para que el contenido se desplace en la misma
dirección que los dedos en el touchpad de la ThinkPad.

- **Ruta:** `scripts/install/configure_thinkpad_touchpad_linux.sh`
- **SO requerido:** Linux (Xorg)
- **Dependencias:** bash, sudo para `--apply`, Xorg/libinput; `xinput` opcional para el estado

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

La ThinkPad debe usar el driver `libinput`, como el dispositivo actual
`SynPS/2 Synaptics TouchPad`. El script instala el archivo en
`/etc/X11/xorg.conf.d/`; Xorg lo leerá al iniciar una nueva sesión gráfica.

## Uso

```bash
just configure-thinkpad-touchpad --check
just configure-thinkpad-touchpad --plan
just configure-thinkpad-touchpad --apply
just configure-thinkpad-touchpad --status
just configure-thinkpad-touchpad --rollback
```

Después de `--apply`, cierra y abre la sesión gráfica. No se reinicia Xorg ni
se apaga la máquina automáticamente.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida la plantilla y detecta conflictos sin escribir. |
| `--plan` | `--dry-run` | Muestra las acciones previstas. |
| `--status` | — | Muestra el archivo y la propiedad XInput actual. |
| `--apply` | — | Instala la regla y crea un respaldo administrado. |
| `--rollback` | — | Restaura el respaldo administrado más reciente. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de entorno. `DISPLAY` y `XAUTHORITY`, si están
disponibles, solo se usan para consultar el estado de XInput.

## Ejemplos

### Forma explícita recomendada

```bash
just configure-thinkpad-touchpad --apply
```

### Revisar sin modificar

```bash
just configure-thinkpad-touchpad --check
just configure-thinkpad-touchpad --plan
```

### Verificar después de reabrir Xorg

```bash
DISPLAY=:0 XAUTHORITY="$HOME/.Xauthority" \
  xinput list-props "SynPS/2 Synaptics TouchPad" \
  | grep "Natural Scrolling"
```

## Protecciones de seguridad

- Solo `--apply` y `--rollback` solicitan `sudo`.
- Se rechazan destinos existentes que no estén administrados por Rafex.
- Se detectan reglas Xorg manuales relacionadas antes de escribir.
- Se conserva un respaldo fechado, incluyendo el caso en que el archivo no existía.
- La regla solo coincide con dispositivos identificados como touchpad.
- No cambia TrackPoint, mouse externo, tapping, aceleración, DRM, Picom ni suspensión.
- No reinicia la sesión gráfica automáticamente.

## Fallos conocidos

### `DISPLAY no disponible`

**Causa:** el estado se consultó desde SSH o fuera de Xorg.

**Solución:** ejecuta `--status` desde la sesión gráfica o define
`DISPLAY` y `XAUTHORITY`. La instalación no depende de esa consulta.

### `hay reglas Xorg relacionadas no administradas`

**Causa:** existe una configuración manual que podría ganar prioridad o
duplicar `NaturalScrolling`/`libinput`.

**Solución:** revisa el archivo indicado y decide manualmente si debe
conservarse; el script no lo sobrescribe.

### `Natural Scrolling Enabled: 0` después de aplicar

**Causa:** la sesión Xorg actual cargó la configuración anterior.

**Solución:** cierra y vuelve a abrir la sesión gráfica. Si continúa en `0`,
ejecuta `--status` y revisa los registros de Xorg.

## Changelog

### [Unreleased]
- **feat:** añadir regla persistente de scroll natural solo para touchpad libinput.

### v1.0.0 — 2026-09-05

**feat:** versión inicial con respaldo y rollback.
