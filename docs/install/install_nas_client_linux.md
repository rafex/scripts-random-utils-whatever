# install_nas_client_linux

Comprueba o instala el cliente CIFS requerido para montar recursos SMB/NAS en Linux. No instala un servidor Samba.

- **Ruta:** `scripts/install/install_nas_client_linux.sh`
- **SO requerido:** Linux (Debian/Ubuntu)
- **Dependencias:** `dpkg-query`, `apt-get`, `sudo` (para instalar)

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

Para comprobar basta con Debian/Ubuntu y `dpkg-query`. La instalación requiere `apt-get`, `sudo` y autorización para actualizar el índice e instalar paquetes.

## Uso

Usar `just install-nas-client --check` para comprobar el estado, `--plan` para ver los comandos previstos y `--apply` para instalar `cifs-utils`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el paquete y `mount.cifs` (predeterminado). |
| `--plan` | `--dry-run` | Muestra los comandos de APT sin ejecutarlos. |
| `--apply` | — | Actualiza APT e instala `cifs-utils`. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No utiliza variables de entorno de configuración. Los argumentos CLI determinan la acción.

## Ejemplos

Forma recomendada, primero revisar:

```bash
just install-nas-client --check
```

Ver las acciones previstas:

```bash
just install-nas-client --plan
```

Instalar el cliente SMB:

```bash
just install-nas-client --apply
```

No hay modo `.env` ni modo legacy.

## Protecciones de seguridad

- Instala únicamente `cifs-utils`; no instala ni configura un servidor Samba.
- `--plan` no ejecuta comandos de APT.
- El modo `--apply` pide autenticación con `sudo` antes de modificar paquetes.

## Fallos conocidos

### `este instalador requiere Debian/Ubuntu`

**Causa:** el instalador usa `dpkg-query` y APT.
**Solución:** instalar `cifs-utils` con el gestor de paquetes de la distribución o usar Debian/Ubuntu.

### `el paquete está instalado pero mount.cifs no aparece en PATH`

**Causa:** instalación incompleta o binario fuera del `PATH`.
**Solución:** revisar el estado de `cifs-utils` y la ubicación del ejecutable `mount.cifs`.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.0.0 — 2026-10-05

**feat:** añadir instalador del cliente CIFS para conectar recursos SMB/NAS.

- Ofrecer comprobación, plan de instalación y aplicación explícita en Debian/Ubuntu.
- Limitar la instalación al cliente `cifs-utils`, sin servidor Samba.
