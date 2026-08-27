---
title: md2pdf_unix.sh
description: Conversión de Markdown a PDF en macOS y Linux
tags:
  - desarrollo
---

# md2pdf_unix.sh

Convierte archivos Markdown a PDF con estilo profesional usando pandoc + weasyprint (con fallback automático a xelatex). Soporta temas CSS predefinidos, auto-detección de front-matter YAML, idempotencia (no reescribe PDFs sin cambios), archivo `.env` y conversión por lote recursiva.

- **Ruta:** `scripts/dev/md2pdf_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `pandoc`, `weasyprint` (o `xelatex`, `pdflatex`, `lualatex`)

______________________________________________________________________

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Archivo .env](#archivo-env)
- [Temas CSS](#temas-css)
- [Auto-detección de CSS](#auto-deteccion-de-css)
- [Auto-detección de título (YAML front matter)](#auto-deteccion-de-titulo-yaml-front-matter)
- [Fallback de motor PDF](#fallback-de-motor-pdf)
- [Idempotencia](#idempotencia)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

> **Forma recomendada desde la raíz del repo:** usar `just md2pdf`.

______________________________________________________________________

## Requisitos

```sh
# macOS
brew install pandoc
pip install weasyprint

# Debian/Ubuntu
sudo apt install pandoc
pip install weasyprint
```

Si no tienes `weasyprint`, el script hará fallback automático a `xelatex` (TeX Live) o `pdflatex`.

______________________________________________________________________

## Uso

### Desde la raíz del repositorio (recomendado)

```sh
just md2pdf -f documento.md
just md2pdf -f doc.md --theme academic -t "Mi Ensayo"
just md2pdf -i ./podcast -o ./pdfs --theme podcast
```

### Directamente

```sh
./scripts/dev/md2pdf_unix.sh [opciones]
```

Si no se especifica `--file`, convierte todos los archivos `.md` del directorio de entrada (default: `./input/`).

______________________________________________________________________

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--file <archivo.md>` | `-f` | Archivo Markdown a convertir |
| `--input <dir>` | `-i` | Directorio de entrada (default: `./input`) |
| `--output <dir>` | `-o` | Directorio de salida (default: junto al `.md`) |
| `--css-dir <dir>` | `-c` | Directorio de estilos CSS (default: `./css`) |
| `--css <archivo>` | `-s` | Archivo CSS a usar (auto-detecta si no se indica) |
| `--theme <nombre>` | | Tema CSS predefinido: `podcast` o `academic` (default: `podcast`) |
| `--title <título>` | `-t` | Título del documento (auto-detecta YAML front matter) |
| `--engine <motor>` | `-e` | Motor PDF: `weasyprint`, `xelatex`, `pdflatex`, `lualatex` (default: `weasyprint`) |
| `--margin <t,b,l,r>` | `-m` | Márgenes en formato `top,bottom,left,right` (default: `2cm,2cm,1.5cm,1.5cm`) |
| `--no-standalone` | | Desactiva modo standalone de pandoc |
| `--force` | | Reconstruir PDF aunque el `.md` no haya cambiado |
| `--dry-run` | | Muestra los comandos sin ejecutar |
| `--env <archivo>` | | Archivo `.env` con configuración (default: `.env`) |
| `--help` | `-h` | Muestra la ayuda |

______________________________________________________________________

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `MD2PDF_CSS_DIR` | `./css` | Directorio de estilos CSS |
| `MD2PDF_INPUT_DIR` | `./input` | Directorio de entrada |
| `MD2PDF_OUTPUT_DIR` | — | Directorio de salida (vacío = junto al `.md`) |
| `MD2PDF_CSS_FILE` | — | Archivo CSS (vacío = usa tema) |
| `MD2PDF_ENGINE` | `weasyprint` | Motor PDF |
| `MD2PDF_TITLE` | — | Título del documento |
| `MD2PDF_MARGINS` | `2cm,2cm,1.5cm,1.5cm` | Márgenes |
| `MD2PDF_STANDALONE` | `true` | Activar standalone |
| `MD2PDF_THEME` | `podcast` | Tema CSS: `podcast` o `academic` |
| `MD2PDF_FORCE` | `0` | Forzar reconstrucción |
| `MD2PDF_DRY_RUN` | `0` | Modo simulación |
| `MD2PDF_ENV_FILE` | `.env` | Ruta al archivo `.env` |

**Orden de prioridad:** flags CLI > variables de entorno > `.env` > defaults.

______________________________________________________________________

## Archivo .env

```env
# md2pdf — configuracion por defecto
MD2PDF_INPUT_DIR=./podcast
MD2PDF_OUTPUT_DIR=./pdfs
MD2PDF_THEME=podcast
MD2PDF_ENGINE=weasyprint
MD2PDF_MARGINS=2cm,2cm,1.5cm,1.5cm
MD2PDF_TITLE=Mi Podcast
```

El script carga automáticamente `.env` desde el directorio actual. Usa `--env otro.env` para una ruta personalizada.

______________________________________________________________________

## Temas CSS

El script incluye dos temas predefinidos en `assets/dev/`:

| Tema | Archivo | Estilo |
|---|---|---|
| `podcast` | `assets/dev/podcast-style.css` | Sans-serif cálido (ámbar `#c2410c`), lectura cómoda en pantalla |
| `academic` | `assets/dev/academic-style.css` | Serif formal (azul marino `#0a1628`), estilo postulación/ensayo |

