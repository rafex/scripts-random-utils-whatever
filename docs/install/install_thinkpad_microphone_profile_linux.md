---
title: install_thinkpad_microphone_profile_linux.sh
description: Configura EasyEffects y la entrada de micrófono para grabaciones en la ThinkPad.
tags:
  - instalación
  - audio
  - thinkpad
---

# install_thinkpad_microphone_profile_linux

Configura EasyEffects para reducir ruido de fondo y controlar picos al grabar con el micrófono interno de la ThinkPad X1 Yoga 1.ª generación.

- **Ruta:** `scripts/install/install_thinkpad_microphone_profile_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** EasyEffects, `pactl`, PipeWire/PulseAudio, `python3`, `dpkg-query`, `apt-get`, `sudo`

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

- ThinkPad X1 Yoga 1.ª generación con PipeWire y el origen analógico del micrófono interno visible mediante `pactl`.
- Ejecutar como usuario normal. `sudo` se usa solo para instalar EasyEffects desde Debian.

## Uso

La tarea independiente vuelve a aplicar el preset, su autocarga, el inicio de EasyEffects en la sesión y la entrada predeterminada procesada:

```bash
just install-thinkpad-microphone-profile --apply
```

La cadena de entrada usa RNNoise, compresión moderada y limitación de picos. EasyEffects expone el audio procesado como `easyeffects_source`; el instalador lo selecciona como entrada predeterminada para las aplicaciones.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba EasyEffects, preset, autocarga y entrada predeterminada. |
| `--plan` | `--dry-run` | Muestra cambios y valida la ruta del micrófono. |
| `--apply` | — | Instala EasyEffects si hace falta y aplica el perfil completo. |
| `--status` | — | Informa del estado sin fallar si faltan componentes. |
| `--rollback` | — | Restaura preset, autocarga, helper, autostart y entrada predeterminada anterior. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos CLI seleccionan la acción. Estas variables adaptan el dispositivo y los destinos de usuario:

| Variable | Predeterminado | Descripción |
|---|---|---|
| `EASYEFFECTS_MIC_SOURCE` | `alsa_input.pci-0000_00_1f.3.analog-stereo` | Nombre del origen de audio del micrófono interno. |
| `EASYEFFECTS_MIC_ROUTE` | `analog-input-internal-mic` | Puerto de entrada que debe asociarse al preset. |
| `XDG_DATA_HOME` | `~/.local/share` | Base de presets y reglas de EasyEffects. |
| `XDG_CONFIG_HOME` | `~/.config` | Destino del autostart de sesión. |
| `XDG_STATE_HOME` | `~/.local/state` | Respaldos usados para rollback. |
| `XDG_BIN_HOME` | `~/.local/bin` | Destino del helper persistente de sesión. |

## Ejemplos

Forma recomendada:

```bash
just install-thinkpad-microphone-profile --check
just install-thinkpad-microphone-profile --plan
just install-thinkpad-microphone-profile --apply
```

Comprobar la configuración activa:

```bash
just install-thinkpad-microphone-profile --status
pactl get-default-source
```

Revertir el perfil:

```bash
just install-thinkpad-microphone-profile --rollback
```

Si el origen de hardware reporta otro nombre:

```bash
EASYEFFECTS_MIC_SOURCE=alsa_input.pci-0000_00_1f.3.analog-stereo \
EASYEFFECTS_MIC_ROUTE=analog-input-internal-mic \
  just install-thinkpad-microphone-profile --apply
```

## Protecciones de seguridad

- Antes de reemplazar archivos conserva copias privadas bajo `$XDG_STATE_HOME/rafex/thinkpad-microphone-profile`.
- El helper y la entrada de autostart son archivos de usuario; no requieren privilegios root.
- `--rollback` vuelve a seleccionar el origen predeterminado guardado antes de aplicar el perfil. EasyEffects permanece instalado.
- La cadena no añade ganancia de entrada y limita picos para reducir recorte digital.

## Fallos conocidos

### `no se encontró el micrófono o el puerto solicitado`

**Causa:** el nombre del origen o del puerto difiere del predeterminado, o el micrófono no está disponible.
**Solución:** consulta `pactl --format=json list sources` y define `EASYEFFECTS_MIC_SOURCE` y `EASYEFFECTS_MIC_ROUTE`.

### `EasyEffects Source no apareció después de iniciar EasyEffects`

**Causa:** EasyEffects no inició su servidor virtual o PipeWire no está listo.
**Solución:** consulta `systemctl --user status pipewire pipewire-pulse wireplumber`, inicia EasyEffects y vuelve a ejecutar `--apply`.

### La aplicación no graba aunque EasyEffects Source sea la entrada predeterminada

**Causa:** la aplicación mantiene seleccionado un dispositivo de captura anterior.
**Solución:** vuelve a seleccionar el dispositivo predeterminado o `Easy Effects Source` en los ajustes de entrada de esa aplicación.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.0.0 — 2026-10-06

**feat:** añadir perfil de captura para el micrófono interno ThinkPad.

- Autocargar RNNoise, compresión moderada y limitador para la entrada analógica interna.
- Iniciar EasyEffects al entrar en sesión y establecer su origen virtual como entrada predeterminada.
- Guardar el estado previo y permitir rollback.
