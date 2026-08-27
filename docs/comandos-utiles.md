---
title: Comandos útiles
description: Referencia de comandos frecuentes del repositorio
tags:
  - referencia
---

# Comandos y binarios útiles para la terminal

Alternativas prácticas a varios comandos nativos de macOS y Linux. La combinación más útil para localizar archivos grandes y limpiar carpetas es `ncdu` para explorar y `trash`/`trash-put` para borrar de forma recuperable.

- **SO requerido:** macOS, Linux
- **Dependencias:** las herramientas indicadas en cada sección

______________________________________________________________________

## Índice

- [Instalación](#instalacion)
- [Archivos grandes y uso de disco](#archivos-grandes-y-uso-de-disco)
- [Borrar carpetas con seguridad](#borrar-carpetas-con-seguridad)
- [Alternativas a comandos nativos](#alternativas-a-comandos-nativos)
- [Flujo recomendado de limpieza](#flujo-recomendado-de-limpieza)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Instalación

### macOS con Homebrew

```sh
brew install ncdu dust gdu fd bat ripgrep eza fzf zoxide trash
```

### Linux basado en Debian/Ubuntu

```sh
sudo apt update
sudo apt install ncdu ripgrep fd-find bat fzf trash-cli
```

`dust`, `gdu` y `eza` dependen de la versión de la distribución. Si no están disponibles en APT, deben instalarse desde el gestor de paquetes de la distribución o siguiendo el método recomendado por sus proyectos.

En algunas distribuciones los nombres de los binarios cambian:

| Paquete | Binario habitual |
|---|---|
| `fd-find` | `fdfind` |
| `bat` | `batcat` |
| `trash-cli` | `trash-put` |

Se pueden crear alias locales si se prefiere usar los nombres de macOS:

```sh
alias fd='fdfind'
alias bat='batcat'
alias trash='trash-put'
```

## Archivos grandes y uso de disco

### `ncdu`: explorar y borrar desde una interfaz interactiva

Es la opción principal para saber qué está ocupando espacio. Muestra el tamaño de carpetas y permite navegar hasta el archivo o directorio responsable.

```sh
ncdu -x --enable-delete .
ncdu -x --enable-delete "$HOME"
ncdu -x --enable-delete /var
```

- `-x` evita cruzar a otros sistemas de archivos o volúmenes montados.
- Dentro de `ncdu`, `Enter` entra en una carpeta, `q` sale y `d` solicita confirmación para borrar el elemento seleccionado.
- Empieza en una ruta concreta, como `~/Downloads` o `~/.cache`, antes de revisar `/`.

### `dust`: resumen visual de `du`

```sh
dust -d 2 .
dust -d 3 "$HOME/Downloads"
```

`-d` limita la profundidad para que la salida sea manejable. Es útil para detectar rápidamente qué subdirectorios consumen más espacio, pero no debe usarse como sustituto de una confirmación antes de borrar.

### `gdu`: alternativa rápida e interactiva

```sh
gdu -d 2 .
gdu "$HOME"
```

Puede ser más rápido que `du` en árboles grandes. La disponibilidad y las teclas de borrado pueden variar según la versión; para borrar de forma explícita y recuperable se recomienda `trash`/`trash-put`.

### Buscar archivos individuales grandes

Con `find`, sin instalar nada:

```sh
# Archivos mayores de 1 GiB en la carpeta actual
find . -type f -size +1G -print

# Archivos mayores de 500 MiB sin entrar en .git
find . -path './.git' -prune -o -type f -size +500M -print
```

Con `fd`, con una salida más cómoda:

```sh
fd --type f --hidden --exclude .git --size +1g .
fd --type f --hidden --exclude .git --size +500m --exec-batch du -h
```

Para una medición ordenada usando herramientas nativas:

```sh
du -ak . 2>/dev/null | sort -n | tail -n 30
```

Este último comando muestra tamaños en bloques de KiB y puede ser lento porque calcula el tamaño de cada archivo. `ncdu` suele ser mejor para una exploración repetida.

## Borrar carpetas con seguridad

### Opción recomendada: papelera

En macOS, con el paquete `trash` de Homebrew:

```sh
trash "$HOME/Downloads/carpeta-temporal"
```

En Linux, con `trash-cli`:

```sh
trash-put "$HOME/Downloads/carpeta-temporal"
trash-list
trash-restore
```

La papelera permite recuperar elementos si la ruta era incorrecta. Confirma siempre la ruta antes de ejecutarlo:

```sh
target="$HOME/Downloads/carpeta-temporal"
printf 'Se enviará a la papelera: %s\n' "$target"
ls -ld -- "$target" 2>/dev/null || stat "$target"
```

### Borrado permanente con confirmación

Si realmente debe eliminarse de forma irreversible:

```sh
rm -ri -- "$HOME/Downloads/carpeta-temporal"
```

- `-r` borra directorios recursivamente.
- `-i` solicita confirmación para los elementos que se van a borrar.
- `--` evita que una ruta que empieza con `-` se interprete como una opción.

Para borrar solo directorios vacíos, usa primero una vista previa:

```sh
find "$HOME/Downloads" -type d -empty -print
find "$HOME/Downloads" -type d -empty -delete
```

No uses `rm -rf` como primera opción: no pasa por la papelera y un error en la ruta puede eliminar datos inmediatamente.

## Alternativas a comandos nativos

| Comando nativo | Alternativa | Uso recomendado | Ejemplo |
|---|---|---|---|
| `find` | `fd` | Buscar archivos y directorios con filtros sencillos y salida legible | `fd --type f --extension log .` |
| `du` | `dust` | Resumen de tamaños por directorio | `dust -d 2 .` |
| `du` | `ncdu` | Explorar tamaños y limpiar interactivamente | `ncdu -x --enable-delete "$HOME"` |
| `cat` | `bat` | Ver archivos con colores, números de línea y paginación | `bat README.md` |
| `grep` | `rg` | Buscar texto respetando `.gitignore` y excluyendo `.git` automáticamente | `rg -n "TODO|FIXME"` |
| `ls` | `eza` | Listados con colores, metadatos y árbol | `eza -lah --git` |
| `rm` | `trash` / `trash-put` | Enviar archivos o carpetas a la papelera | `trash carpeta/` |
| historial del shell | `fzf` | Seleccionar comandos, archivos o procesos interactivamente | `history \| fzf` |
| `cd` | `zoxide` | Saltar a directorios visitados con frecuencia | `z proyecto` |

### `bat` para leer archivos

```sh
bat README.md
bat --paging=never --style=plain archivo.log
```

Para usarlo como un `cat` mejorado, sin paginación ni decoración:

```sh
bat --paging=never --style=plain archivo.txt
```

### `rg` para buscar texto

```sh
rg -n "cadena" .
rg -ni "cadena" --glob '*.md'
rg -n --hidden -g '!.git' "cadena" .
```

Por defecto, `rg` respeta `.gitignore`. Usa `--hidden` solo cuando necesites buscar también en archivos ocultos y conserva `-g '!.git'` para no recorrer el historial del repositorio.

### `fd` para buscar rutas

```sh
fd --type f --extension sh scripts/
fd --type d --hidden --exclude .git 'cache' "$HOME"
```

## Flujo recomendado de limpieza

```text
ncdu -x ~/Downloads
        ↓
identificar la carpeta o archivo grande
        ↓
verificar la ruta con ls -ld o stat
        ↓
trash carpeta/       (recuperable)
        ↓
trash-list / papelera del sistema
```

Para una limpieza del repositorio actual:

```sh
ncdu -x .
rg --files --hidden -g '!.git' | head
fd --type f --hidden --exclude .git --size +500m .
```

Antes de borrar `.cache`, `node_modules`, `target`, `build` o artefactos similares, confirma que no sean necesarios para una tarea en curso y que puedan regenerarse.

## Protecciones de seguridad

- No ejecutes comandos destructivos sobre `/`, `$HOME` completo o el directorio raíz del repositorio sin revisar antes la ruta.
- No combines una búsqueda amplia con borrado automático hasta probar primero con `-print` o una lista de vista previa.
- Usa `--` antes de rutas recibidas como entrada.
- Evita `sudo` para limpiar archivos de usuario; si un directorio requiere privilegios, revisa primero propietario y permisos.
- Recuerda que la papelera de otro volumen puede no comportarse igual que la papelera del volumen principal.
- En `ncdu`, no presiones `d` hasta haber seleccionado exactamente el elemento correcto.

## Fallos conocidos

### `command not found: fd`, `bat` o `trash`

**Causa:** el paquete no está instalado o Linux expone otro nombre (`fdfind`, `batcat` o `trash-put`).

**Solución:** revisa la sección [Instalación](#instalacion), ejecuta `command -v <binario>` y usa el nombre alternativo correspondiente.

### `ncdu` muestra menos espacio del esperado

**Causa:** `-x` excluye otros sistemas de archivos montados y los permisos pueden impedir leer algunas carpetas.

**Solución:** ejecuta `ncdu` sobre el volumen correcto y revisa los mensajes de permisos. No uses `sudo` sin entender qué volumen estás recorriendo.

### `rm: Permission denied`

**Causa:** el usuario no tiene permisos sobre el archivo o directorio.

**Solución:** inspecciona con `ls -ld` o `stat`; evita corregirlo con `sudo rm -rf` sin confirmar antes la ruta y el propietario.

## Changelog

### [Unreleased]

- **docs:** documentar herramientas modernas para buscar, inspeccionar y limpiar archivos en macOS y Linux.
