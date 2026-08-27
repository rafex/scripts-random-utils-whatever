# install_vscodium_linux.sh

Configura el repositorio APT oficial de VSCodium e instala el paquete DEB
`codium` en Debian. No instala extensiones ni importa configuraciones de VS
Code.

- **Ruta:** `scripts/install/install_vscodium_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `dpkg`, `sudo`; el script instala `wget`, `gnupg` y `ca-certificates` si faltan

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

- Debian 13 o posterior con `apt-get` y `dpkg`.
- Arquitectura `amd64` o `arm64`.
- `sudo` configurado para el usuario actual.
- Conectividad HTTPS a `download.vscodium.com` y `gitlab.com`.
- Ejecutar como usuario normal, no como root.

El flujo sigue la instalación oficial de VSCodium para paquetes DEB:
<https://vscodium.com/install>.

## Uso

Diagnosticar sin modificar nada:

```sh
just install-vscodium --check
```

Revisar el plan:

```sh
just install-vscodium --plan
```

Configurar el repositorio e instalar VSCodium:

```sh
just install-vscodium --apply
```

Verificar la instalación:

```sh
codium --version
apt-cache policy codium
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Diagnostica repositorio, clave y paquete sin cambios |
| `--plan` | `--dry-run` | Muestra acciones previstas sin modificar el sistema |
| `--apply` | — | Configura el repositorio oficial e instala `codium` |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

Este script no utiliza variables de entorno para repositorios, claves,
contraseñas ni configuraciones de VSCodium. La contraseña de sudo se solicita
únicamente mediante `sudo -v`.

## Ejemplos

### Forma explícita recomendada

```sh
just install-vscodium --apply
```

### Ejecución directa

```sh
bash scripts/install/install_vscodium_linux.sh --check
bash scripts/install/install_vscodium_linux.sh --plan
bash scripts/install/install_vscodium_linux.sh --apply
```

### Abrir un proyecto

```sh
codium .
```

## Protecciones de seguridad

- Usa exclusivamente `https://download.vscodium.com/debs` como origen APT.
- Usa un archivo `vscodium.sources` con `Signed-By` en lugar de `apt-key`.
- Descarga la clave oficial por HTTPS y verifica la huella PGP
  `1302DE60231889FE1EBACADC54678CF75A278D9C` antes de instalarla.
- Respaldará la clave y la fuente anterior en
  `/var/backups/rafex-vscodium/` antes de reemplazarlas.
- No acepta, almacena ni transmite contraseñas, tokens ni claves SSH.
- No instala VSCodium Insiders, extensiones, Flatpak ni Snap.

## Fallos conocidos

### `arquitectura no soportada por el repositorio VSCodium`

**Causa:** el repositorio oficial documentado ofrece paquetes `amd64` y
`arm64` para este flujo.

**Solución:** instala el paquete DEB específico de la arquitectura desde la
página oficial o utiliza una arquitectura soportada.

### `huella de clave VSCodium inesperada`

**Causa:** la clave descargada no coincide con la identidad esperada o la clave
del repositorio fue rotada.

**Solución:** no instales la clave manualmente. Comprueba la documentación
oficial y actualiza el fingerprint mediante una revisión explícita.

### `codium` no aparece en el menú de i3

**Causa:** i3 puede necesitar recargar sus lanzadores o el menú no ha
actualizado la caché de aplicaciones.

**Solución:** ejecuta `dex --autostart` o inicia directamente `codium`; cierra y
vuelve a abrir el menú de aplicaciones.

## Changelog

### [Unreleased]

- **feat:** añadir instalador Debian idempotente para VSCodium DEB oficial.
