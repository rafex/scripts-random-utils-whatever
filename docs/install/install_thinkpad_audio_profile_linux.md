---
title: install_thinkpad_audio_profile_linux.sh
description: Instala EasyEffects y configura el procesamiento de salida de audio para la ThinkPad.
tags:
  - instalación
  - audio
  - thinkpad
---

# install_thinkpad_audio_profile_linux

Instala EasyEffects y configura un preset reversible de claridad vocal para los altavoces y auriculares cableados de la ThinkPad X1 Yoga 1.ª generación. El perfil independiente del micrófono se administra con `just install-thinkpad-microphone-profile`.

- **Ruta:** `scripts/install/install_thinkpad_audio_profile_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu)
- **Dependencias:** `dpkg-query`, `apt-get`, `sudo`, `pactl`, `python3`, PipeWire

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

- Debian/Ubuntu con PipeWire activo y `pactl` capaz de listar sinks en JSON.
- Ejecutar desde un checkout de este repositorio como usuario normal; `sudo` se usa solo para instalar el paquete.
- El sink analógico interno debe llamarse `alsa_output.pci-0000_00_1f.3.analog-stereo`, salvo que se configure otra identidad.

## Uso

`just install-thinkpad-audio-profile --apply` instala EasyEffects, copia el preset al área XDG del usuario, registra autocarga en las rutas de altavoces y auriculares, y crea el inicio automático al entrar en i3. No altera el volumen ni procesa el micrófono.

Para grabar con el micrófono interno, usa la tarea separada `just install-thinkpad-microphone-profile --apply`; permite mantener o revertir de forma independiente la cadena de captura y la entrada predeterminada.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba que EasyEffects y el preset estén instalados. |
| `--plan` | `--dry-run` | Muestra la instalación y los destinos sin modificar el sistema. |
| `--apply` | — | Instala el paquete y aplica el perfil con respaldos previos. |
| `--status` | — | Muestra el estado actual; devuelve éxito aunque falte el perfil. |
| `--rollback` | — | Restaura los archivos previos o elimina los creados por el instalador; conserva EasyEffects. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Los argumentos CLI seleccionan la acción. Las siguientes variables permiten adaptar la asociación al sink o a las descripciones de ruta reportadas por PipeWire:

| Variable | Predeterminado | Descripción |
|---|---|---|
| `EASYEFFECTS_DEVICE` | `alsa_output.pci-0000_00_1f.3.analog-stereo` | Nombre PipeWire del sink analógico. |
| `EASYEFFECTS_DEVICE_DESCRIPTION` | `Audio Interno Estéreo analógico` | Descripción del sink que se guarda en la regla. |
| `EASYEFFECTS_SPEAKER_ROUTE` | Detectado con `pactl` | Descripción de la ruta de altavoces. |
| `EASYEFFECTS_HEADPHONE_ROUTE` | Detectado con `pactl` | Descripción de la ruta de auriculares cableados. |
| `XDG_DATA_HOME` | `$HOME/.local/share` | Raíz de presets y reglas de EasyEffects. |
| `XDG_CONFIG_HOME` | `$HOME/.config` | Raíz del inicio automático. |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Respaldo usado por `--rollback`. |

## Ejemplos

Forma recomendada:

```bash
just install-thinkpad-audio-profile --check
just install-thinkpad-audio-profile --plan
just install-thinkpad-audio-profile --apply
```

Revertir los archivos de configuración:

```bash
just install-thinkpad-audio-profile --rollback
```

Si el nombre del sink difiere:

```bash
EASYEFFECTS_DEVICE=alsa_output.pci-0000_00_1f.3.analog-stereo just install-thinkpad-audio-profile --apply
```

## Protecciones de seguridad

- Crea archivos temporales y los renombra al destino después de escribirlos.
- Conserva los archivos previos de preset, autocarga e inicio automático en `$XDG_STATE_HOME/rafex/thinkpad-audio-profile` con permisos privados.
- La reversión restaura archivos anteriores o elimina solo los que el instalador agregó.
- La ecualización es moderada, reduce la ganancia de entrada 2 dB y no modifica el volumen ALSA/PipeWire.

## Fallos conocidos

### `no se pudieron leer las rutas ... con pactl`

**Causa:** PipeWire no está activo, el sink interno no está presente o `pactl` no puede emitir JSON.
**Solución:** comprobar `wpctl status` y definir `EASYEFFECTS_DEVICE`, `EASYEFFECTS_SPEAKER_ROUTE` y `EASYEFFECTS_HEADPHONE_ROUTE` si el dispositivo usa otros nombres.

### El preset no se carga tras instalar

**Causa:** EasyEffects aún no está ejecutándose en la sesión gráfica o las reglas no coinciden con la ruta actual.
**Solución:** iniciar `easyeffects --hide-window --service-mode`, revisar las rutas detectadas con `pactl --format=json list sinks` y ejecutar nuevamente `--apply`.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.0.0 — 2026-10-05

**feat:** añadir perfil EasyEffects de voces claras para la ThinkPad X1 Yoga.

- Instalar EasyEffects y asociar el preset al sink analógico, altavoces y auriculares cableados.
- Activar EasyEffects al inicio de i3 y permitir restaurar las configuraciones anteriores.
