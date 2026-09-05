---
title: i3_bar_profile_linux.sh
description: Selecciona una única barra activa para i3.
tags:
  - sistema
  - i3
  - barras
---

# i3_bar_profile_linux.sh

Selecciona `i3bar`, `tint2` o `polybar` en i3 sin duplicar barras ni tocar
Conky, EWW, Picom u Openbox. Tint2 muestra el taskbar nativo del workspace
actual; Polybar usa el helper de ventanas administrado por Rafex.

- **Ruta:** `scripts/system/i3_bar_profile_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `dpkg-query`, `grep`, `i3-msg`; opcionales `sudo`, `tint2` y `polybar`.

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

Ejecuta primero `just install-i3-bar-profiles --apply`. El archivo de i3 debe
incluir únicamente `~/.config/i3/rafex-bar-active.conf`. Polybar se instala
desde Debian solo al seleccionarlo; no se compila ni se añade al perfil base.

## Uso

```bash
just i3-bar --check
just i3-bar --plan --set polybar
just i3-bar --status
just i3-bar --set i3bar
just i3-bar --set tint2
just i3-bar --set polybar
just i3-bar --reload
just i3-bar --rollback
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba fuentes, i3 y posibles conflictos. |
| `--plan` | — | Muestra el cambio previsto; puede combinarse con `--set`. |
| `--status` | — | Muestra el perfil, paquetes y runtime externo. |
| `--set <perfil>` | — | Activa `i3bar`, `tint2` o `polybar`; instala la dependencia opcional si falta. |
| `--reload` | — | Recarga i3 para aplicar el archivo activo. |
| `--rollback` | — | Restaura el respaldo más reciente del archivo activo. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio de configuración del usuario. |

El runtime usa `XDG_RUNTIME_DIR` para PID files y lock. No se usan archivos
`.env` ni variables para introducir comandos.

## Ejemplos

```bash
# Mantener el comportamiento actual.
just i3-bar --set i3bar

# Probar Tint2 y volver al fallback.
just i3-bar --set tint2
just i3-bar --status
just i3-bar --set i3bar

# Polybar instala su paquete Debian solo en esta selección.
just i3-bar --plan --set polybar
just i3-bar --set polybar
```

## Protecciones de seguridad

- `i3bar` permanece como perfil inicial y de recuperación.
- Se rehúsa sobrescribir un archivo activo no administrado.
- La selección usa reemplazo atómico y respalda el estado anterior.
- La recarga se ejecuta solo cuando existe `DISPLAY` e `i3-msg`.
- Las acciones de Polybar apuntan únicamente a helpers versionados del perfil.
- Tint2 y Polybar solo enfocan ventanas con clic izquierdo; no añaden cierres ni
  minimización.
- El selector no usa `pkill` global ni detiene procesos Tint2/Polybar ajenos.

## Fallos conocidos

### `se rehúsa sobrescribir un active bar no administrado`

**Causa:** `rafex-bar-active.conf` existe, pero no tiene el marcador Rafex.

**Solución:** conserva el archivo manual y elige explícitamente cómo integrarlo.

### `i3 rechazó la recarga; se restauró el perfil anterior`

**Causa:** i3 no aceptó la configuración activa o una dependencia externa falló.

**Solución:** ejecuta `i3 -C -c ~/.config/i3/config`, corrige el problema y
repite la selección.

## Changelog

### [Unreleased]

- **feat:** añadir selector de i3bar, Tint2 y Polybar con fallback y rollback.
