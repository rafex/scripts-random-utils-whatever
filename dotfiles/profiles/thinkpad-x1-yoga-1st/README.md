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

- i3, i3status, rofi, 9menu, dunst, alacritty y picom. Dunst detecta la
  posición de i3bar y reserva espacio para que las notificaciones no se
  empalmen con la barra.
- Inicio de `udiskie` desde i3; `pasystray` y `nm-applet` se gestionan mediante
  los archivos XDG de autostart ejecutados por `dex`.
- Atajos de brillo, audio, capturas, bloqueo y pantallas.
- Menú 9menu en `Mod+F9` y `XF86Tools` con accesos a las herramientas de la
  ThinkPad, incluido Synaptic mediante `synaptic-pkexec`.
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

## Laboratorio de seguridad opcional

Las herramientas de auditoría no forman parte de `install-profile`, para
mantener el escritorio y la instalación base ligeros. Se instalan por etapas
desde Debian:

```sh
just install-security-lab --check
just install-security-lab --plan --stage base
just install-security-lab --apply --stage base
just install-security-lab --status
```

Las etapas `wireless`, `web`, `forensics`, `credentials` y `virtualization`
son explícitas; `all` instala todas. Las herramientas no ejecutan acciones
automáticamente. El Wi-Fi interno sigue bajo NetworkManager y para prácticas
de modo monitor se recomienda un adaptador USB externo compatible.

Las capturas en vivo requieren `sudo dumpcap` o `sudo tshark`; el usuario no
se añade al grupo `wireshark` y Wireshark se abre como usuario normal. Las
máquinas virtuales usan preferentemente `qemu:///session`: el instalador solo
añade el grupo `kvm`, sin crear bridges ni abrir puertos.

## Fondos de marca

El perfil incluye cinco fondos raster en
`assets/backgrounds/`, instalados por `dotfiles/install.sh` en:

```text
~/.local/share/rafex/profiles/thinkpad-x1-yoga-1st/assets/backgrounds/
```

| Archivo | Uso previsto |
|---|---|
| `rafex-thinkpad-boot.png` | GRUB o pantalla de arranque; oscuro y con espacio para texto a la izquierda |
| `rafex-thinkpad-login.png` | LightDM; centro despejado para el diálogo de inicio |
| `rafex-thinkpad-desktop.png` | Fondo diario de i3; baja interferencia con i3bar y terminales |
| `rafex-thinkpad-tablet.png` | Pantalla vertical al rotar la Yoga |
| `rafex-thinkpad-projector.png` | Proyección y pantalla de recuperación; contraste sobrio |

La instalación del perfil no modifica automáticamente GRUB ni LightDM, porque
ambos son configuraciones del sistema y requieren una decisión explícita. El
SVG original de Rafex permanece fuera del perfil como fuente de identidad; las
imágenes raster son fondos derivados y no sustituyen la marca vectorial.

Para aplicarlos explícitamente después de instalar el perfil:

```sh
just install-thinkpad-backgrounds --plan --stage all
just install-thinkpad-backgrounds --apply --stage desktop
just install-thinkpad-backgrounds --apply --stage grub
just install-thinkpad-backgrounds --apply --stage login
```

`desktop` no requiere sudo. Las etapas `grub` y `login` solicitan sudo,
respaldan los archivos del sistema y no reinician LightDM automáticamente.

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

El perfil declara compatibilidad RGB/TrueColor para Alacritty
(`xterm-256color`), Kitty (`xterm-kitty`) y rxvt-unicode. Si una sesión remota
desde Kitty conserva colores amarillos o con poco contraste, desconecta y vuelve
a conectar el cliente después de instalar el perfil.
