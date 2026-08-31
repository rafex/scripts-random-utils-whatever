---
title: install_dotfiles_unix.sh
description: Instalación de dotfiles en macOS y Linux
tags:
  - instalación
---

# install_dotfiles_unix.sh

Empaqueta los dotfiles de i3wm en un `tar.gz` distribuible con un instalador autocontenido. El paquete se transfiere a cualquier máquina Debian/Linux y al extraerlo contiene su propio `install.sh` que detecta shell, verifica sudo, instala paquetes, copia configs, scripts y añade variables de entorno.

- **Ruta:** `scripts/install/install_dotfiles_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `tar`

______________________________________________________________________

## Uso

```sh
./scripts/install/install_dotfiles_unix.sh [opciones]
```

## Opciones

| Opción | Descripción |
|---|---|
| `--dist-dir <dir>` | Directorio de salida (default: `dist/`) |
| `--profile <name>` | Perfil a empaquetar (default: `default`) |
| `--dry-run` | Muestra los pasos sin empaquetar |
| `-h, --help` | Muestra la ayuda |

______________________________________________________________________

## Qué incluye el paquete

```
i3-dotfiles-bundle.tar.gz
├── install.sh                    ← Instalador autocontenido
└── profiles/<perfil>/
    ├── README.md
    ├── DEPS.toml
    ├── deps.txt
    ├── config/                   ← Configuración del perfil
    └── scripts/                  ← Helpers para ~/.local/bin/
```

## Comportamiento de install.sh (dentro del tar.gz)

1. **Detecta shell** (bash/zsh/fish) → determina el archivo RC correcto
1. **Verifica sudo**:
   - Con sudo → instala paquetes vía `apt-get`
   - Sin sudo → advierte y salta instalación de paquetes (todo en `~/.config/`)
1. **Backup** de configs existentes → `~/.config/<app>.bak.<timestamp>`
1. **Copia configs** a `~/.config/i3/`, `~/.config/i3status/`, etc.
1. **Fusiona paletas** en `~/.config/rafex/themes/` y conserva el tema activo.
1. **Copia `.tmux.conf`** del perfil a `~/.tmux.conf`, con respaldo fechado.
1. **Copia Xresources** a `~/.Xresources`
1. **Copia scripts** a `~/.local/bin/` (con nombres que i3 config espera)
1. **Crea directorios** de imágenes: `~/Imágenes/FondosDePantalla/`, `~/Imágenes/CapturasDePantalla/`
1. **Instala assets del perfil**, cuando el perfil los declare. Los assets son
   opcionales; por ejemplo, Openbox reutiliza el perfil visual pero no duplica
   los fondos de ThinkPad. Los fondos se instalan con
   `just install-thinkpad-backgrounds`.
1. **Inyecta env vars** en el RC file (idempotente):
   ```sh
   export XDG_CURRENT_DESKTOP=i3
   export XDG_SESSION_DESKTOP=i3
   export DESKTOP_SESSION=i3
   export PATH="$HOME/.local/bin:$PATH"
   ```

## Ejemplos

```sh
# Empaquetar el perfil default
./scripts/install/install_dotfiles_unix.sh

# Empaquetar el perfil ThinkPad
./scripts/install/install_dotfiles_unix.sh --profile thinkpad-x1-yoga-1st

# Empaquetar con directorio de salida personalizado
./scripts/install/install_dotfiles_unix.sh --dist-dir ./output

# Simular sin empaquetar
./scripts/install/install_dotfiles_unix.sh --dry-run

# Transferir a otra máquina
scp dist/i3-dotfiles-bundle.tar.gz user@machine:~/
ssh user@machine
tar xzf i3-dotfiles-bundle.tar.gz
cd i3-dotfiles-bundle && ./install.sh --profile thinkpad-x1-yoga-1st
```

### Usando Justfile

```sh
# Empaquetar un perfil para distribuirlo
just install-dotfiles
just install-dotfiles --dry-run

# Aplicar directamente un perfil en el equipo actual
just install-profile thinkpad-x1-yoga-1st --dry-run
just install-profile thinkpad-x1-yoga-1st
```

`install-dotfiles` genera el bundle distribuible. `install-profile` ejecuta el
instalador de `dotfiles/` directamente y acepta el nombre del perfil como
primer parámetro; los argumentos restantes se pasan al instalador, por ejemplo
`--dry-run`.

______________________________________________________________________

## Archivos del repositorio asociados

| Archivo | Propósito |
|---|---|
| `dotfiles/profiles/<perfil>/config/i3/config` | Configuración de i3wm (sanitizada, sin secretos) |
| `dotfiles/profiles/thinkpad-x1-yoga-1st/config/tmux.conf` | Perfil tmux developer para el usuario |
| `dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes/` | Paletas light/dark de la sesión |
| `dotfiles/install.sh` | Instalador autocontenido dentro del tar.gz |
| `dotfiles/profiles/<perfil>/deps.txt` | Lista de paquetes apt |

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Variables de entorno

No se requieren variables adicionales fuera de las indicadas en esta documentación.

## Fallos conocidos

### `error: ... failed ...` después de crear los directorios de imágenes

**Causa:** una versión anterior del instalador devolvía el código de una
comprobación negativa cuando el perfil no tenía `assets/`. Esto afectaba al
perfil Openbox, que comparte temas con ThinkPad pero no contiene una copia de
los fondos.

**Solución:** actualiza el repositorio y repite la instalación. Los
componentes opcionales ahora terminan con éxito cuando no están declarados;
los assets existentes siguen copiándose con respaldo e idempotencia.

Si se necesitan los fondos de ThinkPad, ejecuta después:

```bash
just install-thinkpad-backgrounds --apply --stage desktop
```

## Changelog

### [Unreleased]

**feat:** instalar `.tmux.conf` y paletas ThinkPad preservando el tema activo.

### v1.0.0 — 2026-07-31

**feat:** Empaquetador de dotfiles i3wm con instalador autocontenido.

- Empaquetador: genera tar.gz con configs, scripts auxiliares, deps.txt e install.sh
- Instalador autocontenido: detecta shell, verifica sudo, instala paquetes, copia configs
- Mapeo de scripts del repo a nombres que i3 config espera en ~/.local/bin/
- Inyección idempotente de variables de entorno en RC file
- Sanitización de configs: sin secretos, sin paths personales absolutos
