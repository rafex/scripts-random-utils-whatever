# AGENTS.md

Guía de convenciones para documentar scripts en este repositorio.

---

## Estructura de documentación para scripts

Cada script debe tener un archivo Markdown de documentación en:

```
docs/<categoria>/<nombre-del-script>.md
```

Donde `<categoria>` refleja el subdirectorio dentro de `scripts/`.

**Ejemplo:**

| Script | Documentación |
|---|---|
| `scripts/install/create_usb_macos_debian.sh` | `docs/install/create_usb_macos_debian.md` |

---

## Plantilla de documento

El archivo Markdown debe seguir esta estructura en orden:

```markdown
# <nombre-del-script>

Descripción breve en una o dos líneas.

- **Ruta:** `scripts/<categoria>/<nombre>.sh`
- **SO requerido:** <macOS | Linux | ambos>
- **Dependencias:** <lista de herramientas externas>

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Archivo .env        ← solo si el script soporta .env
## Ejemplos
## Protecciones de seguridad   ← solo si aplica
## Fallos conocidos
## Changelog
```

---

## Sección: Opciones

Documentar cada opción en tabla:

```markdown
| Opción | Alias | Descripción |
|---|---|---|
| `--from <archivo>` | `-f` | Descripción |
```

---

## Sección: Variables de entorno

Documentar variables en tabla. Indicar el orden de prioridad cuando
coexisten argumentos CLI, variables de entorno y `.env`.

---

## Sección: Ejemplos

Incluir al menos:
- Forma explícita/recomendada
- Forma con variables de entorno
- Forma con archivo `.env` (si aplica)
- Modo legacy / compatibilidad (si aplica)

---

## Sección: Fallos conocidos

Formato por entrada:

```markdown
### `mensaje de error o título del fallo`

**Causa:** ...
**Solución:** ...
```

Agregar aquí los errores que se encuentren en uso real, con su causa y solución.

---

## Sección: Changelog

Usar formato [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) adaptado con conventional commits.

```markdown
### [Unreleased]
- Cambios pendientes de release.

### vX.Y.Z — YYYY-MM-DD

**<tipo>:** resumen del cambio.

- Detalle 1
- Detalle 2
```

**Tipos válidos:** `feat`, `fix`, `style`, `refactor`, `docs`, `chore`.

---

## Convención de versiones para scripts

Usar versionado semántico **vMAJOR.MINOR.PATCH**:

| Tipo de cambio | Incremento |
|---|---|
| Cambio incompatible o reescritura | MAJOR |
| Nueva funcionalidad sin romper compatibilidad | MINOR |
| Corrección de bug o ajuste menor | PATCH |

---

## Soporte de plataformas

### Convención de sufijos en nombres de scripts

El sufijo del nombre del archivo declara el soporte de plataforma:

| Sufijo | Plataforma soportada | Ejemplo |
|---|---|---|
| `*_macos.sh` / `*_macos.py` | Solo macOS | `create_usb_macos.sh` |
| `*_linux.sh` / `*_linux.py` | Solo Linux | `setup_linux.sh` |
| `*_unix.sh` / `*_unix.py` | macOS y Linux | `clean_tmp_unix.sh` |

Esta convención aplica a cualquier extensión: `.sh`, `.bash`, `.py`.

Los scripts sin sufijo de plataforma son **legacy** y deben migrarse al nuevo esquema al ser modificados.

### Directriz general

Todos los scripts de este repositorio deben **soportar macOS y Linux** salvo que sea técnicamente imposible. El campo `SO requerido` en la documentación indica el soporte real declarado.

| Valor | Significado |
|---|---|
| `macOS` | Solo funciona en macOS (uso de `diskutil`, APIs exclusivas, etc.) |
| `Linux` | Solo funciona en Linux |
| `macOS, Linux` | Soporta ambos sistemas |

### Cómo implementar soporte dual

Detectar el sistema operativo al inicio del script:

```bash
OS_TYPE="$(uname -s)"   # Darwin = macOS, Linux = Linux
```

Bifurcar la lógica específica del SO con bloques `if/else`:

```bash
if [[ "$OS_TYPE" == "Darwin" ]]; then
  # comando macOS
else
  # comando Linux equivalente
fi
```

### Herramientas con equivalentes por plataforma

| Tarea | macOS | Linux |
|---|---|---|
| Listar discos | `diskutil list` | `lsblk` |
| Info de disco | `diskutil info /dev/diskN` | `lsblk -o ... /dev/sdX` |
| Desmontar disco | `diskutil unmountDisk /dev/diskN` | `udisksctl unmount` / `umount` |
| Expulsar disco | `diskutil eject /dev/diskN` | `udisksctl power-off` / `eject` |
| Disco de boot | `diskutil info /` → `Part of Whole` | `lsblk -no PKNAME $(findmnt -n -o SOURCE /)` |
| Disco extraíble | `diskutil info` → `Removable Media` | `/sys/block/<dev>/removable` |
| Progreso de `dd` | `kill -INFO <pid>` (SIGINFO) | `dd ... status=progress` |

### Progreso de `dd`

Orden de preferencia (cross-platform):

1. **`pv`** disponible → `pv "$ISO" | sudo dd of=...` (funciona en ambos)
2. **Linux** → `dd ... status=progress`
3. **macOS sin `pv`** → `dd` en background + bucle `kill -INFO $dd_pid`

---

## Referencias

- Documentación de ejemplo: [docs/install/create_usb_macos_debian.md](docs/install/create_usb_macos_debian.md)

---

## Makefile y Justfile — Responsabilidades separadas

El repositorio tiene dos archivos de automatización en la raíz con **responsabilidades únicas y no superpuestas**. Una misma acción nunca puede existir en ambos.

| Archivo | Rol | Responsabilidad |
|---|---|---|
| `Makefile` | **Builder** | Verificación de sintaxis, linting, empaquetado y generación de artefactos |
| `Justfile` | **Task runner** | Lanzar los scripts del repositorio desde la raíz |

### Makefile (Builder)

- Solo contiene tareas que **producen o verifican artefactos**: `check`, `shellcheck`, `dist`, `clean`.
- No ejecuta scripts de usuario directamente.
- Se modulariza con archivos `.mk` en `make/`:

```
make/
  check.mk   ← verificación de sintaxis y linting
  dist.mk    ← empaquetado y limpieza
```

**Añadir un módulo:**

```makefile
# En Makefile
include make/<nuevo>.mk
```

### Justfile (Task runner)

- Solo contiene tareas que **invocan scripts** del repositorio.
- No construye ni empaqueta nada.
- Se modulariza con archivos `.just` en `just/`, uno por categoría de scripts:

```
just/
  install.just   ← tareas para scripts/install/
```

**Añadir un módulo:**

```justfile
# En Justfile
import 'just/<nueva-categoria>.just'
```

**Añadir una tarea para un nuevo script** en `just/<categoria>.just`:

```justfile
# Descripción breve de la tarea
nombre-tarea *args:
    bash scripts/<categoria>/<script>.sh {{args}}
```

### Regla de no solapamiento

| Acción | Makefile | Justfile |
|---|---|---|
| Verificar sintaxis bash | ✓ | ✗ |
| Empaquetar scripts | ✓ | ✗ |
| Limpiar artefactos | ✓ | ✗ |
| Ejecutar un script | ✗ | ✓ |
| Listar tareas disponibles | ✗ | ✓ (`just`) |
