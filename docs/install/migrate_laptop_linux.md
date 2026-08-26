# migrate_laptop_linux.sh

Audita y prepara una ThinkPad Debian a partir de una laptop Debian fuente,
transfiriendo únicamente configuración portable y sin copiar secretos.

- **Ruta:** `scripts/install/migrate_laptop_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `ssh`, `sudo`, `apt-get`, `systemctl`

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

- Ejecutar como el usuario normal de la ThinkPad, no como root.
- Para `--apply`, `sudo` debe estar instalado y el usuario debe pertenecer al
  grupo `sudo`. Esta instalación recién hecha puede requerir una preparación
  única desde una consola root:

  ```sh
  su -
  cd /home/rafex/scripts-random-utils-whatever
  just configure-sudo --user rafex --apply
  ```

  Cierra la sesión y vuelve a entrar antes de ejecutar una etapa `--apply`.
- Tener acceso SSH por clave a la laptop fuente o usar una sesión SSH ya
  configurada.
- La fuente predeterminada es `rafex@192.168.3.174`.
- La ThinkPad debe usar Debian y tener `apt-get` y `systemd`.

## Uso

El modo predeterminado es una auditoría sin cambios:

```sh
./scripts/install/migrate_laptop_linux.sh --check
```

Para ejecutar desde Just:

```sh
just migrate-laptop --source rafex@192.168.3.174 --check
```

Para revisar específicamente el hardware de la ThinkPad:

```sh
just migrate-laptop --stage hardware --check
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--source <usuario@host>` | — | Laptop fuente para auditoría no secreta |
| `--check` | — | Audita origen y destino sin modificar nada |
| `--plan` | — | Muestra paquetes y archivos previstos sin modificar nada |
| `--dry-run` | — | Alias compatible de `--plan` |
| `--apply` | — | Aplica la etapa seleccionada |
| `--stage <etapa>` | — | `audit`, `hardware`, `desktop`, `network`, `usb`, `cameras`, `laptop`, `display` o `all` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `MIGRATE_SOURCE` | `rafex@192.168.3.174` | Origen SSH usado por la auditoría |
| `MIGRATE_STAGE` | `audit` | Etapa si no se especifica `--stage` |

Los argumentos CLI tienen prioridad sobre las variables de entorno.

## Ejemplos

### Auditoría recomendada

```sh
just migrate-laptop --source rafex@192.168.3.174 --check
```

### Revisar el plan sin cambios

```sh
just migrate-laptop --source rafex@192.168.3.174 --plan --stage desktop
```

### Aplicar las etapas una por una

Primero prepara drivers, firmware de usuario y aceleración:

```sh
just migrate-laptop --apply --stage hardware
```

Después aplica el entorno y los periféricos:

```sh
just migrate-laptop --source rafex@192.168.3.174 --apply --stage desktop
just migrate-laptop --source rafex@192.168.3.174 --apply --stage network
just migrate-laptop --source rafex@192.168.3.174 --apply --stage usb
just migrate-laptop --source rafex@192.168.3.174 --apply --stage cameras
just migrate-laptop --source rafex@192.168.3.174 --apply --stage laptop
```

La etapa `hardware` instala y verifica:

- `i915` más Mesa, Vulkan y el Intel Media Driver para VA-API de Skylake.
- PipeWire, WirePlumber y ALSA.
- V4L2, cámaras físicas y dependencias DKMS para cámaras virtuales.
- Wacom, libinput, sensores, Bluetooth, WWAN y `fwupd`.
- Headers del kernel, `dkms`, `gcc` y herramientas de diagnóstico.
- Grupos `video` y `render` para acceso de usuario a `/dev/video*` y
  `/dev/dri/renderD128`.

El driver `intel-media-va-driver-non-free` requiere que APT tenga habilitado
el componente `non-free`. La etapa `hardware` delega esta operación al script
central `enable_debian_repositories_linux.sh`, que garantiza las cuatro
componentes (`main`, `contrib`, `non-free` y `non-free-firmware`) tanto en
fuentes `.list` como `.sources`. Si existe el archivo legado generado por
versiones anteriores (`90-laptop-nonfree.list`) y ya hay otra fuente Debian
completa, se respalda y se retira para evitar advertencias de duplicados.

Tras cerrar sesión y volver a entrar, valida la aceleración:

```sh
vainfo --display drm --device /dev/dri/renderD128
glxinfo -B
vulkaninfo --summary
ffmpeg -hwaccels
```

Valida el resto del hardware con:

```sh
aplay -l
wpctl status
v4l2-ctl --list-devices
nmcli device
mmcli -L
bluetoothctl list
fwupdmgr get-devices
fprintd-enroll
```

### Usando variables de entorno

```sh
MIGRATE_SOURCE=rafex@192.168.3.174 \
MIGRATE_STAGE=network \
  just migrate-laptop --apply
