# usb_mount_perms_linux.sh

Diagnostica y corrige permisos para montar/desmontar USB sin sudo en Linux (Debian/Ubuntu). Crea las reglas necesarias de polkit y udev, y configura udiskie para auto-montaje en i3.

- **Ruta:** `scripts/hardware/usb_mount_perms_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `pkaction`, `systemctl`, `loginctl` (todas presentes en Debian/Ubuntu base)

---

## Requisitos

- **polkit ≥ 0.106** (reglas JS en `/etc/polkit-1/rules.d/`). Debian 10+, Ubuntu 18.04+.
- `udisks2` para montaje por CLI (`udisksctl`).
- `udiskie` para auto-montaje (opcional, recomendado en i3/Xorg).

---

## Uso

```sh
./scripts/hardware/usb_mount_perms_linux.sh [opciones]
```

## Opciones

| Opción | Descripción |
|---|---|
| `--check` | Diagnostica permisos USB sin modificar nada (default) |
| `--fix` | Aplica todas las correcciones necesarias (requiere sudo) |
| `--dry-run` | Muestra los comandos sin ejecutarlos (útil con `--fix`) |
| `-h, --help` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `USB_PERMS_GROUP` | `plugdev` | Grupo que tendrá permisos de montaje |
| `I3_CONFIG` | `~/.config/i3/config` | Ruta al archivo de configuración de i3 |

---

## Ejemplos

### Modo diagnóstico (sin sudo)

```sh
# Solo revisar el estado actual, sin modificar nada
./scripts/hardware/usb_mount_perms_linux.sh --check
```

### Modo corrección

```sh
# Aplicar todas las correcciones
./scripts/hardware/usb_mount_perms_linux.sh --fix
```

### Simular cambios

```sh
# Ver qué se haría sin aplicar nada
./scripts/hardware/usb_mount_perms_linux.sh --fix --dry-run
```

### Con grupo personalizado

```sh
USB_PERMS_GROUP=storage ./scripts/hardware/usb_mount_perms_linux.sh --fix
```

### Forma recomendada (instalado en PATH)

Una vez copiado a `~/.local/bin/usb-mount-perms`:

```sh
usb-mount-perms --check   # diagnosticar
usb-mount-perms --fix      # corregir
```

---

## Qué corrige (modo `--fix`)

| Corrección | Archivo | Detalle |
|---|---|---|
| Regla polkit | `/etc/polkit-1/rules.d/10-udisks2-mount.rules` | Permite `mount/unmount/eject/power-off` sin auth al grupo `plugdev` |
| Regla udev | `/etc/udev/rules.d/99-usb-storage.rules` | Otorga `MODE=0660, GROUP=plugdev` a dispositivos de bloque USB |
| Grupo usuario | `usermod -aG plugdev` | Agrega al usuario al grupo de montaje si no está ya |
| i3 config | `~/.config/i3/config` | Activa `udiskie --tray` para auto-montaje y habilita `dbus-update-activation-environment` para registro de sesión |
| udiskie config | `~/.config/udiskie/config.yml` | Auto-montaje al insertar, notificaciones, ignorar discos de sistema |

---

## Protecciones de seguridad

- El script **nunca modifica** nada en modo `--check` (default).
- Las reglas polkit se limitan al grupo `plugdev` — otros usuarios sin el grupo no heredan los permisos.
- La regla udev solo afecta dispositivos USB (`ENV{ID_BUS}=="usb"`), no discos internos.
- La config de udiskie ignora explícitamente `/dev/sda*`, `/dev/nvme*` y `/dev/mmcblk*` (discos de sistema).
- El modo `--dry-run` permite previsualizar todos los cambios antes de aplicarlos.

---

## Fallos conocidos

### `polkit < 0.106 usa archivos .pkla, no rules.d`

**Causa:** Versión antigua de polkit sin soporte para reglas JavaScript.
**Solución:** Usar una distro moderna (Debian 9 tuvo polkit 0.105, Debian 10+ usa 0.106+).

### `udisksctl mount` sigue pidiendo contraseña tras aplicar `--fix`

**Causa:** El usuario no ha cerrado sesión y vuelto a entrar; los cambios de grupo (`usermod -aG`) requieren nueva sesión.
**Solución:** Cerrar sesión de i3 (Mod+Shift+E) y volver a entrar.

### `udiskie` no se inicia automáticamente tras `--fix`

**Causa:** i3 necesita ser recargado (`Mod+Shift+R`).
**Solución:** Recargar i3 con `Mod+Shift+R` o reiniciar la sesión X.

### Sin polkit agent en i3, los prompts de auth fallan silenciosamente

**Causa:** i3 no incluye un agente de polkit por defecto.
**Solución:** El script lo detecta en modo `check`. Instalar `lxpolkit` o `ukui-polkit` y asegurarse de que arranque en la sesión X (vía `dex --autostart` o manualmente en el config de i3).

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-08-02

**feat:** Script inicial de diagnóstico y corrección de permisos de montaje USB sin sudo.

- Modos `check`, `fix` y `dry-run`
- Regla polkit JS para `org.freedesktop.udisks2.*` sin auth para `plugdev`
- Regla udev para dispositivos de bloque USB (`GROUP=plugdev, MODE=0660`)
- Configuración de `udiskie` para auto-montaje en i3
- Activación de `dbus-update-activation-environment` en i3 para registro de sesión
- Verificación de sesión logind, XDG vars, acciones polkit y dispositivos conectados
