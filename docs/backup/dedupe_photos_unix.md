# dedupe_photos_unix.py

Inventaría dos carpetas de fotos, identifica duplicados con SHA-256, propone coincidencias visuales y mantiene en SQLite el progreso y la verificación de la copia única.

- **Ruta:** `scripts/backup/dedupe_photos_unix.py`
- **SO requerido:** macOS, Linux (incluido TNAS)
- **Dependencias:** Python 2.7 o 3, SQLite incluido en Python; FFmpeg para los modos visuales

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

- A y B deben existir, ser carpetas diferentes y no estar anidadas entre sí.
- C debe estar fuera de A y B. El programa crea `C/photos/` y `C/.photo-dedupe.sqlite3`.
- Para comparar el contenido exacto basta Python con el módulo SQLite estándar. Los modos visuales requieren FFmpeg y sus decodificadores para el formato de imagen usado.
- Se consideran fotos los formatos de imagen comunes y RAW listados por el script. Si FFmpeg no puede leer un archivo, se registra como error y el borrado de los orígenes queda bloqueado.
- Los archivos de otros tipos, enlaces simbólicos y directorios no regulares también bloquean el borrado para evitar perder contenido que el programa no procesó.

## Uso

El modo recomendado para empezar calcula hashes y huellas visuales, copia una instancia de cada SHA-256 distinto y genera candidatas visuales para revisión:

```sh
python scripts/backup/dedupe_photos_unix.py run A B C --mode visual-review
```

La base SQLite permite reanudar la misma operación con las mismas rutas. La revisión de candidatas es explícita. Tras resolverlas, `reviewed` consolida únicamente los grupos aprobados. Para borrar los orígenes se usa un comando aparte con una confirmación explícita.

## Opciones

### `run`

| Opción | Alias | Descripción |
|---|---|---|
| `--mode exact\|visual-review\|reviewed` | — | `exact` deduplica solo SHA-256; `visual-review` añade candidatas dHash y conserva variantes; `reviewed` consolida solo candidatas aprobadas. Por defecto: `exact`. |
| `--ffmpeg <ejecutable>` | — | Ruta a FFmpeg para procesar huellas visuales. Por defecto: `ffmpeg` desde `PATH`. |

### `review`

| Opción | Alias | Descripción |
|---|---|---|
| `--id <n>` | — | ID de candidata mostrado por `candidates`. |
| `--decision approve\|distinct` | — | Aprueba la equivalencia visual o confirma que son fotos distintas. |

### `delete-sources`

| Opción | Alias | Descripción |
|---|---|---|
| `--confirm-delete` | — | Confirmación requerida para eliminar A y B después de validar el inventario y cada hash destino. |
| `--ffmpeg <ejecutable>` | — | Ruta de FFmpeg; se conserva para consistencia del comando. |

### `candidates`

Recibe C y muestra el ID, distancia dHash, decisión y rutas de cada coincidencia visual activa.

## Variables de entorno

El script no lee variables de entorno ni archivos `.env`. Las rutas se pasan como argumentos; `--ffmpeg` prevalece sobre la búsqueda de `ffmpeg` en `PATH`.

## Ejemplos

### Forma explícita recomendada

```sh
python scripts/backup/dedupe_photos_unix.py run /home/rafex/fotosA /home/rafex/fotosB /mnt/usb/usbshare1/fotos --mode visual-review
python scripts/backup/dedupe_photos_unix.py candidates /mnt/usb/usbshare1/fotos
```

### Revisar decisiones y consolidar

```sh
python scripts/backup/dedupe_photos_unix.py review /mnt/usb/usbshare1/fotos --id 1 --decision approve
python scripts/backup/dedupe_photos_unix.py review /mnt/usb/usbshare1/fotos --id 2 --decision distinct
python scripts/backup/dedupe_photos_unix.py run /home/rafex/fotosA /home/rafex/fotosB /mnt/usb/usbshare1/fotos --mode reviewed
```

### Borrar orígenes después de verificar

```sh
python scripts/backup/dedupe_photos_unix.py delete-sources /home/rafex/fotosA /home/rafex/fotosB /mnt/usb/usbshare1/fotos --confirm-delete
```

### Modo de compatibilidad por contenido exacto

```sh
python scripts/backup/dedupe_photos_unix.py run /home/rafex/fotosA /home/rafex/fotosB /mnt/usb/usbshare1/fotos --mode exact
```

## Protecciones de seguridad

- SHA-256 identifica duplicados byte por byte; las coincidencias visuales usan dHash con distancia de hasta 4 bits y siempre requieren revisión humana.
- Cada archivo se vuelve a hashear antes de copiar; la copia temporal se verifica antes y después de renombrarla a su destino final.
- SQLite registra hash, huella visual, ruta destino, decisión y estado verificado por cada foto para permitir reanudar.
- El modo `reviewed` solo elimina del directorio de fotos de C variantes visuales expresamente aprobadas, después de confirmar la copia de la representante. Los originales continúan en A y B hasta el comando separado de borrado.
- `delete-sources` vuelve a inventariar A/B, rechaza elementos desconocidos o candidatas pendientes, comprueba hashes del origen y de C, y requiere `--confirm-delete`.
- No se siguen enlaces simbólicos y C no puede solaparse con A o B.

## Fallos conocidos

### `FFmpeg no pudo leer la imagen`

**Causa:** el formato no está soportado por el FFmpeg instalado, el archivo está dañado o no es realmente una imagen.
**Solución:** conservar el origen, revisar el formato/archivo y usar un FFmpeg con el decodificador correspondiente antes de reintentar.

### `Hay candidata(s) visuales sin decisión`

**Causa:** el modo `visual-review` encontró fotos similares que todavía no se han revisado.
**Solución:** lista las candidatas y marca cada una como `approve` o `distinct`; luego vuelve a ejecutar `reviewed`.

### `El inventario actual no coincide con SQLite`

**Causa:** cambió una carpeta o archivo desde el último análisis.
**Solución:** vuelve a ejecutar `visual-review` o `exact` con las mismas rutas; conserva los orígenes hasta que la base muestre todas las copias verificadas.

## Changelog

### [Unreleased]

- Se agregará cualquier ajuste pendiente antes de publicar una versión.

### v1.0.0 — 2026-10-09

**feat:** consolidar fotos con verificación reanudable y control de borrado.

- Registra SHA-256, huellas dHash, decisiones y estado de copia en SQLite.
- Añade modos exacto, revisión visual y consolidación de candidatas aprobadas.
- Permite borrar los orígenes solo en una acción separada, con validación completa.
