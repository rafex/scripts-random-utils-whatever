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
- Atajos de brillo, audio, capturas, bloqueo y pantallas. F5/F6 controlan el
  brillo de pantalla; `XF86KbdBrightnessDown`/`Up` y
  `XF86LaunchA`/`Explorer` bajan/suben el brillo del teclado con notificación.
  Fn+Space conserva el control nativo del firmware.
- CopyQ mantiene un historial visual del portapapeles y se abre con
  `Mod+Shift+V`; la captura X11 se realiza con `Mod+P` o `Print` (pantalla
  completa), `Shift+Print` (selección) y `Ctrl+Print` (ventana activa).
  Instálalos con `just install-clipboard --apply` y
  `just install-screenshot --apply`. El historial puede contener información
  sensible: no copies contraseñas y revísalo o límpialo desde CopyQ.
- Menú 9menu en `Mod+F9` y `XF86Tools` con accesos a las herramientas de la
  ThinkPad, incluido Synaptic mediante `synaptic-pkexec`. Incluye capturas de
  pantalla, historial CopyQ, una salida visible y acciones de cerrar sesión,
  suspender, hibernar, reiniciar y apagar; todas las acciones sensibles piden
  confirmación en Rofi.
- El brillo de teclado usa `brightnessctl` con el grupo `input` y conserva un
  respaldo Polkit restringido al LED `tpacpi::kbd_backlight`. El grupo `input`
  también permite leer eventos de `/dev/input/event*`; cierra y abre sesión
  después de ejecutar `just install-kbd-brightness --apply`.
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
se añade al grupo `wireshark` y Wireshark se abre como usuario normal. Para
virtualización, `just install-security-lab --apply --stage virtualization`
instala las dependencias y `just configure-kvm --apply` prepara
`qemu:///session`, pools privadas en el usuario y red user-mode sin bridges ni
puertos nuevos. Consulta [configure_kvm_linux](../../../docs/install/configure_kvm_linux.md)
si el repositorio se está usando desde su copia de trabajo.

## Auditoría final de preparación

Antes de salir a una red pública o impartir un curso, ejecuta:

```sh
sudo -v
just audit-thinkpad --status
```

El auditor verifica USBGuard, UFW, Fail2ban, AppArmor, auditd, SSH efectivo,
OXXO Cel, dumpcap, cifrado, TRIM, TLP, KVM, runtimes y la disponibilidad de
los laboratorios sin mostrar secretos. Un proyector debe probarse físicamente:

```sh
just screen-projector --check
```

El SSD externo debe montarse manualmente antes de generar el respaldo final.
Secure Boot continúa siendo una decisión pendiente; LUKS protege los datos
apagados, pero no sustituye la protección de la cadena de arranque.

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

Thunar se asigna al escritorio `5:misc` y ahora conserva el comportamiento
normal de i3: se abre como ventana en mosaico, sin tamaño ni posición flotante
forzados. En el perfil Openbox solo se conserva la asignación al escritorio;
Openbox es un gestor flotante por diseño y no ofrece mosaico nativo.

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

## Panel Conky opcional

El panel Conky complementa i3bar o tint2 sin reemplazarlos. Se instala desde
Debian y se inicia automáticamente en i3 y Openbox:

```sh
just install-conky --check
just install-conky --plan
just install-conky --apply
just install-conky --status
just conky-status
```

Se muestra en el lateral izquierdo, debajo de la barra y con el alto útil de la
pantalla, con un fondo translúcido de alta opacidad y fuente `DejaVu Sans Mono`
tamaño 11 para conservar el contraste sobre los fondos del perfil. En i3 es un
dock X11 que reserva ese espacio y no cubre las ventanas de trabajo. En
Openbox las ventanas son flotantes por diseño.
Incluye kernel,
uptime, CPU, RAM, disco, temperaturas válidas, batería, red sin SSID/IP,
audio, KVM, Podman, runtimes y un resumen no certificador de seguridad. Las
lecturas que no estén disponibles aparecen como `N/D`. No muestra credenciales,
IMEI, IMSI, APN, nombres de archivos ni puertos.

El cambio de tema también actualiza los colores del panel:

```sh
~/.local/bin/theme-toggle.sh --set nord
~/.local/bin/theme-toggle.sh --set dracula
```

Conky se controla mediante `~/.local/bin/conky-launch.sh`; `--reload` solo
reinicia la instancia administrada por Rafex. Si el comando se ejecuta por SSH
sin `DISPLAY`, no inicia ninguna ventana.

El perfil declara compatibilidad RGB/TrueColor para Alacritty
(`xterm-256color`), Kitty (`xterm-kitty`) y rxvt-unicode. Si una sesión remota
desde Kitty conserva colores amarillos o con poco contraste, desconecta y vuelve
a conectar el cliente después de instalar el perfil.

## Estación creativa, oficina y multimedia

Estas capas son opcionales y no forman parte de la instalación ligera del
perfil. Se instalan por separado desde Debian:

```sh
just install-graphics --apply
just install-office --apply --locale es_MX
just install-multimedia --apply
just install-fonts --apply --profile web-programming
```

Para chino, japonés y coreano puede añadirse la etapa más grande de fuentes:

```sh
just install-fonts --apply --profile cjk
```

El locale de oficina se carga en la sesión del usuario desde
`~/.config/rafex/locale.conf`; no reemplaza `/etc/default/locale`. Después de
instalarlo hay que abrir una nueva sesión. El locale de usuario es
`es_MX.UTF-8` (no `es_MX_UTF8`) y `LC_ALL` debe quedar sin definir. Los scripts fuerzan `LC_ALL=C`
solo al interpretar salidas APT, para que el idioma del escritorio no rompa sus
diagnósticos.

