---
title: install_picom_user_service_linux.sh
description: Instala el servicio de usuario de Picom iniciado por i3.
tags:
  - instalación
  - picom
  - systemd
  - i3
---

# install_picom_user_service_linux.sh

Instala `rafex-picom.service` como unidad systemd del usuario y prepara i3 para
iniciarla cuando la sesión X11 ya está disponible.

- **Ruta:** `scripts/install/install_picom_user_service_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `systemctl`, `picom`, configuración i3 y el runner versionado.

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

Ejecutar como el usuario de la sesión gráfica, nunca como `root`. El servicio
usa el Picom disponible en `~/.local/bin/picom` y, como alternativa,
`/usr/bin/picom`. El binario se selecciona al iniciar, no durante la
instalación.

La unidad se instala en:

```text
~/.config/systemd/user/rafex-picom.service
```

No se habilita con `default.target`: i3 importa `DISPLAY`, `XAUTHORITY` y
`DBUS_SESSION_BUS_ADDRESS` y ejecuta `systemctl --user start` después de que
X11 esté listo.

## Uso

```bash
just install-picom-user-service --check
just install-picom-user-service --plan
just install-picom-user-service --apply
just install-picom-user-service --status
```

Después de aplicar:

```bash
just picom-toggle --enable
i3-msg reload
just picom-toggle --check
systemctl --user status rafex-picom.service
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba fuentes, destinos y dependencias sin escribir. |
| `--plan` | — | Muestra la unidad, el runner, el override y el bloque i3 previstos. |
| `--apply` | — | Instala la unidad, el runner, el override de autostart y el bloque administrado de i3. |
| `--status` | — | Muestra instalación, preferencia, estado del servicio e integración. |
| `--replace-unmanaged` | — | Permite reemplazar archivos locales no administrados después de revisarlos; conserva respaldo. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | Directorio de configuración del usuario. |
| `I3_SERVICE_CONFIG` | `~/.config/i3/config` | Archivo i3 que recibe el bloque administrado. |

## Ejemplos

Flujo recomendado:

```bash
just install-picom-user-service --check
just install-picom-user-service --plan
just install-picom-user-service --apply
just picom-toggle --enable
i3-msg reload
```

Revisión sin cambios:

```bash
just install-picom-user-service --status
systemctl --user cat rafex-picom.service
```

Si existe una configuración manual en el destino, primero revisa el respaldo y
usa explícitamente:

```bash
just install-picom-user-service --apply --replace-unmanaged
```

## Protecciones de seguridad

- No usa `sudo`, APT, root ni servicios del sistema.
- No activa `graphical-session.target` ni el autostart completo de Cinnamon/GNOME.
- Desactiva solamente el autostart genérico de Picom mediante un override del usuario.
- i3 inicia una sola unidad; systemd mantiene el proceso con `Restart=on-failure`.
- Los archivos existentes no administrados se rechazan salvo con `--replace-unmanaged` y se respaldan antes.
- El runner exige Linux, usuario no root, `DISPLAY` y una configuración existente.
- `picom-toggle` solo detiene la unidad administrada; la compatibilidad legacy no mata procesos Picom con otra configuración.

## Fallos conocidos

### `graphical-session.target` aparece inactivo

**Causa:** i3 no siempre activa ese target en sesiones iniciadas por LightDM,
`startx` o un gestor X11 mínimo.

**Solución:** no es necesario activarlo. i3 importa el entorno X11 y arranca
directamente `rafex-picom.service`.

### `DISPLAY no está disponible`

**Causa:** se intentó iniciar la unidad desde una TTY o antes de que X11
estuviera listo.

**Solución:** inicia Picom desde i3 o ejecuta en una terminal gráfica:
`just picom-toggle --enable`.

### `rafex-picom.service` no inicia

**Causa:** configuración ausente, binario no ejecutable o error del backend
GLX/driver.

**Solución:** consulta `journalctl --user -u rafex-picom.service -b` y prueba
`just picom-toggle --disable`. i3 seguirá usable sin compositor.

### Aparece más de una instancia de Picom

**Causa:** quedó un autostart externo o una instancia legacy iniciada antes de
instalar la unidad.

**Solución:** revisa `pgrep -a -u "$USER" picom`, detén solo la instancia que
administres y verifica `~/.config/autostart/picom.desktop`.

## Changelog

### [Unreleased]
- `feat`: añade servicio de usuario de Picom iniciado de forma idempotente por i3.
