# Perfil: default

Perfil base de configuración de i3 + Xorg. Limpio, portable y sin personalizaciones específicas de hardware.

## Instalación

```sh
cd dotfiles/
./install.sh --profile default
```

## Contenido

| Componente | Archivo |
|---|---|
| i3 (WM) | `config/i3/config` |
| i3status (barra) | `config/i3status/config` |
| rofi (launcher) | `config/rofi/config.rasi` |
| dunst (notificaciones) | `config/dunst/dunstrc` |
| alacritty (terminal) | `config/alacritty/alacritty.toml` |
| picom (compositor) | `config/picom/picom.conf` |
| Xresources (DPI/fuentes) | `config/Xresources` |

## Dependencias

Ver `deps.txt` y `DEPS.toml` para la lista de paquetes apt requeridos.
