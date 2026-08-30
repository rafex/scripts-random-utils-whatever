# Perfil Openbox para ThinkPad X1 Yoga

Perfil paralelo y ligero para una sesión Xorg con Openbox y tint2. No reemplaza
el perfil `thinkpad-x1-yoga-1st` de i3: i3 continúa siendo la sesión estable y
predeterminada de LightDM.

## Características

- Openbox con comportamiento híbrido: ventanas flotantes y reglas automáticas
  por aplicación.
- tint2 en la parte superior con escritorios, tareas, bandeja, reloj y estado
  compacto del equipo.
- Diez escritorios: `term`, `code`, `web`, `docs`, `misc`, `media`, `comms`,
  `ops`, `monitor` y `scratch`.
- Atajos multimedia, brillo, Wi-Fi, micrófono, proyector, rotación y energía
  reutilizando los scripts comunes del repositorio.
- Alacritty y rxvt-unicode siguen abriendo la sesión tmux `thinkpad`.
- Picom no se inicia por defecto; se puede activar desde el centro de control.

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
| `Super+F9` | Centro de control |
| `XF86Tools` | Centro de control |
| `XF86WakeUp` | Menú de energía |
| `XF86Display` | Siguiente modo del proyector |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Volumen |
| `XF86AudioMute` / `XF86AudioMicMute` | Silenciar audio/micrófono |
| `XF86WLAN` / `XF86RFKill` | Wi-Fi/modo avión |
| `Super+Shift+T` | Cambiar tema |
| `Super+Shift+P` | Activar o desactivar picom |

## Temas

El tema inicial es `nord`. Se puede cambiar desde Rofi o con:

```bash
theme-toggle.sh --set nord
theme-toggle.sh --cycle
```

El selector actualiza Openbox, tint2, Dunst, Rofi, Alacritty, rxvt-unicode,
i3status y tmux cuando las configuraciones correspondientes existen.

## Fallos conocidos

- Las reglas por aplicación dependen de `WM_CLASS`; si una aplicación cambia
  su clase, compruébala con `xprop WM_CLASS` y añade una regla específica.
- Algunas aplicaciones no respetan Xresources ni la paleta del WM.
- La bandeja depende de que NetworkManager, pasystray y udiskie estén iniciados
  sin duplicados.
- El compositor es opcional y puede consumir más batería o exponer problemas
  gráficos; se mantiene apagado al iniciar.
