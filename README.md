# scripts-random-utils-whatever

Colección de scripts de utilidad para macOS y Linux.

---

## Convención de nombres de scripts

El sufijo del archivo indica el sistema operativo soportado:

| Sufijo | Plataforma | Ejemplo |
|---|---|---|
| `*_macos.sh` / `*_macos.py` | Solo macOS | `create_usb_macos.sh` |
| `*_linux.sh` / `*_linux.py` | Solo Linux | `setup_linux.sh` |
| `*_unix.sh` / `*_unix.py` | macOS y Linux | `clean_unix.sh` |

Los scripts `.sh` sin sufijo de plataforma son legacy y deben migrarse.

---

## Estructura del repositorio

```
scripts/          ← scripts organizados por categoría
docs/             ← documentación de cada script
make/             ← módulos del Makefile (builder)
just/             ← módulos del Justfile (task runner)
```

Para lanzar scripts desde la raíz del repo:

```sh
just              # listar tareas disponibles
just <tarea>      # ejecutar una tarea
```

Para verificar y empaquetar:

```sh
make check        # verificar sintaxis de todos los scripts
make dist         # generar paquete distribuible
```