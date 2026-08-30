---
title: install_openbox_profile_linux.sh
description: Instala el perfil Openbox paralelo y ligero para la ThinkPad X1 Yoga.
tags:
  - instalación
  - openbox
  - thinkpad
---

# install_openbox_profile_linux.sh

Instala Openbox y tint2 junto con un perfil paralelo para la ThinkPad. No
reemplaza i3 ni cambia la sesión predeterminada de LightDM.

- **Ruta:** `scripts/install/install_openbox_profile_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `sudo`, `dpkg-query`, `apt-get`; el perfil instala Openbox, tint2, tmux, Rofi y los scripts portables del repositorio.

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

- Ejecutar como usuario normal con `sudo`.
- Tener el repositorio completo y una sesión Xorg para validar el resultado.
- i3 puede permanecer instalado como entorno de recuperación.

## Uso

```bash
just install-openbox-profile --dry-run
just install-openbox-profile
```

Tras aplicar, cierra sesión y selecciona **Openbox** en LightDM. Para volver a
i3, selecciónalo nuevamente en el mismo menú.

Sin opciones, la tarea ejecuta la aplicación del perfil. Usa `--check` o
`--dry-run` cuando solo quieras inspeccionar.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Revisa paquetes, fuentes y configuración sin cambios. |
| `--plan` | `--dry-run` | Muestra el plan sin modificar el sistema. |
| `--apply` | — | Instala paquetes y copia el perfil. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El instalador no requiere variables de entorno. Las rutas se calculan desde el
directorio del repositorio y `$HOME`.

## Ejemplos

Instalación recomendada:

```bash
just install-openbox-profile
```

Inspección sin cambios:

```bash
just install-openbox-profile --check
just install-openbox-profile --plan
```

## Protecciones de seguridad

- Solicita la contraseña solo mediante `sudo -v`.
- No almacena credenciales.
- No modifica i3, Xorg, GPU, DRI, LUKS, GRUB, `fstab` ni LightDM.
- Respaldar configuraciones existentes es responsabilidad del instalador de
  perfiles antes de reemplazar archivos de usuario.

## Fallos conocidos

### `Openbox no aparece en LightDM`

**Causa:** el paquete no se instaló correctamente o el display manager no ha
recargado sus sesiones.

**Solución:** confirma `dpkg -s openbox`, cierra sesión completamente y revisa
que exista `/usr/share/xsessions/openbox.desktop`.

### `Una aplicación abre en otro escritorio`

**Causa:** Openbox usa `WM_CLASS` y no entiende literalmente las reglas
`assign` de i3.

**Solución:** ejecuta `xprop WM_CLASS`, compara el valor con `~/.config/openbox/rc.xml`
y ajusta una regla específica.

## Changelog

### [Unreleased]

- `feat`: añade perfil Openbox paralelo con tint2 y diez escritorios.
