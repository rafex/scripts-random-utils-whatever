# install_mount_nas_linux

Instala el comando autónomo `mountNas` en `~/.local/bin`, para conectarse a la TNAS sin ejecutar archivos desde el repositorio.

- **Ruta:** `scripts/install/install_mount_nas_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `install`, `cmp`, `mktemp`

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

Ejecutar como usuario normal desde una copia del repositorio. Para que `mountNas` conecte la TNAS también se requiere `cifs-utils` y el archivo `$HOME/.config/samba/tnas.credentials`.

## Uso

Ejecutar `just install-mount-nas --check` para consultar la instalación; usar `--plan` para previsualizar o `--apply` para instalar o actualizar el helper. Tras la instalación, `mountNas` funciona desde cualquier directorio y no necesita que el repositorio siga presente.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba que el helper instalado coincida con la versión del repositorio (predeterminado). |
| `--plan` | `--dry-run` | Muestra la ruta de origen y destino sin modificar archivos. |
| `--apply` | — | Instala o actualiza `~/.local/bin/mountNas`. |
| `--status` | — | Muestra si existe y si coincide con la versión fuente. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `NAS_INSTALL_TARGET` | Ruta alternativa de instalación; por defecto `$HOME/.local/bin/mountNas`. Útil para pruebas o instalaciones personalizadas. |

## Ejemplos

Forma recomendada:

```bash
just install-mount-nas --apply
```

Previsualizar:

```bash
just install-mount-nas --plan
```

Después de instalar, desde cualquier directorio:

```bash
mountNas
```

## Protecciones de seguridad

- Escribe primero un archivo temporal y lo mueve al destino al terminar, para evitar dejar una instalación parcial.
- Al actualizar un archivo distinto, conserva una copia `mountNas.bak.<fecha>`.
- Instala el helper con modo `0755`; no copia ni modifica el archivo de credenciales.

## Fallos conocidos

### `mountNas no está instalado`

**Causa:** el comando todavía no se instaló en `~/.local/bin`.
**Solución:** ejecutar `just install-mount-nas --apply` desde el repositorio.

### `mountNas: command not found`

**Causa:** `~/.local/bin` no está en `PATH`.
**Solución:** añadir `export PATH="$HOME/.local/bin:$PATH"` al perfil de shell e iniciar una nueva terminal; también se puede invocar `~/.local/bin/mountNas` directamente.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.0.0 — 2026-10-05

**feat:** instalar un helper de conexión independiente del checkout del repositorio.

- Instalar o actualizar `mountNas` con reemplazo atómico y respaldo previo.
