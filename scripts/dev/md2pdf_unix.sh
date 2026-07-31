#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# md2pdf_unix.sh
# Convierte archivos Markdown a PDF con estilo profesional usando pandoc +
# weasyprint. Soporta flags largos/cortos, estructura de directorios para
# insumos (CSS, entrada, salida) y conversión por lote.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Valores por defecto
# ─────────────────────────────────────────────────────────────────────────────
CSS_DIR="${MD2PDF_CSS_DIR:-./css}"
INPUT_DIR="${MD2PDF_INPUT_DIR:-./input}"
OUTPUT_DIR="${MD2PDF_OUTPUT_DIR:-./output}"
CSS_FILE="${MD2PDF_CSS_FILE:-galaxia-style.css}"
INPUT_FILE=""
PDF_ENGINE="${MD2PDF_ENGINE:-weasyprint}"
TITLE="${MD2PDF_TITLE:-}"
MARGINS="${MD2PDF_MARGINS:-2cm,2cm,1.5cm,1.5cm}"
STANDALONE="${MD2PDF_STANDALONE:-true}"
DRY_RUN="${MD2PDF_DRY_RUN:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Uso:${RESET}"
    echo "  $0 [opciones]"
    echo
    echo -e "${BOLD}Opciones:${RESET}"
    echo -e "  ${CYAN}-f, --file${RESET} <archivo.md>     Archivo Markdown a convertir"
    echo -e "  ${CYAN}-i, --input${RESET} <dir>          Directorio de entrada (default: ${INPUT_DIR})"
    echo -e "  ${CYAN}-o, --output${RESET} <dir>         Directorio de salida (default: ${OUTPUT_DIR})"
    echo -e "  ${CYAN}-c, --css-dir${RESET} <dir>        Directorio de estilos CSS (default: ${CSS_DIR})"
    echo -e "  ${CYAN}-s, --css${RESET} <archivo>        Archivo CSS a usar (default: ${CSS_FILE})"
    echo -e "  ${CYAN}-t, --title${RESET} <título>       Título del documento (metadata)"
    echo -e "  ${CYAN}-e, --engine${RESET} <motor>       Motor PDF: weasyprint|wkhtmltopdf|pdflatex (default: ${PDF_ENGINE})"
    echo -e "  ${CYAN}-m, --margin${RESET} <t,b,l,r>      Márgenes: top,bottom,left,right (default: ${MARGINS})"
    echo -e "  ${CYAN}    --no-standalone${RESET}         Desactiva modo standalone de pandoc"
    echo -e "  ${CYAN}    --dry-run${RESET}               Muestra los comandos sin ejecutar"
    echo -e "  ${CYAN}-h, --help${RESET}                  Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno:${RESET}"
    echo -e "  ${CYAN}MD2PDF_CSS_DIR${RESET}    Directorio de estilos CSS"
    echo -e "  ${CYAN}MD2PDF_INPUT_DIR${RESET}  Directorio de entrada"
    echo -e "  ${CYAN}MD2PDF_OUTPUT_DIR${RESET} Directorio de salida"
    echo -e "  ${CYAN}MD2PDF_CSS_FILE${RESET}   Archivo CSS"
    echo -e "  ${CYAN}MD2PDF_ENGINE${RESET}     Motor PDF"
    echo -e "  ${CYAN}MD2PDF_TITLE${RESET}      Título del documento"
    echo -e "  ${CYAN}MD2PDF_MARGINS${RESET}    Márgenes (formato top,bottom,left,right)"
    echo -e "  ${CYAN}MD2PDF_STANDALONE${RESET} Activar standalone (true|false)"
    echo -e "  ${CYAN}MD2PDF_DRY_RUN${RESET}    Modo simulación (1=no ejecutar)"
    echo
    echo -e "${BOLD}Estructura de directorios esperada:${RESET}"
    echo "  proyecto/"
    echo "  ├── css/"
    echo "  │   └── galaxia-style.css"
    echo "  ├── input/"
    echo "  │   ├── capitulo-01.md"
    echo "  │   └── capitulo-02.md"
    echo "  └── output/"
    echo "      ├── capitulo-01.pdf"
    echo "      └── capitulo-02.pdf"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 -f documento.md"
    echo "  $0 -f doc.md -t \"Mi Libro\" --margin 2cm,2.5cm,1.5cm,1.5cm"
    echo "  $0                                     # convierte todos los .md de input/"
    echo "  $0 -i ./src -o ./dist -c ./styles"
    echo "  $0 --dry-run                           # previsualiza comandos"
    echo "  $0 -f doc.md --engine pdflatex         # usar LaTeX como motor"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)           INPUT_FILE="$2";  shift 2 ;;
        -i|--input)          INPUT_DIR="$2";   shift 2 ;;
        -o|--output)         OUTPUT_DIR="$2";  shift 2 ;;
        -c|--css-dir)        CSS_DIR="$2";     shift 2 ;;
        -s|--css)            CSS_FILE="$2";    shift 2 ;;
        -t|--title)          TITLE="$2";       shift 2 ;;
        -e|--engine)         PDF_ENGINE="$2";  shift 2 ;;
        -m|--margin)         MARGINS="$2";     shift 2 ;;
        --no-standalone)     STANDALONE=false; shift ;;
        --dry-run)           DRY_RUN=1;        shift ;;
        -h|--help)           usage; exit 0 ;;
        *)
            # Compatibilidad posicional: único argumento = archivo de entrada
            if [[ -z "$INPUT_FILE" ]]; then
                INPUT_FILE="$1"
            else
                error "argumento desconocido: $1"
                echo
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones previas
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    if ! command -v pandoc &>/dev/null; then
        error "pandoc no está instalado. Instálalo con: sudo apt install pandoc"
        exit 1
    fi

    local engine_bin=""
    case "$PDF_ENGINE" in
        weasyprint)  engine_bin="weasyprint" ;;
        wkhtmltopdf) engine_bin="wkhtmltopdf" ;;
        pdflatex|xelatex|lualatex) engine_bin="$PDF_ENGINE" ;;
        *) error "motor PDF desconocido: ${BOLD}${PDF_ENGINE}${RESET}. Usa: weasyprint, wkhtmltopdf, pdflatex, xelatex, lualatex"
           exit 1 ;;
    esac

    if ! command -v "$engine_bin" &>/dev/null; then
        error "motor PDF '${BOLD}${engine_bin}${RESET}' no encontrado."
        case "$PDF_ENGINE" in
            weasyprint)  echo "  Instala con: pip install weasyprint" ;;
            wkhtmltopdf) echo "  Instala con: sudo apt install wkhtmltopdf" ;;
            pdflatex|xelatex|lualatex) echo "  Instala con: sudo apt install texlive-latex-recommended" ;;
        esac
        exit 1
    fi

    if [[ ! -d "$CSS_DIR" ]]; then
        error "directorio CSS no encontrado: ${BOLD}${CSS_DIR}${RESET}"
        exit 1
    fi

    local css_path="$CSS_DIR/$CSS_FILE"
    if [[ ! -f "$css_path" ]]; then
        error "archivo CSS no encontrado: ${BOLD}${css_path}${RESET}"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Obtener lista de archivos Markdown a procesar