```

### Compatibilidad legacy

Para conservar permisos directos sobre nodos de bloques USB, que no son
necesarios para el montaje normal con udisks2:

```sh
sudo scripts/hardware/usb_mount_perms_linux.sh --fix --legacy-udev
```

## Protecciones de seguridad

- Solicita sudo con `sudo -v`; nunca recibe una contraseña como argumento.
- No copia archivos `.nmconnection`, claves SSH, perfiles de navegador ni
  otros secretos.
- Solo muestra nombres de conexiones NetworkManager, nunca sus secretos.
- Respaldos de reglas del sistema usan sufijo `.bak.YYYYMMDD_HHMMSS`.
- No modifica particiones, `fstab`, GRUB ni opciones de montaje del NVMe.
- No descarga automáticamente un módulo `v4l2loopback` que ya esté en uso.
- `--check` y `--plan` no escriben archivos ni ejecutan cambios del sistema.
- No activa automáticamente parámetros GuC/HuC ni otros parámetros del kernel.
- No aplica actualizaciones de BIOS o firmware mediante `fwupdmgr`.
- No añade PPAs ni software externo para el lector Validity VFS7500.

## Fallos conocidos

### `no se pudo conectar por SSH`

**Causa:** la laptop fuente está apagada, la IP cambió o no existe una clave
SSH autorizada.

**Solución:** verifica `ssh rafex@192.168.3.174` y vuelve a ejecutar la
auditoría.

### `no se detectó una salida interna`

**Causa:** la etapa de pantalla se ejecutó fuera de una sesión Xorg o no hay
un `DISPLAY` disponible.

**Solución:** inicia i3 desde LightDM y ejecuta `xrandr --query` dentro de la
sesión gráfica.

### `no se pudo cargar v4l2loopback`

**Causa:** faltan headers compatibles, DKMS no compiló el módulo o Secure Boot
impide cargarlo.

**Solución:** revisa `dkms status`, `uname -r`, `ls /usr/src/linux-headers*` y
`journalctl -k`; reinicia después de instalar headers.

### `sudo no está instalado`

**Causa:** la instalación inicial de Debian no tiene todavía el comando
`sudo`, por lo que el migrador no puede solicitar la contraseña de forma
segura.

**Solución:** entra a una consola root con `su -`, instala `sudo`, agrega
`rafex` al grupo `sudo` mediante
`just configure-sudo --user rafex --apply`, cierra sesión y vuelve a entrar.

### `vainfo` o `glxinfo` no pueden abrir el dispositivo

**Causa:** la sesión actual todavía no conoce el grupo `render`, o la prueba
se ejecutó fuera de una sesión gráfica.

**Solución:** cierra sesión después de aplicar la etapa `hardware`; ejecuta
`vainfo` desde una sesión con el usuario `rafex` y usa la ruta DRM indicada.

### `fprintd-enroll` no encuentra el lector Validity

**Causa:** el lector VFS7500 (`138a:0090`) no tiene soporte garantizado en el
driver estándar de Debian.

**Solución:** conserva el resultado como hardware detectado sin driver
estándar. El soporte experimental de `python-validity` requiere software
externo, firmware del lector y posiblemente inicialización desde Windows; no
se instala automáticamente.

## Changelog

### [Unreleased]

- **feat:** migración Debian por etapas con auditoría, dry-run y respaldos.
- **feat:** auditoría detallada y etapa hardware para GPU, VA-API, Vulkan,
  audio, input, WWAN y firmware.
- **feat:** configuración portable de i3 para ThinkPad X1 Yoga.
- **feat:** NetworkManager, udisks2, cámaras, VA-API, TLP y NVMe.
- **fix:** reutilizar el gestor central de repositorios y retirar fuentes
  `90-laptop-nonfree.list` redundantes después de respaldarlas.
- **fix:** usar `libwacom-common` y `libwacom-bin`, los paquetes disponibles en
  Debian Forky, en lugar del nombre de paquete fuente `libwacom`.
- **fix:** reemplazar `volumeicon-alsa`, ausente en Debian Forky, por
  `pasystray` para el icono de volumen y mantener `pavucontrol` como mezclador.
- **fix:** retirar opciones GLX obsoletas de Picom que generaban advertencias
  al iniciar la sesión gráfica.
- **fix:** instalar Font Awesome y reemplazar emojis de i3status por glifos
  compatibles con la barra i3.
- **fix:** hacer condicionales los autostarts de `udiskie` y `nm-applet` para
  que el perfil funcione aunque las etapas USB y network se apliquen después.
