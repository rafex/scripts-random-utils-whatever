# Perfil: macbook-pro-late2012

Configuración completa de i3 + Xorg para **MacBook Pro (Retina, 13-inch, Late 2012)** corriendo Debian 13 (trixie).

## Hardware

| Componente | Detalle |
|---|---|
| Modelo | MacBookPro10,2 (Retina, 13-inch, Late 2012) |
| CPU | Intel Core i5-3210M @ 2.50GHz (Ivy Bridge) |
| RAM | 8 GB DDR3 1600 MHz |
| Gráficos | Intel HD Graphics 4000 |
| Pantalla | 13.3" 1280×800, DPI 76 |
| SSD | Crucial CT480M500SSD1 480 GB |
| Red | Wi-Fi Broadcom BCM4331 (brcmfmac), Ethernet USB |

## Software

| Componente | Detalle |
|---|---|
| OS | Debian GNU/Linux 13 (trixie) |
| WM | i3 (Xorg, no Wayland) |
| DM | LightDM + `~/.xsession` |
| Compositor | picom (backend GLX) |
| Terminal | alacritty |
| Notificaciones | dunst |
| Launcher | rofi |
| Audio | PipeWire (PulseAudio compat) |
| Montaje USB | udisks2 + udiskie + polkit (sin sudo) |
| Shell | bash |

## Instalación

```sh
cd dotfiles/
./install.sh --profile macbook-pro-late2012
```

## Post-instalación

Una vez instalados los dotfiles, son necesarios estos pasos adicionales:

### 1. Copiar wallpaper

El wallpaper referenciado en el i3 config no está incluido en el perfil. Cópialo manualmente:

```sh
mkdir -p ~/Imágenes/FondosDePantalla
# Copia el wallpaper a:
# ~/Imágenes/FondosDePantalla/wp15986180-debian-13-wallpapers.jpg
```

Si usas otro wallpaper, edita la línea `exec_always --no-startup-id feh --bg-scale ...` en `~/.config/i3/config`.

### 2. Instalar scripts de hardware

Los scripts referenciados en los bindsyms de i3 están en el repo principal:

```sh
# Notificaciones de hardware
cp scripts/hardware/notify_brightness_linux.sh ~/.local/bin/brightness-notify.sh
cp scripts/hardware/notify_volume_linux.sh ~/.local/bin/volume-notify.sh
cp scripts/hardware/notify_kbd_brightness_linux.sh ~/.local/bin/kbd-brightness-notify.sh
cp scripts/hardware/notify_power_linux.sh ~/.local/bin/power-notify.sh
cp scripts/hardware/screensaver_toggle_linux.sh ~/.local/bin/screensaver-toggle

# HiDPI (ajuste de DPI y escala)
cp scripts/display/hidpi_xorg_linux.sh ~/.local/bin/hidpi_xorg.sh

# Montaje USB sin sudo
cp scripts/hardware/usb_mount_perms_linux.sh ~/.local/bin/usb-mount-perms

# Pantalla externa — para ponencias/proyector
cp scripts/display/screen_mirror_linux.sh ~/.local/bin/screen-mirror.sh
cp scripts/display/screen_auto_mirror_linux.sh ~/.local/bin/screen-auto-mirror.sh
cp scripts/display/screen_auto_edge_mirror_linux.sh ~/.local/bin/screen-auto-edge-mirror.sh
cp scripts/display/screen_extend_auto_linux.sh ~/.local/bin/screen-extend-auto.sh

chmod +x ~/.local/bin/*.sh ~/.local/bin/screensaver-toggle ~/.local/bin/usb-mount-perms
```

### 3. Configurar permisos de montaje USB

```sh
sudo ~/.local/bin/usb-mount-perms --fix
```

Esto crea la regla polkit necesaria para montar/desmontar USB sin sudo y activa udiskie para auto-montaje.

### 4. Configurar polkit agent (si no arranca automáticamente)

El perfil usa `dex` para lanzar el agente UKUI vía autostart de XDG. Si no funciona:

```sh
sudo apt install ukui-polkit
# Verifica que /etc/xdg/autostart/polkit-ukui-authentication-agent-1.desktop exista
```

### 5. Instalar configs de Xorg al sistema