______________________________________________________________________

## Auto-detección de CSS

Al procesar un archivo `.md`, el script busca automáticamente un CSS en su mismo directorio, en este orden:

1. `style.css`
1. `galaxia-style.css`
1. `podcast-style.css`
1. `academic-style.css`

Si encuentra alguno, lo usa en lugar del tema definido. Esto permite tener CSS específicos por proyecto sin modificar la configuración global.

**Ejemplo:**

```
proyecto/
├── episodio-01/
│   ├── lectura.md
│   └── style.css          ← se usa este CSS para lectura.md
├── episodio-02/
│   ├── lectura.md          ← usa el tema default (podcast)
│   └── otro.md
```

______________________________________________________________________

## Auto-detección de título (YAML front matter)

Si el archivo `.md` tiene front matter YAML con `title`, el script lo detecta automáticamente:

```markdown
---
title: "Episodio 1 — La conciencia del código"
date: 2026-08-04
---

# Contenido del episodio...
```

El título se inyecta como metadata de pandoc y aparece en las propiedades del PDF. El flag `--title` tiene prioridad sobre el YAML.

______________________________________________________________________

## Fallback de motor PDF

Cuando se usa `weasyprint` como motor y no está instalado, el script intenta automáticamente la siguiente cadena de fallback:

1. `weasyprint` → 2. `xelatex` → 3. `pdflatex`

Si se especifica explícitamente `xelatex` o `pdflatex` con `--engine`, no hay fallback — falla si no está disponible.

> **Nota:** los motores LaTeX (`xelatex`, `pdflatex`) no soportan CSS. El PDF se genera con el estilo por defecto de pandoc/LaTeX.

______________________________________________________________________

## Idempotencia

El script compara la fecha de modificación (`mtime`) del `.md` con el `.pdf` existente:

- Si el `.md` es más reciente que el `.pdf` → reconstruye.
- Si el `.pdf` no existe → construye.
- Si el `.md` no cambió desde la última conversión → se omite.

Usa `--force` para reconstruir todos los PDFs sin importar el estado.

______________________________________________________________________

## Ejemplos

```sh
# Convertir un archivo especifico con tema podcast
./scripts/dev/md2pdf_unix.sh -f documento.md --theme podcast

# Convertir con tema academico y titulo explicito
./scripts/dev/md2pdf_unix.sh -f doc.md --theme academic -t "Mi Ensayo"

# Convertir todos los .md de un directorio recursivamente
./scripts/dev/md2pdf_unix.sh -i ./podcast -o ./pdfs --theme podcast

# Forzar reconstruccion de todos los PDFs
./scripts/dev/md2pdf_unix.sh -i ./podcast --force

# Previsualizar comandos sin ejecutar
./scripts/dev/md2pdf_unix.sh -i ./podcast --dry-run

# Usar LaTeX como motor
./scripts/dev/md2pdf_unix.sh -f doc.md -e xelatex

# Con variables de entorno
MD2PDF_THEME=academic ./scripts/dev/md2pdf_unix.sh -f doc.md

# Con archivo .env personalizado
./scripts/dev/md2pdf_unix.sh --env produccion.env

# Via just (recomendado)
just md2pdf -f documento.md
just md2pdf -i ./podcast -o ./pdfs
```

______________________________________________________________________

## Fallos conocidos

### `weasyprint` no encuentra fuentes en macOS

**Causa:** weasyprint en macOS a veces no detecta las fuentes del sistema.

**Solución:** instalar fuentes adicionales:

```sh
brew install --cask font-helvetica-neue font-inter
```

O usar el fallback a xelatex con `--engine xelatex`.

### `ModuleNotFoundError: No module named 'weasyprint'`

**Causa:** weasyprint no está instalado en el Python activo.

**Solución:**

```sh
pip install weasyprint
# o si usas brew:
brew install weasyprint
```

### `pandoc: xelatex not found`

**Causa:** TeX Live no está instalado.

**Solución:**

```sh
# macOS
brew install basictex

# Linux
sudo apt install texlive-xetex
```

______________________________________________________________________

## Changelog

### [Unreleased]

### v2.0.0 — 2026-08-04

**feat:** Reescritura mayor con temas CSS, fallback de motor, idempotencia.

- Temas CSS predefinidos: `podcast` (sans-serif cálido) y `academic` (serif formal).
- CSS en `assets/dev/podcast-style.css` y `assets/dev/academic-style.css`.
- Auto-detección de CSS local en el directorio del `.md`.
- Auto-detección de título desde YAML front matter.
- Fallback automático de motor: weasyprint → xelatex → pdflatex.
- Idempotencia: solo reconstruye PDFs si el `.md` cambió. Flag `--force`.
- Soporte de archivo `.env` (`MD2PDF_*`). Flag `--env`.
- Output junto al `.md` por defecto (si no se especifica `--output`).

### v1.0.0 — 2026-07-31

**feat:** Script inicial de conversión Markdown a PDF con pandoc.

- Flags largos/cortos para todos los parámetros
- Conversión por lote de directorios
- Estructura de directorios para insumos (CSS, entrada, salida)
- Márgenes configurables
- Soporte para múltiples motores PDF (weasyprint, wkhtmltopdf, pdflatex, xelatex, lualatex)
- Modo `--dry-run`
