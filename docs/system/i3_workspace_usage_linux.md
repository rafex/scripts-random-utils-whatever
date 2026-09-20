---
title: i3_workspace_usage_linux.py
description: Registra uso agregado privado de ventanas i3 y propone workspaces ThinkPad.
tags:
  - sistema
  - i3
  - thinkpad
---

# i3_workspace_usage_linux.py

Registra de forma local el tiempo en foco y las activaciones por clase e
instancia de ventana. Genera un borrador de workspaces y reglas `assign` para
revisar manualmente; no modifica i3.

- **Ruta:** `scripts/system/i3_workspace_usage_linux.py`
- **SO requerido:** Linux
- **Dependencias:** `python3`, `i3-msg`, i3/X11; `systemd --user` para el daemon instalado.

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

El modo `--daemon` se ejecuta solamente en una sesión i3/X11 con `DISPLAY` e
IPC disponible. El uso normal se instala para el perfil
`thinkpad-x1-yoga-1st`; los informes se pueden consultar sin una sesión gráfica.

## Uso

```bash
just i3-workspace-usage --status
just i3-workspace-usage --report
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--daemon` | — | Escucha eventos de ventana y workspace de i3; lo usa la unidad de usuario. |
| `--status` | — | Muestra ruta y tamaño del estado agregado. |
| `--report` | — | Imprime el borrador de nombres y reglas `assign`. |
| `--output <archivo>` | — | Guarda el informe con permisos `0600`; requiere `--report`. |
| `--reset --yes` | — | Elimina el único archivo de estado del registrador tras confirmación explícita. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_STATE_HOME` | `~/.local/state` | Raíz del estado privado; se usa `rafex/i3-workspace-usage.json`. |
| `DISPLAY` | — | Requerido únicamente por `--daemon` para conectar con i3. |
| `I3SOCK` | — | Socket IPC opcional que consume `i3-msg`. |

No hay `.env`. La configuración de i3 no es una entrada del script: el informe
es un borrador que debe revisarse e incorporarse manualmente.

## Ejemplos

```bash
# Forma recomendada: instalar el servicio exclusivo de la ThinkPad.
just install-i3-workspace-usage --apply

# Consultar evidencia y generar un fragmento privado para revisar.
just i3-workspace-usage --status
just i3-workspace-usage --report --output "$HOME/.local/state/rafex/i3-workspaces-draft.conf"

# Inspección manual directa, compatible con una sesión i3 ya activa.
python3 scripts/system/i3_workspace_usage_linux.py --report
```

## Protecciones de seguridad

- Solo conserva `WM_CLASS`, instancia, número de workspace, segundos de foco,
  activaciones y la última fecha observada.
- No registra títulos, URL, texto de documentos, historial crudo, pulsaciones,
  red ni credenciales.
- El estado y los informes escritos usan permisos `0600`; su directorio usa
  `0700`.
- Las clases desconocidas se muestran como reglas `assign` comentadas.
- Nunca escribe `~/.config/i3/config`, reinicia i3 ni aplica las propuestas.
- La unidad no se habilita globalmente: i3 la inicia con el socket de su sesión.

## Fallos conocidos

### `DISPLAY no está disponible`

**Causa:** el daemon se inició fuera de i3/X11 o sin importar su entorno.
**Solución:** instala el componente y reinicia i3 para que su autostart importe
las variables de sesión antes de iniciar la unidad.

### `estado inválido`

**Causa:** el archivo privado fue editado manualmente o pertenece a una versión
incompatible.
**Solución:** guarda una copia si la necesitas y ejecuta `just i3-workspace-usage --reset`.

## Changelog

### [Unreleased]

- **feat:** registrar uso agregado y privado de workspaces i3 para el perfil ThinkPad.