Los configs de Xorg (trackpad, gráficos, Magic Mouse) se instalan en `~/.config/X11/xorg.conf.d/` (espacio de usuario) por defecto. Para que el trackpad y los gráficos Intel usen estos configs, deben copiarse a `/etc/X11/xorg.conf.d/`:

```sh
sudo cp ~/.config/X11/xorg.conf.d/20-intel.conf /etc/X11/xorg.conf.d/
sudo cp ~/.config/X11/xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/
```

El `40-magicmouse.conf` funciona desde `~/.config/X11/` (user-space). Si tienes conflictos con el de `/etc/`, elimina o renombra la versión del sistema:

```sh
sudo mv /etc/X11/xorg.conf.d/40-magicmouse.conf /etc/X11/xorg.conf.d/40-magicmouse.conf.bak
```

### 6. Trackpad estilo macOS

El archivo `40-libinput.conf` replica el comportamiento del trackpad del MacBook:

| Opción | Valor | Efecto |
|---|---|---|
| Tapping | on | Tap para hacer click |
| NaturalScrolling | true | Scroll invertido (natural) |
| ScrollMethod | twofinger | Scroll con dos dedos |
| AccelSpeed | 0.3 | Velocidad del cursor |
| PalmDetection | on | Ignorar palma al escribir |
| ClickMethod | clickfinger | Click izq/der por número de dedos (sin zonas físicas) |
| DisableWhileTyping | true | Pausa trackpad al teclear |

### 7. Perfiles de pantalla (autorandr)

El perfil incluye un preset de `autorandr` para configuración mirror (`LVDS1` + `HDMI1`):

```sh
autorandr --load mirror    # aplicar perfil guardado
autorandr --save mirror    # guardar estado actual como "mirror"
autorandr -c               # detectar y cargar perfil automático
```

Los scripts de pantalla en `~/.local/bin/` (`screen-mirror.sh`, `screen-extend-auto.sh`, etc.) usan `xrandr` directamente y son alternativas a autorandr.

### 8. Reiniciar sesión

```sh
i3-msg restart   # o Mod+Shift+R
```

## Contenido del perfil

| Componente | Archivo |
|---|---|
| i3 (WM) | `config/i3/config` |
| xsession | `config/xsession` |
| i3status (barra) | `config/i3status/config` |
| rofi (launcher) | `config/rofi/config.rasi` |
| dunst (notificaciones) | `config/dunst/dunstrc` |
| alacritty (terminal) | `config/alacritty/alacritty.toml` |
| picom (compositor) | `config/picom/picom.conf` |
| udiskie (auto-montaje USB) | `config/udiskie/config.yml` |
| Xresources (DPI/fuentes) | `config/Xresources` |
| Xorg — gráficos Intel | `config/X11/xorg.conf.d/20-intel.conf` |
| Xorg — trackpad macOS | `config/X11/xorg.conf.d/40-libinput.conf` |
| Xorg — Magic Mouse | `config/X11/xorg.conf.d/40-magicmouse.conf` |
| autorandr — perfil mirror | `config/autorandr/mirror/` |

## Dependencias externas

Ver `DEPS.toml` para el mapeo completo de scripts y paquetes.

## Atajos de teclado

| Atajo | Acción |
|---|---|
| `Mod+Return` | Terminal (alacritty) |
| `Mod+Space` | Launcher (rofi) |
| `Mod+Tab` | Cambiar ventana |
| `Mod+q` | Cerrar ventana |
| `Mod+f` | Fullscreen |
| `Mod+Shift+f` | Toggle flotante + centrar |
| `Mod+Shift+l` | Bloquear pantalla (i3lock) |
| `Mod+p` | Screenshot (maim) |
| `Mod+Shift+p` | Toggle picom |
| `Mod+Shift+s` | Toggle screensaver |
| `Mod+r` | Modo resize |
| `Mod+Shift+r` | Reiniciar i3 |
| `Mod+Shift+c` | Recargar config |
| `Mod+Shift+q` | Salir de i3 |
| `Mod+Shift+minus` | Scratchpad (ocultar) |
| `Mod+minus` | Scratchpad (mostrar) |
| Teclas brillo | Brillo pantalla + notificación |
| Teclas volumen | Volumen + notificación |

## Histórico

El archivo `history/i3_config_raw.txt` contiene la copia fiel del i3 config original de la laptop (incluye líneas comentadas del wizard de i3). Se conserva como referencia histórica.
