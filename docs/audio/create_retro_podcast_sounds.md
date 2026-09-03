# create_retro_podcast_sounds

Genera efectos sonoros originales en formato WAV para una cortinilla de podcast: un handshake de módem para separar secciones y una cortinilla chiptune de inspiración retro. Incluye cinco variantes alternativas del handshake para comparar.

- **Ruta:** `scripts/audio/create_retro_podcast_sounds.py`
- **SO requerido:** macOS, Linux
- **Dependencias:** Python 3.10 o superior

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

- Python 3.10 o superior.
- Espacio de escritura en `assets/audio/`.

## Uso

```bash
python3 scripts/audio/create_retro_podcast_sounds.py
```

Genera archivos mono WAV PCM de 44.1 kHz y 16 bits en `assets/audio/`. Conserva `modem_section_transition.wav` y además crea `modem_section_transition_v1.wav` a `modem_section_transition_v5.wav`.

## Opciones

El script no tiene opciones CLI.

| Opción | Alias | Descripción |
|---|---|---|
| — | — | La duración, afinación y carpeta de salida están definidas en el script. |

## Variables de entorno

No utiliza variables de entorno.

## Ejemplos

### Forma explícita/recomendada

```bash
python3 scripts/audio/create_retro_podcast_sounds.py
```

### Uso con Audacity

Importa `assets/audio/modem_section_transition.wav`, cualquiera de sus cinco variantes y `assets/audio/retro_chiptune_curtain.wav` en Audacity. Mezcla la cortinilla chiptune bajo la voz y usa el efecto de módem entre secciones.

## Protecciones de seguridad

- Solo escribe los archivos de audio generados dentro de `assets/audio/`.
- No sobrescribe los archivos originales `modem_section_transition.wav` ni `retro_chiptune_curtain.wav` si ya existen.
- No modifica ni elimina proyectos existentes de Audacity.
- Los sonidos son sintetizados y no contienen grabaciones de terceros.

## Fallos conocidos

### `PermissionError` al crear los archivos

**Causa:** no hay permisos de escritura en `assets/audio/`.
**Solución:** ejecuta el script desde una copia de trabajo con permisos de escritura.

## Changelog

### [Unreleased]

- Generación inicial de efectos retro originales para podcast.