# ─────────────────────────────────────────────────────────────────────────────
resolve_files() {
    if [[ -n "$INPUT_FILE" ]]; then
        if [[ ! -f "$INPUT_FILE" ]]; then
            error "archivo de entrada no encontrado: ${BOLD}${INPUT_FILE}${RESET}"
            exit 1
        fi
        echo "$INPUT_FILE"
    else
        if [[ ! -d "$INPUT_DIR" ]]; then
            error "directorio de entrada no encontrado: ${BOLD}${INPUT_DIR}${RESET}"
            exit 1
        fi
        # Buscar .md recursivamente en input dir
        local files
        files="$(find "$INPUT_DIR" -type f -name '*.md' | sort)"
        if [[ -z "$files" ]]; then
            error "no se encontraron archivos .md en ${BOLD}${INPUT_DIR}${RESET}"
            exit 1
        fi
        echo "$files"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Convertir un archivo Markdown a PDF
# ─────────────────────────────────────────────────────────────────────────────
convert_one() {
    local md_file="$1"
    local basename="${md_file##*/}"
    local pdf_name="${basename%.md}.pdf"
    local output_path="$OUTPUT_DIR/$pdf_name"
    local css_path="$CSS_DIR/$CSS_FILE"

    info "Procesando: ${BOLD}${basename}${RESET}"

    mkdir -p "$OUTPUT_DIR"

    local pandoc_opts=()
    pandoc_opts+=(--pdf-engine="$PDF_ENGINE")
    pandoc_opts+=(--css="$css_path")

    if [[ -n "$TITLE" ]]; then
        pandoc_opts+=(--metadata title="$TITLE")
    fi

    if [[ "$STANDALONE" == "true" ]]; then
        pandoc_opts+=(--standalone)
    fi

    # Márgenes: descomponer top,bottom,left,right
    IFS=',' read -r m_top m_bottom m_left m_right <<< "$MARGINS"
    pandoc_opts+=(-V margin-top="${m_top}")
    pandoc_opts+=(-V margin-bottom="${m_bottom}")
    pandoc_opts+=(-V margin-left="${m_left}")
    pandoc_opts+=(-V margin-right="${m_right}")

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "  ${CYAN}[dry-run]${RESET} pandoc \"${md_file}\" -o \"${output_path}\" ${pandoc_opts[*]}"
        return 0
    fi

    if pandoc "$md_file" -o "$output_path" "${pandoc_opts[@]}"; then
        success "${BOLD}${pdf_name}${RESET} → ${output_path}"
    else
        error "falló la conversión de ${BOLD}${basename}${RESET}"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Principal
# ─────────────────────────────────────────────────────────────────────────────
preflight

files=()
while IFS= read -r f; do
    files+=("$f")
done < <(resolve_files)

total="${#files[@]}"
echo
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}Markdown → PDF${RESET}"
echo -e "  CSS:      ${CSS_DIR}/${CSS_FILE}"
echo -e "  Motor:    ${PDF_ENGINE}"
echo -e "  Salida:   ${OUTPUT_DIR}"
echo -e "  Archivos: ${total}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

failed=0
for f in "${files[@]}"; do
    convert_one "$f" || ((failed++))
done

echo
if [[ "$failed" -eq 0 ]]; then
    success "${BOLD}${total} archivo(s) convertido(s) correctamente.${RESET}"
else
    error "${failed} de ${total} archivo(s) fallaron."
    exit 1
fi
