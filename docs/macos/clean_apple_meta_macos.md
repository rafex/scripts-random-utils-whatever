# clean_apple_meta_macos.sh

Limpia metadatos Apple (`._*`, `.DS_Store`, atributos extendidos) en volúmenes montados que no soportan APFS/HFS+, como NAS, SMB, exFAT o FAT32.

- **Ruta:** `scripts/macos/clean_apple_meta_macos.sh`
- **SO requerido:** macOS
- **Dependencias:** `xattr`, `find` (incluidos en macOS)

---

## Índice

- [Requisitos](#requisitos)
- [Por qué aparecen estos archivos](#por-qué-aparecen-estos-archivos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

> **Forma recomendada desde la raíz del repo:** usar `just clean-apple-meta`.

---

## Requisitos

- macOS (el script verifica `uname -s` y aborta en Linux)
- El directorio a limpiar debe existir y ser accesible por el usuario actual
- Para limpiar volúmenes del sistema puede requerirse `sudo`

---

## Por qué aparecen estos archivos

macOS guarda metadatos de cada archivo/carpeta (resource fork, etiquetas Finder, cuarentena, atributos extendidos). En volúmenes nativos APFS/HFS+ esto se almacena internamente. En volúmenes no nativos (exFAT, FAT32, SMB, NFS, NAS), macOS los guarda como archivos auxiliares **AppleDouble**:

| Archivo original | Archivo de metadatos |
|---|---|
| `foto.jpg` | `._foto.jpg` |
| `proyecto/` | `._proyecto` |
| cualquier archivo | `.DS_Store` (por carpeta) |

El símbolo `@` en `ls -l` indica que una entrada tiene atributos extendidos activos. Aunque tengas configurado `DSDontWriteNetworkStores = 1`, esto solo afecta a `.DS_Store`, no a los archivos `._*`.

---

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
just clean-apple-meta --path /Volumes/rafex/repository
```

### Directamente

```sh
./scripts/macos/clean_apple_meta_macos.sh --path /Volumes/rafex/repository
```

---

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--path <ruta>` | `-p` | Ruta del volumen o directorio a limpiar |
| `--no-xattr` | | Omitir limpieza de atributos extendidos con `xattr -rc` |
| `--dry-run` | | Mostrar qué se eliminaría sin borrar nada |
| `--help` | `-h` | Mostrar la ayuda |

---

## Variables de entorno

| Variable | Descripción | Prioridad |
|---|---|---|
| `CLEAN_PATH` | Ruta del directorio a limpiar | Baja (los args CLI tienen prioridad) |

Orden de prioridad: argumento `--path` > variable de entorno `CLEAN_PATH`.

---

## Ejemplos

### Forma explícita (recomendada)

```sh
./scripts/macos/clean_apple_meta_macos.sh --path /Volumes/rafex/repository/github/rafex/ether
```

### Con variable de entorno

```sh
CLEAN_PATH=/Volumes/rafex/repository/github/rafex/ether \
  ./scripts/macos/clean_apple_meta_macos.sh
```

### Solo ver qué se borraría (sin borrar)

```sh
./scripts/macos/clean_apple_meta_macos.sh --path /Volumes/nas/datos --dry-run
```

### Omitir limpieza de xattrs (solo borrar archivos)

```sh
./scripts/macos/clean_apple_meta_macos.sh --path /Volumes/nas/datos --no-xattr
```

### Desde el task runner

```sh
just clean-apple-meta --path /Volumes/nas/datos
just clean-apple-meta --path /Volumes/nas/datos --dry-run
```

---

## Protecciones de seguridad

- El script aborta si se ejecuta fuera de macOS.
- La ruta se resuelve a su valor absoluto con `cd && pwd` antes de operar.
- Se valida que la ruta exista y sea un directorio antes de cualquier operación.
- No se usa `eval` ni interpolación sin sanitizar.
- Los conteos de archivos se hacen antes de borrar para informar al usuario.

---

## Fallos conocidos

### `xattr: [path]: No such file or directory` en algunos archivos

**Causa:** Archivos que desaparecen durante el recorrido de `xattr -rc` (race condition en sistemas activos).  
**Solución:** Normal en uso concurrente. Los archivos restantes sí se limpian. Vuelve a ejecutar el script si es necesario.

### Algunos `._*` vuelven a aparecer después de limpiar

**Causa:** Las carpetas aún tienen atributos extendidos (`@`). macOS los regenera al acceder al volumen.  
**Solución:** Ejecuta el script sin `--no-xattr` para que limpie también los xattrs con `xattr -rc`.

### `xattr: command not found`

**Causa:** Se está ejecutando en Linux (aunque el script debería haber abortado antes).  
**Solución:** Este script es exclusivo de macOS.

### No se eliminan los `.DS_Store` en el raíz del volumen

**Causa:** El Finder recrea `.DS_Store` inmediatamente si el volumen está abierto en una ventana del Finder.  
**Solución:** Cierra las ventanas del Finder que apunten a ese volumen antes de ejecutar el script.

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-05-02

**feat:** versión inicial.

- Limpieza de atributos extendidos con `xattr -rc`
- Eliminación de archivos `._*` AppleDouble con `find -delete`
- Eliminación de archivos `.DS_Store` con `find -delete`
- Modo `--dry-run` para previsualizar sin borrar
- Opción `--no-xattr` para omitir limpieza de atributos extendidos
- Soporte de `--path` y variable de entorno `CLEAN_PATH`
- Validación de macOS al inicio del script
