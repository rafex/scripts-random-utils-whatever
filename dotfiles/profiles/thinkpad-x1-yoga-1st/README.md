# Perfil: thinkpad-x1-yoga-1st

Configuración portable de i3 para ThinkPad X1 Yoga de primera generación.
Conserva el flujo de trabajo de la MacBook, pero no instala configuraciones
específicas de Xorg, DPI ni autorandr.

## Instalación

```sh
./dotfiles/install.sh --profile thinkpad-x1-yoga-1st
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

- i3, i3status, rofi, dunst, alacritty y picom.
- Inicio de `udiskie` y `nm-applet` desde i3.
- Atajos de brillo, audio, capturas, bloqueo y pantallas.
- Configuración de udiskie que ignora el NVMe interno.
- `.Xresources` sin un DPI fijo.
- La autorrotación y las pruebas Wacom se activan con la etapa `tablet` de la
  migración; no se inician desde `.bashrc`.

## No incluye

- `20-intel.conf` de la MacBook.
- Configuración de trackpad exclusiva de MacBook.
- Perfil autorandr de la Mac.
- Contraseñas, perfiles `.nmconnection` o archivos privados.
- Rotación automática hasta validar sensores y orientación en la ThinkPad.
