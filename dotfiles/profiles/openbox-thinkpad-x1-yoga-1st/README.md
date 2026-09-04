# Perfil Openbox para ThinkPad X1 Yoga

Perfil paralelo y ligero para una sesión Xorg con Openbox y tint2. No reemplaza
el perfil `thinkpad-x1-yoga-1st` de i3: i3 continúa siendo la sesión estable y
predeterminada de LightDM.

## Características

El inicio de sesión selecciona el teclado español latinoamericano (`latam`),
coherente con el sistema y el perfil i3. El idioma `es_MX.UTF-8` es independiente
de la distribución del teclado.

- Openbox con comportamiento híbrido: ventanas flotantes y reglas automáticas
  por aplicación.
- tint2 en la parte superior con escritorios, tareas, bandeja, reloj y estado
  compacto del equipo.
- Diez escritorios: `term`, `code`, `web`, `docs`, `misc`, `media`, `comms`,
  `ops`, `monitor` y `scratch`.
- Atajos multimedia, brillo, Wi-Fi, micrófono, proyector, rotación y energía
  reutilizando los scripts comunes del repositorio.
- F5/F6 controlan el brillo de pantalla y los keysyms `XF86LaunchA`/
  `XF86Explorer` (las teclas físicas F11/F12 en este modelo) bajan/suben el
  brillo del teclado con notificación; Fn+Space conserva el control del
  firmware.
- Alacritty y rxvt-unicode siguen abriendo la sesión tmux `thinkpad`.
- CopyQ mantiene el historial del portapapeles y se abre con
  `Super+Shift+V`. El capturador X11 usa `Super+P` o `Print` para pantalla
  completa, `Shift+Print` para selección y `Ctrl+Print` para la ventana activa.
  Se instalan por separado con `just install-clipboard --apply` y
  `just install-screenshot --apply`.
- Picom no se inicia por defecto; se puede activar desde el centro de control.
- EWW es opcional: `just install-eww --apply` instala una columna derecha
  `rafex-widgets` con calendario, multimedia mediante `playerctl`, dispositivos
  y controles rápidos. Usa `windowtype desktop`, `stacking bg`, no reserva
  espacio y permanece detrás de las ventanas; se alterna con
  `Super+Control+W` o `just eww-widgets --toggle dashboard`.

## Instalación

Desde la raíz del repositorio:

```bash
just install-openbox-profile --dry-run
just install-openbox-profile
```

Después de cerrar sesión, selecciona **Openbox** en LightDM. La sesión i3 no
se modifica y puede elegirse nuevamente como recuperación.

## Atajos principales

| Atajo | Acción |
|---|---|
| `Super+Return` | Alacritty/tmux |
| `Super+Space` | Menú Rofi |
| `Super+1` … `Super+0` | Escritorios 1–10 |
| `Super+Tab` | Ventanas Rofi |
| `Super+F9` | Menú ratmenu (9menu como respaldo) |
| `XF86Tools` | Menú ratmenu |
| `XF86WakeUp` | Menú de energía |
| `XF86KbdBrightnessDown` / `Up` | Bajar/subir brillo del teclado |
| `XF86LaunchA` / `XF86Explorer` | Bajar/subir brillo del teclado |
| `XF86Display` | Siguiente modo del proyector |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Volumen |
| `XF86AudioMute` / `XF86AudioMicMute` | Silenciar audio/micrófono |
| `XF86WLAN` / `XF86RFKill` | Wi-Fi/modo avión |
| `Super+Shift+T` | Cambiar tema |
| `Super+Shift+P` | Activar o desactivar picom |
| `Super+Control+P` | Panel de control Rafex |

El menú raíz de Openbox abre ratmenu; 9menu ofrece el fallback y ambos ofrecen capturas de pantalla, CopyQ, cerrar
sesión, suspender, hibernar, reiniciar y apagar. Las acciones sensibles siempre
piden confirmación mediante Rofi; la hibernación solo se intenta si
`loginctl can-hibernate` la anuncia como disponible. El brillo usa
`brightnessctl` con el grupo `input` y conserva un respaldo Polkit restringido
al LED del teclado; esa pertenencia también permite leer eventos de entrada y
requiere cerrar y abrir sesión después de `just install-kbd-brightness --apply`.

## Temas

El tema inicial es `nord`. Se puede cambiar desde Rofi o con:

```bash
theme-toggle.sh --set nord
theme-toggle.sh --cycle
```

El selector actualiza Openbox, tint2, Dunst, Rofi, Alacritty, rxvt-unicode,
i3status, tmux y el estilo EWW cuando las configuraciones correspondientes
existen.

Las fuentes base y la fuente de iconos para EWW se instalan por separado:

```bash
just install-fonts --apply --profile web-programming
just install-fonts --apply --profile nerd
```

Los emojis Unicode usan `Noto Color Emoji`; `JetBrains Mono Nerd Font` aporta
los glifos de iconos y se instala únicamente en la cuenta del usuario.

El panel GTK3 opcional se instala con `just install-rafex-control-panel --apply`.
EWW es opcional y no activa servicios privilegiados. `i3lock-color` también es
opcional; al ejecutar su instalador se activa el wrapper en modo imagen para el
atajo y `xss-lock`, ajustando el fondo a toda la pantalla con una copia
temporal tipo *cover*. El `i3lock` de Debian queda disponible como respaldo.

## Herramientas Android opcionales

Para administrar teléfonos del laboratorio instala ADB, fastboot, las reglas
udev de Debian y scrcpy:

```bash
just install-android-tools --apply
just android-tools --devices
just android-tools --install-apk --path ~/Android/lab-apks/app.apk
just android-tools --scrcpy
```

Activa la depuración USB y acepta la huella RSA en cada teléfono. Las acciones
se ejecutan como usuario normal, requieren un único dispositivo autorizado y
no activan ADB por red ni permiten shell remoto o flasheo automático.

## Fallos conocidos

- Las reglas por aplicación dependen de `WM_CLASS`; si una aplicación cambia
  su clase, compruébala con `xprop WM_CLASS` y añade una regla específica.
- Algunas aplicaciones no respetan Xresources ni la paleta del WM.
- La bandeja depende de que NetworkManager, pasystray y udiskie estén iniciados
  sin duplicados.
- El compositor es opcional y puede consumir más batería o exponer problemas
  gráficos; se mantiene apagado al iniciar.
