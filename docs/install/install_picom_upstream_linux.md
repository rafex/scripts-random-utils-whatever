---
title: install_picom_upstream_linux.sh
description: Ruta histórica de Picom upstream, retirada del perfil ThinkPad estable.
tags:
  - instalación
  - picom
  - i3
---

# install_picom_upstream_linux.sh

Esta receta queda conservada como referencia histórica. El perfil ThinkPad
estable usa exclusivamente Picom v13 de Debian y `rafex-picom.service`; por
ello `--apply` se rechaza y nunca vuelve a escribir `~/.local/bin/picom`.

- **Ruta:** `scripts/install/install_picom_upstream_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, git, Meson, Ninja, pkg-config, compilador C, dependencias de desarrollo X11/GLX y sudo únicamente para APT.

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

No requiere nada para `--check`, `--plan` o `--status`. Para administrar el
compositor usa las recetas actuales `just picom-debian --apply` y
`just install-picom-user-service --apply`.

## Uso

```bash
just install-picom-upstream --check
just install-picom-upstream --plan
just install-picom-upstream --status
```

Para instalar o reiniciar la configuración vigente:

```bash
just picom-debian --apply
just install-picom-user-service --apply
just picom-debian --reload
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el entorno, las dependencias y el plan sin escribir. |
| `--plan` | — | Muestra origen, commit, rutas y paquetes faltantes sin escribir. |
| `--apply` | — | Se rechaza para proteger la autoridad única de Picom Debian. |
| `--status` | — | Muestra cualquier instalación upstream heredada sin activarla. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

Este instalador no requiere variables de entorno. Las rutas se derivan de
`$HOME` y de `XDG_CONFIG_HOME`/`XDG_DATA_HOME` si están definidos.

## Ejemplos

```bash
# La receta histórica solo informa; no compila ni instala.
just install-picom-upstream --check
just install-picom-upstream --plan
just install-picom-upstream --status
```

## Protecciones de seguridad

- `--apply` falla antes de instalar dependencias, compilar o escribir archivos.
- El perfil estable no consulta `PATH` ni `~/.local/bin/picom`; el servicio
  usa explícitamente `/usr/bin/picom`.
- Las instalaciones upstream heredadas se detectan con
  `just thinkpad-config-audit --status` antes de retirarlas manualmente.

## Fallos conocidos

### `Picom upstream está retirado para esta ThinkPad`

**Causa:** coexistían dos binarios y dos posibles propietarios para el mismo
compositor.

**Solución:** usa `just picom-debian --apply` y
`just install-picom-user-service --apply`.

### `commit inesperado para v13`

**Causa:** la etiqueta remota cambió, el checkout local fue alterado o el
origen no es el repositorio oficial.

**Solución:** no fuerces la compilación. Conserva el árbol para inspección y
revisa la etiqueta y su firma en el repositorio oficial antes de actualizar el
commit fijado en este script.

### `Picom no inicia con la configuración visual`

**Causa:** GLX, blur o el controlador gráfico pueden no funcionar bien en una
sesión concreta; también puede existir otra instancia activa.

**Solución:** vuelve a `just picom-toggle --disable` y prueba la configuración
con blur desactivado temporalmente. El paquete de Debian no se elimina y el
binario anterior queda disponible en los respaldos fechados.

### `shader compilation failed` o colores inesperados

**Causa:** el driver GLX no admite la versión GLSL solicitada o se seleccionó
una variante de paleta que no corresponde al tema actual.

**Solución:** cambia temporalmente la regla de Alacritty a
`shader = "shaders/neutral.glsl";`, reinicia Picom y revisa los logs. Si el
problema persiste, desactiva el compositor; blur, transparencia y Picom no son
requisitos para que i3 siga funcionando.

## Changelog

### [Unreleased]

- **fix:** retirar la compilación upstream de la ruta estable ThinkPad para
  dejar Picom Debian como única autoridad.

### v1.0.1 — 2026-09-05

**fix:** restaurar automáticamente el binario y la configuración anteriores si
el reemplazo atómico falla.
