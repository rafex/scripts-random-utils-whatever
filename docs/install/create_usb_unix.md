# create_usb_unix.sh

Crea un USB booteable desde una imagen ISO en macOS y Linux usando `dd`.

- **Ruta:** `scripts/install/create_usb_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `diskutil`, `dd`, `sudo`
- **Task runner:** `just` (opcional, para lanzar desde la raíz del repo)

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Archivo .env](#archivo-env)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

> **Forma recomendada desde la raíz del repo:** usar `just create-usb`.

---

## Requisitos

- macOS (el script utiliza `diskutil` y `/dev/r*` específicos de macOS)
- `sudo` disponible y configurado para el usuario actual
- La imagen ISO debe existir en el sistema de archivos antes de ejecutar
- El disco USB debe estar conectado y reconocido por el sistema

---

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
just create-usb [opciones]
```

### Directamente

```sh
./scripts/install/create_usb_unix.sh [opciones]
```

Si no se especifica el disco destino por argumento o variable, el script lo pedirá de forma interactiva tras mostrar la lista de discos disponibles.

---

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--from <archivo.iso>` | `-f` | Ruta al archivo ISO fuente |
| `--to <diskN>` | `-t` | Disco destino (ej. `disk4`) |
| `--env <archivo.env>` | | Archivo `.env` con `USB_ISO` y `USB_DISK` |
| `--help` | `-h` | Mostrar ayuda |

---

## Variables de entorno

| Variable | Descripción |
|---|---|
| `USB_ISO` | Ruta al archivo ISO |
| `USB_DISK` | Disco destino (ej. `disk4`) |

Las variables de entorno tienen menos prioridad que los argumentos CLI explícitos.

**Orden de prioridad (mayor a menor):**

```
--from / --to  >  USB_ISO / USB_DISK (env)  >  .env file
```

---

## Archivo .env

El script carga automáticamente un archivo `.env` en el directorio actual.
Se puede especificar uno diferente con `--env`.

Solo se leen las variables `USB_ISO` y `USB_DISK` (no se hace `source` del archivo para evitar ejecución arbitraria de código).

**Formato:**

```env
USB_ISO=/ruta/debian.iso
USB_DISK=disk4
```

---

## Ejemplos

### Con `just` desde la raíz (recomendado)

```sh
just create-usb --from ~/Descargas/debian-12.iso --to disk4
```

```sh
just create-usb -f ~/Descargas/debian-12.iso -t disk4
```

Con variables de entorno:

```sh
USB_ISO=~/Descargas/debian-12.iso USB_DISK=disk4 just create-usb
```

Con archivo `.env`:

```sh
just create-usb --env config.env
```

Ver tareas disponibles en el repo:

```sh
just
```

---

### Directamente sobre el script

#### Forma explícita

```sh
./scripts/install/create_usb_unix.sh --from ~/Descargas/debian-12.iso --to disk4
```

#### Con alias cortos

```sh
./scripts/install/create_usb_unix.sh -f ~/Descargas/debian-12.iso -t disk4
```

#### Usando variables de entorno

```sh
USB_ISO=~/Descargas/debian-12.iso USB_DISK=disk4 ./scripts/install/create_usb_unix.sh
```

#### Con archivo .env en el directorio actual

```sh
# .env
USB_ISO=/Users/rafex/Descargas/debian-12.iso
USB_DISK=disk4
```

```sh
./scripts/install/create_usb_unix.sh
```

#### Con archivo .env en otra ruta

```sh
./scripts/install/create_usb_unix.sh --env /tmp/usb.env
```

#### Modo legacy (argumento posicional, compatibilidad hacia atrás)

```sh
./scripts/install/create_usb_unix.sh /ruta/debian.iso
```
> El disco se solicitará de forma interactiva.

### Ver progreso del `dd` desde otra terminal

Mientras el script copia la ISO, en otra terminal ejecutar:

```sh
sudo pkill -INFO dd
```

---

## Protecciones de seguridad

El script incluye múltiples salvaguardas antes de escribir en el disco:

| Verificación | Acción |
|---|---|
| `disk0` como destino | Bloqueo automático (error fatal) |
| Disco con `Device Location: Internal` | Bloqueo automático (error fatal) |
| Disco coincide con el disco de boot del sistema | Bloqueo automático (error fatal) |
| Disco sin `Removable Media: Yes` ni `External` | Advertencia en amarillo + confirmación adicional requerida |
| Confirmación final antes de escribir | Se requiere escribir `YES` en mayúsculas |

---

## Fallos conocidos

> Esta sección se irá completando con problemas encontrados en uso real.

### `dd: /dev/rdisk4: Permission denied`

**Causa:** el usuario no tiene permisos de escritura en el dispositivo raw.  
**Solución:** el script ya usa `sudo dd`. Verificar que `sudo` esté configurado. Si persiste, revisar si hay un proceso que tenga el disco montado:

```sh
diskutil unmountDisk /dev/disk4
```

---

### `dd: /dev/rdiskN: Resource busy`

**Causa:** el disco tiene particiones montadas al momento de ejecutar `dd`.  
**Solución:** el script ejecuta `diskutil unmountDisk` antes de `dd`. Si el error persiste:

```sh
diskutil unmountDisk force /dev/disk4
```

---

### El USB no arranca en el equipo destino

**Causa posible 1:** la ISO fue copiada incorrectamente o el proceso fue interrumpido.  
**Causa posible 2:** el equipo destino requiere modo UEFI/Legacy específico.  
**Solución:** repetir el proceso y verificar que `dd` termine sin errores antes de expulsar.

---

## Changelog

### [Unreleased]

- Pendiente: soporte para mostrar progreso de `dd` en tiempo real (pv).

---

### v1.2.0 — 2026-05-02

**style:** colores en la salida del script.

- Helpers de salida: `info` (cyan), `success` (verde), `warn` (amarillo), `error` (rojo)
- Banner de confirmación en rojo/bold
- Caja de advertencia en amarillo para discos no extraíbles
- Prompts interactivos coloreados
- Sección de discos y cabeceras en cyan/bold

---

### v1.1.0 — 2026-05-02

**feat:** mejoras de usabilidad y seguridad.

- Argumentos `--from`/`-f` y `--to`/`-t`
- Soporte para archivo `.env` vía `--env`
- Variables de entorno `USB_ISO` y `USB_DISK`
- Compatibilidad hacia atrás con argumento posicional
- Bloqueo de `disk0`, discos internos y disco de boot
- Advertencia si el disco no es externo/extraíble
- Banner de confirmación prominente antes de la escritura
- `usage()` con ejemplos y documentación

---

### v1.0.0 — 2026-05-02

**feat:** versión inicial.

- Recibe la ISO como primer argumento posicional
- Lista discos con `diskutil list`
- Solicita el disco de forma interactiva
- Validación básica del formato `diskN`
- Desmonta, copia con `dd`, sincroniza y expulsa
