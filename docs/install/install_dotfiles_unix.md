# install_dotfiles_unix.sh

Empaqueta los dotfiles de i3wm en un `tar.gz` distribuible con un instalador autocontenido. El paquete se transfiere a cualquier máquina Debian/Linux y al extraerlo contiene su propio `install.sh` que detecta shell, verifica sudo, instala paquetes, copia configs, scripts y añade variables de entorno.

- **Ruta:** `scripts/install/install_dotfiles_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `tar`

---

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

---

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
2. **Verifica sudo**:
   - Con sudo → instala paquetes vía `apt-get`
   - Sin sudo → advierte y salta instalación de paquetes (todo en `~/.config/`)
3. **Backup** de configs existentes → `~/.config/<app>.bak.<timestamp>`
4. **Copia configs** a `~/.config/i3/`, `~/.config/i3status/`, etc.
5. **Copia Xresources** a `~/.Xresources`
6. **Copia scripts** a `~/.local/bin/` (con nombres que i3 config espera)
7. **Crea directorios** de imágenes: `~/Imágenes/FondosDePantalla/`, `~/Imágenes/CapturasDePantalla/`
8. **Inyecta env vars** en el RC file (idempotente):
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
just install-dotfiles
just install-dotfiles --dry-run
```

---

## Archivos del repositorio asociados

| Archivo | Propósito |
|---|---|
| `dotfiles/profiles/<perfil>/config/i3/config` | Configuración de i3wm (sanitizada, sin secretos) |
| `dotfiles/install.sh` | Instalador autocontenido dentro del tar.gz |
| `dotfiles/profiles/<perfil>/deps.txt` | Lista de paquetes apt |

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-07-31

**feat:** Empaquetador de dotfiles i3wm con instalador autocontenido.

- Empaquetador: genera tar.gz con configs, scripts auxiliares, deps.txt e install.sh
- Instalador autocontenido: detecta shell, verifica sudo, instala paquetes, copia configs
- Mapeo de scripts del repo a nombres que i3 config espera en ~/.local/bin/
- Inyección idempotente de variables de entorno en RC file
- Sanitización de configs: sin secretos, sin paths personales absolutos
