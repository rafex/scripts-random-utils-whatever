# md2pdf_unix.sh

Convierte archivos Markdown a PDF con estilo profesional usando pandoc + weasyprint. Soporta flags largos/cortos, estructura de directorios para CSS, entrada y salida, y conversión por lote de todos los `.md` de un directorio.

- **Ruta:** `scripts/dev/md2pdf_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `pandoc`, `weasyprint` (o `wkhtmltopdf`, `pdflatex`, `xelatex`, `lualatex`)

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)

---

## Requisitos

```sh
# Debian/Ubuntu
sudo apt install pandoc
pip install weasyprint

# macOS
brew install pandoc
pip install weasyprint
```

---

## Uso

```sh
./scripts/dev/md2pdf_unix.sh [opciones]
```

Si no se especifica `--file`, convierte todos los archivos `.md` del directorio de entrada (default: `./input/`).

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--file <archivo.md>` | `-f` | Archivo Markdown a convertir |
| `--input <dir>` | `-i` | Directorio de entrada (default: `./input`) |
| `--output <dir>` | `-o` | Directorio de salida (default: `./output`) |
| `--css-dir <dir>` | `-c` | Directorio de estilos CSS (default: `./css`) |
| `--css <archivo>` | `-s` | Archivo CSS a usar (default: `galaxia-style.css`) |
| `--title <título>` | `-t` | Título del documento (metadata) |
| `--engine <motor>` | `-e` | Motor PDF: `weasyprint`, `wkhtmltopdf`, `pdflatex`, `xelatex`, `lualatex` |
| `--margin <t,b,l,r>` | `-m` | Márgenes en formato `top,bottom,left,right` (default: `2cm,2cm,1.5cm,1.5cm`) |
| `--no-standalone` | | Desactiva modo standalone de pandoc |
| `--dry-run` | | Muestra los comandos sin ejecutar |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `MD2PDF_CSS_DIR` | `./css` | Directorio de estilos CSS |
| `MD2PDF_INPUT_DIR` | `./input` | Directorio de entrada |
| `MD2PDF_OUTPUT_DIR` | `./output` | Directorio de salida |
| `MD2PDF_CSS_FILE` | `galaxia-style.css` | Archivo CSS |
| `MD2PDF_ENGINE` | `weasyprint` | Motor PDF |
| `MD2PDF_TITLE` | — | Título del documento |
| `MD2PDF_MARGINS` | `2cm,2cm,1.5cm,1.5cm` | Márgenes |
| `MD2PDF_STANDALONE` | `true` | Activar standalone |
| `MD2PDF_DRY_RUN` | `0` | Modo simulación (1 = no ejecutar) |

**Orden de prioridad:** flags CLI > variables de entorno > defaults.

## Estructura de directorios esperada

```
proyecto/
├── css/
│   └── galaxia-style.css
├── input/
│   ├── capitulo-01.md
│   └── capitulo-02.md
└── output/
    ├── capitulo-01.pdf
    └── capitulo-02.pdf
```

## Ejemplos

```sh
# Convertir un archivo específico
./scripts/dev/md2pdf_unix.sh -f documento.md

# Convertir un archivo con título y márgenes personalizados
./scripts/dev/md2pdf_unix.sh -f doc.md -t "Mi Libro" -m 2cm,2.5cm,1.5cm,1.5cm

# Convertir todos los .md del directorio de entrada
./scripts/dev/md2pdf_unix.sh

# Directorios personalizados
./scripts/dev/md2pdf_unix.sh -i ./src -o ./dist -c ./styles

# Previsualizar comandos sin ejecutar
./scripts/dev/md2pdf_unix.sh --dry-run

# Usar LaTeX como motor
./scripts/dev/md2pdf_unix.sh -f doc.md -e pdflatex

# Con variables de entorno
MD2PDF_ENGINE=pdflatex ./scripts/dev/md2pdf_unix.sh -f doc.md
```

---

## Changelog

### [Unreleased]

### v1.0.0 — 2026-07-31

**feat:** Script inicial de conversión Markdown a PDF con pandoc.

- Flags largos/cortos para todos los parámetros
- Conversión por lote de directorios
- Estructura de directorios para insumos (CSS, entrada, salida)
- Márgenes configurables
- Soporte para múltiples motores PDF (weasyprint, wkhtmltopdf, pdflatex, xelatex, lualatex)
- Modo `--dry-run`
