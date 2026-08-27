# install_terminal_workstation_linux.sh

Prepara una estación Debian para terminal, desarrollo, Neovim/LazyVim, runtimes
gestionados por mise, OpenCode y contenedores rootless con Podman.

- **Ruta:** `scripts/install/install_terminal_workstation_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `sudo`, `apt-get`; `curl` para herramientas upstream

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian con repositorios `main`, `contrib`, `non-free` y
  `non-free-firmware` habilitados.
- Usuario normal con `sudo` configurado. Si es una instalación nueva, ejecuta
  primero `configure_sudo_linux.sh` desde una consola root.
- Conexión a Internet para APT, LazyVim, mise, Boda y OpenCode.
- El script debe ejecutarse como `rafex`, nunca como `root`.

## Uso

Diagnóstico y plan sin cambios:

```sh
just install-terminal-workstation --check
just install-terminal-workstation --plan --stage terminal
```

Aplicación completa:

```sh
just install-terminal-workstation --apply --stage all
```

`all` instala las etapas recomendadas, incluyendo Podman, pero omite
`build-runtimes` porque Maven, Gradle y GraalVM descargan runtimes grandes.
Esa etapa se ejecuta de forma explícita cuando sea necesaria.

Después de aplicar, cierra y abre Alacritty. Debe conectarse a la sesión tmux
fija `thinkpad`. Las conexiones SSH no se envuelven automáticamente en tmux.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica sin modificar nada |
| `--plan` | `--dry-run` | Muestra las acciones previstas |
| `--apply` | — | Instala paquetes y escribe configuración |
| `--stage <etapa>` | — | `terminal`, `editor`, `runtimes`, `build-runtimes`, `containers`, `opencode` o `all` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `BODA_VERSION` | `0.2616.0` | Versión de Boda instalada mediante Cargo |
| `HOME` | entorno | Directorio del usuario; no debe apuntar a una ruta compartida |

No se aceptan contraseñas ni tokens mediante variables de entorno.

## Ejemplos

### Forma explícita recomendada

```sh
just install-terminal-workstation --apply --stage all
```

### Solo terminal y tmux

```sh
just install-terminal-workstation --apply --stage terminal
```

### Editor y runtimes

```sh
just install-terminal-workstation --apply --stage editor
just install-terminal-workstation --apply --stage runtimes
```

### Podman rootless

```sh
just install-terminal-workstation --apply --stage containers
podman run --rm docker.io/library/alpine:latest uname -a
```

### Runtimes adicionales

```sh
just install-terminal-workstation --apply --stage build-runtimes
mise ls
```

## Protecciones de seguridad

- `--check`, `--plan` y `--dry-run` no modifican el sistema.
- La contraseña de sudo solo se solicita mediante `sudo -v`.
- No se almacenan contraseñas, API keys ni credenciales.
- Las configuraciones existentes reciben respaldos fechados antes de cambiarse.
- Los bloques administrados son idempotentes y no se duplican.
- LazyVim respalda `~/.config/nvim`, datos, estado y caché antes de instalarse.
- mise, Boda y OpenCode se instalan en el espacio del usuario.
- Podman se instala sin activar un daemon privilegiado.
- No se modifican particiones, `fstab`, GRUB ni opciones de montaje.

## Fallos conocidos

### `Alacritty ya tiene [terminal.shell]`

**Causa:** agregar otra tabla TOML produciría una configuración inválida.

**Solución:** conserva la tabla existente y configura manualmente el programa
`$HOME/.local/bin/start-thinkpad-tmux`, o elimina la tabla después de guardar un
respaldo y vuelve a ejecutar el instalador.

### `LazyVim no se instaló porque ~/.config/nvim todavía existe`

**Causa:** otro proceso creó la ruta después del respaldo o el directorio es un
enlace simbólico.

**Solución:** revisa el respaldo `.bak.YYYYMMDD_HHMMSS`, mueve manualmente la
configuración anterior y vuelve a ejecutar la etapa `editor`.

### `mise`, `boda` u `opencode` no aparecen en el PATH

**Causa:** la shell actual todavía no cargó el bloque administrado de `.bashrc`.

**Solución:** abre una nueva shell o ejecuta `source ~/.bashrc`; verifica que
`~/.local/bin` y `~/.cargo/bin` estén en `PATH`.

### `Podman rootless` no puede crear un contenedor

**Causa:** faltan rangos `subuid/subgid`, configuración del usuario o soporte de
la sesión para namespaces rootless.

**Solución:** revisa `podman info`, `/etc/subuid`, `/etc/subgid` y la salida de
`loginctl`; no ejecutes Podman con sudo como solución permanente.

## Changelog

### [Unreleased]

- **feat:** instalador idempotente de terminal, LazyVim, mise, OpenCode y
  Podman rootless para ThinkPad Debian.