## Antivirus y USB

ClamAV es opcional. El flujo recomendado es instalarlo y escanear manualmente
cada memoria antes de compartirla:

```sh
just install-antivirus --apply
just scan-usb --path /run/media/$USER/NOMBRE_USB
```

El escáner solo acepta dispositivos extraíbles montados bajo
`/run/media/$USER` o `/media/$USER`, no borra ni pone archivos en cuarentena y
no puede apuntar al NVMe interno. Si se desea escaneo al montar, debe
habilitarse explícitamente con `just install-antivirus --apply --auto-usb`;
esta opción usa el event-hook de udiskie, notifica el resultado y permanece
sin borrado automático. `clamonacc` no se habilita.

La auditoría `just audit-thinkpad --status` informa de estas capas sin tratarlas
como bloqueos de preparación: su ausencia no impide desarrollar, impartir
cursos o realizar auditorías de red.

## mDNS en la red local

Avahi y `libnss-mdns` permiten resolver la ThinkPad como `thinkpad.local` y
descubrir equipos locales. La configuración recomendada limita mDNS a Wi-Fi y
Ethernet, dejando la conexión WWAN fuera; tampoco publica automáticamente
servicios de archivos, SSH, impresoras o escritorios remotos.

```sh
just install-mdns --check
just install-mdns --plan
just install-mdns --apply
just install-mdns --status
```

En una Wi-Fi pública el nombre del equipo y su dirección local pueden ser
visibles para otros dispositivos del mismo segmento. Si no necesitas
descubrimiento local, puedes detener Avahi; mDNS no es necesario para navegar
ni para usar OXXO Cel.

## Impresoras y escáner

La estación puede configurar por USB o por red la multifuncional Epson XP-241 y
la impresora láser Xerox Phaser 3020. La Epson usa ESC/P-R para imprimir y SANE
para escanear; la Xerox se configura como impresora únicamente. La cola Xerox
queda como predeterminada cuando está disponible.

```sh
just install-printers --apply
just configure-printers --status
just configure-printers --apply
just printer-test --printer xerox
just printer-test --printer epson
just scan-document --list
just scan-document --output ~/Documents/escaneo.png
```

La configuración no comparte CUPS, no habilita `saned`, no abre puertos nuevos
en UFW y no almacena contraseñas. Si hay varias URI para una impresora, el
configurador exige seleccionar una explícitamente con `--device-uri`; si una
cola existente entra en conflicto, `--replace` es necesario y puede eliminar
trabajos pendientes. La primera creación de colas puede solicitar sudo, pero
imprimir y escanear se realiza como usuario normal.

## Respaldo incremental cifrado

El respaldo portable anterior sigue disponible para exportaciones puntuales,
pero no sustituye un historial. Para respaldos incrementales usa Restic con dos
repositorios separados en el SSD externo `ssd_rafex_1`:

```sh
just install-restic-backup --apply
just backup-thinkpad-restic --init --profile recovery
just backup-thinkpad-restic --init --profile personal
just backup-thinkpad-restic --backup
just backup-thinkpad-restic --verify
```

`recovery` conserva configuraciones y scripts; `personal` conserva
`Documents`, `Projects`, `Pictures`, `Videos` y `Music`. Las claves se guardan
solo en GNOME Keyring mediante Secret Service. No se incluyen claves SSH/GPG,
credenciales, cookies, keyrings, caches ni los binarios de `mise`.

El SSD debe montarse manualmente y conservar la etiqueta exacta
`ssd_rafex_1`; el runner no formatea ni monta discos. La poda es manual y el
timer opcional solo crea snapshots:

```sh
just backup-thinkpad-restic --prune --plan
just backup-thinkpad-restic --prune --apply
just backup-thinkpad-restic --install-timer
```

Un único SSD no protege frente a robo, incendio o fallo del dispositivo. Para
una estrategia 3-2-1 se necesita una segunda réplica en otro destino.

## CLIs de desarrollo y secretos

Los asistentes de desarrollo se instalan como usuario normal en un prefijo npm
privado. La instalación no inicia sesión ni guarda credenciales:

```sh
just install-ai-cli --check
just install-ai-cli --plan
just install-ai-cli --apply
codex --login
claude
```

Para cifrado de archivos se usa `age`. gopass se instala desde su repositorio
oficial y puede inicializarse con su backend age, que actualmente es
experimental:

```sh
just install-age-gopass --apply
just init-gopass-age
just age-file --encrypt --input ~/.config/app/config.yml \
  --output ~/.config/app/config.yml.age \
  --ssh-recipient ~/.ssh/id_ed25519.pub
```

`--apply` no crea el almacén ni las identidades. La frase de protección del
almacén se introduce únicamente en la terminal interactiva y nunca debe
guardarse en este repositorio, logs o respaldos sin cifrar. No se debe confundir
el `gopass` oficial con el paquete Debian homónimo de otra implementación.

## Escritorio remoto opcional

RustDesk 1.4.9 puede instalarse desde el DEB oficial de GitHub. El instalador
verifica el SHA-256 antes de entregarlo a APT y no habilita el acceso
desatendido automáticamente:

```sh
just install-rustdesk --check
just install-rustdesk --plan
just install-rustdesk --apply
just install-rustdesk --status
```

Abre RustDesk como usuario normal con `rustdesk`. Configura el acceso remoto
solo con autorización explícita, revisa cualquier contraseña o permiso desde
la aplicación y evita habilitarlo automáticamente en redes públicas.
