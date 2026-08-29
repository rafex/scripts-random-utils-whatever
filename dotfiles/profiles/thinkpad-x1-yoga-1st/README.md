# Perfil: thinkpad-x1-yoga-1st

Configuración portable de i3 para ThinkPad X1 Yoga de primera generación.
Conserva el flujo de trabajo de la MacBook, pero no instala configuraciones
específicas de Xorg, DPI ni autorandr.

## Instalación

```sh
just install-profile thinkpad-x1-yoga-1st
```

Después de iniciar sesión en Xorg:

```sh
xrandr --query
xinput list
autorandr --query
~/.local/bin/hidpi_xorg.sh --check
```

Los perfiles de autorandr y los ajustes DPI deben generarse con las salidas
reales de esta laptop. No se copia el perfil `LVDS1`/`HDMI1` de la Mac.

## Incluye

- i3, i3status, rofi, 9menu, dunst, alacritty y picom.
- Inicio de `udiskie` desde i3; `pasystray` y `nm-applet` se gestionan mediante
  los archivos XDG de autostart ejecutados por `dex`.
- Atajos de brillo, audio, capturas, bloqueo y pantallas.
- Menú 9menu en `Mod+F9` y `XF86Tools` con accesos a las herramientas de la
  ThinkPad.
- Diez escritorios con nombres y reglas para colocar automáticamente las
  aplicaciones habituales: terminal, código, web, documentos, configuración,
  multimedia, comunicaciones, operaciones, monitorización y scratch.
- Configuración de udiskie que ignora el NVMe interno.
- `.Xresources` sin un DPI fijo.
- La autorrotación y las pruebas Wacom se activan con la etapa `tablet` de la
  migración; no se inician desde `.bashrc`.
- La suspensión se probó con el modo `s2idle`; para hacerlo
  permanente en GRUB ejecuta `just configure-thinkpad-s2idle --apply` y
  reinicia cuando puedas.
- Incluye las paletas Paper, Nord, Everforest y Dracula para i3, tmux,
  Alacritty, rxvt-unicode, Rofi y Dunst. Nord es el tema inicial; se alternan
  con `Mod+Shift+T` o desde el centro de control. El color del texto de i3status
  se adapta a la paleta activa para conservar contraste en i3bar.
- Los gaps son nativos de i3: 2 píxeles internos, 3 externos y `smart_gaps`.
  Se verifican con `just install-i3-gaps --check` y se aplican con
  `just install-i3-gaps --apply`.
- Incluye `.tmux.conf` basado en el perfil `developer` de
  `development-environment-rafex`, con navegación tipo Vim, OSC52 y TPM.

## No incluye

- `20-intel.conf` de la MacBook.
- Configuración de trackpad exclusiva de MacBook.
- Perfil autorandr de la Mac.
- Contraseñas, perfiles `.nmconnection` o archivos privados.
- Rotación automática hasta validar sensores y orientación en la ThinkPad.

## Escritorios i3

| Escritorio | Uso | Aplicaciones asignadas |
|---|---|---|
| `1:term` | Terminal | Alacritty, rxvt-unicode, Kitty, XTerm |
| `2:code` | Desarrollo | Codium, VSCodium, Eclipse |
| `3:web` | Web | Firefox, Chromium, Chrome |
| `4:docs` | Documentos | Zathura, Evince, LibreOffice, Xournal++ |
| `5:misc` | Configuración | Thunar, Pavucontrol, NetworkManager, Bluetooth, Arandr |
| `6:media` | Multimedia | OBS, Guvcview, Krita, mpv |
| `7:comms` | Comunicaciones | Reserva para aplicaciones de comunicación |
| `8:ops` | Operaciones | Virt-manager, VirtualBox |
| `9:monitor` | Monitorización | Reserva para herramientas de monitorización |
| `10:scratch` | Temporal | Reserva para ventanas temporales |

Las clases no reconocidas permanecen en el escritorio actual. Para incorporar
una aplicación nueva, ejecuta `xprop WM_CLASS`, pulsa sobre su ventana y añade
su clase al bloque de asignaciones de `config/i3`.

## Tema, terminales y tmux

El instalador de perfiles crea `~/.config/rafex/themes/current` apuntando a
`nord` la primera vez. Para materializar las plantillas y cambiar el tema sin
`sudo`:

```sh
just generate-terminal-themes --apply --theme all
~/.local/bin/theme-toggle.sh --list
~/.local/bin/theme-toggle.sh --set nord
~/.local/bin/theme-toggle.sh --set paper
~/.local/bin/theme-toggle.sh --set everforest
~/.local/bin/theme-toggle.sh --set dracula
~/.local/bin/theme-toggle.sh --cycle
~/.local/bin/theme-toggle.sh --toggle
```

`Mod+Shift+T`, la entrada `Tema claro/oscuro` de 9menu y las opciones de tema
del centro Rofi ejecutan el mismo selector. `light` sigue siendo alias de Nord
y `dark` de Dracula. Alacritty conserva el tamaño `7` y rxvt usa tamaño `10`
para mantener una lectura cómoda en la pantalla de la ThinkPad.

Alacritty continúa siendo la terminal principal. La entrada `Terminal RXVT y
tmux` de 9menu abre `urxvt` en la sesión `thinkpad`; en ambos casos no se crea
una sesión tmux anidada.

El archivo `~/.tmux.conf` contiene los plugins del perfil developer. TPM se
instala en `~/.tmux/plugins/tpm`; dentro de tmux usa `Ctrl-b I` para instalar o
actualizar plugins. Una sesión existente puede recargar la configuración con:

```sh
tmux source-file ~/.tmux.conf
```
