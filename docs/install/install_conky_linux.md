---
title: install_conky_linux.sh
description: Instala Conky y un panel lateral seguro para i3 y Openbox en la ThinkPad.
tags:
  - instalación
  - conky
  - thinkpad
---

# install_conky_linux.sh

Instala `conky-all` desde Debian y configura un panel informativo transparente
en la esquina superior derecha, debajo de i3bar o tint2. El panel no reserva
espacio, no roba el foco y funciona tanto con i3 como con Openbox.

- **Ruta:** `scripts/install/install_conky_linux.sh`
- **SO requerido:** Linux (Debian o derivada)
- **Dependencias:** `bash`, `sudo`, `apt-get`, `apt-cache`, `i3` opcional, `conky-all`

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

Se recomienda haber instalado el perfil `thinkpad-x1-yoga-1st`. La instalación
de paquetes requiere `sudo`; la configuración de usuario y el arranque normal
de Conky no requieren privilegios elevados.

## Uso

```bash
just install-conky --check
just install-conky --plan
just install-conky --apply
just install-conky --status
just conky-status
```

El instalador copia la plantilla a `~/.config/conky/conky.conf`, el helper a
`~/.local/bin/conky-status.sh` y el lanzador a
`~/.local/bin/conky-launch.sh`. La instancia se inicia al entrar en i3 u
Openbox.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Verifica Debian, el candidato APT, las plantillas y el estado sin escribir. |
| `--plan` | `--dry-run` | Muestra la instalación e integración previstas sin escribir. |
| `--apply` | — | Instala `conky-all`, copia la configuración y añade los bloques administrados. |
| `--status` | — | Muestra archivos, bloques, número de instancias y presencia de `DISPLAY`. |
| `--help` | `-h` | Muestra la ayuda. |

El helper admite `--section network`, `--section power`, `--section temperature`,
`--section audio`, `--section lab` y `--section security`; consulta su
documentación para el detalle.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Base de la configuración de Conky, i3 y Openbox. |
| `CONKY_CONFIG` | `~/.config/conky/conky.conf` | Ruta de configuración usada por el lanzador. |
| `XDG_RUNTIME_DIR` | `~/.cache` | Directorio base del PID privado del lanzador. |

No se leen archivos `.env` ni se aceptan credenciales.

## Ejemplos

### Instalación recomendada

```bash
just install-conky --check
just install-conky --plan
just install-conky --apply
```

### Diagnóstico sin sesión gráfica

```bash
just install-conky --status
just conky-status --check
```

Es normal que `DISPLAY=ausente` aparezca por SSH; el diagnóstico no intenta
abrir una ventana en ese caso.

### Recargar después de cambiar el tema

```bash
~/.local/bin/theme-toggle.sh --set nord
~/.local/bin/conky-launch.sh --reload
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura y no usan `sudo`.
- `--apply` usa `sudo` solo para instalar `conky-all` mediante APT.
- Se respaldan los archivos de usuario existentes antes de reemplazarlos.
- Los bloques de i3 y Openbox se reemplazan por sus marcadores, sin duplicarse.
- El lanzador solo detiene su propio PID; nunca mata instancias ajenas.
- El panel no muestra SSID, IP, IMEI, IMSI, APN, nombres de archivos,
  credenciales, puertos ni comandos completos.
- No modifica i3bar, i3status, tint2, Xorg, NetworkManager, WWAN ni Picom.

## Fallos conocidos

### `conky-all no tiene candidato APT`

**Causa:** las fuentes Debian no están disponibles o no se actualizaron.

**Solución:** revisa las fuentes APT y vuelve a ejecutar `apt-get update`; no
se añade ningún repositorio externo.

### `Conky no se inicia: no existe DISPLAY.`

**Causa:** el comando se ejecutó por SSH o fuera de la sesión X11.

**Solución:** inicia Conky desde i3/Openbox o ejecuta el lanzador dentro de la
sesión gráfica local.

### `existe otra instancia Conky del usuario`

**Causa:** hay otra instancia que no pertenece al PID administrado por Rafex.

**Solución:** el lanzador no la detiene. Revisa `pgrep -a conky` y decide
manualmente si esa instancia es necesaria.

## Changelog

### [Unreleased]

- `feat`: añade instalación e integración idempotente del panel Conky.
