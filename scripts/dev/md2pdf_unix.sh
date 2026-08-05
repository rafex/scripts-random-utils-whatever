#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# md2pdf_unix.sh  v2.0.0
# Convierte archivos Markdown a PDF con estilo profesional usando pandoc +
# weasyprint (fallback a xelatex). Soporta temas CSS, auto-deteccion de
# front-matter YAML, idempotencia, .env y conversion por lote recursiva.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Colores
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Directorio base del script (para resolver paths relativos)
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Valores por defecto
# ─────────────────────────────────────────────────────────────────────────────
CSS_DIR="${MD2PDF_CSS_DIR:-./css}"
INPUT_DIR="${MD2PDF_INPUT_DIR:-./input}"
OUTPUT_DIR="${MD2PDF_OUTPUT_DIR:-}"
CSS_FILE="${MD2PDF_CSS_FILE:-}"
PDF_ENGINE="${MD2PDF_ENGINE:-weasyprint}"
TITLE="${MD2PDF_TITLE:-}"
MARGINS="${MD2PDF_MARGINS:-2cm,2cm,1.5cm,1.5cm}"
STANDALONE="${MD2PDF_STANDALONE:-true}"
THEME="${MD2PDF_THEME:-podcast}"
DRY_RUN="${MD2PDF_DRY_RUN:-0}"
FORCE="${MD2PDF_FORCE:-0}"
ENV_FILE="${MD2PDF_ENV_FILE:-.env}"
INPUT_FILE=""

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
    echo -e "  ${CYAN}-o, --output${RESET} <dir>         Directorio de salida (default: junto al .md)"
    echo -e "  ${CYAN}-c, --css-dir${RESET} <dir>        Directorio de estilos CSS (default: ${CSS_DIR})"
    echo -e "  ${CYAN}-s, --css${RESET} <archivo>        Archivo CSS a usar (detecta auto si no se indica)"
    echo -e "  ${CYAN}    --theme${RESET} <nombre>        Tema CSS predefinido: podcast|academic (default: ${THEME})"
    echo -e "  ${CYAN}-t, --title${RESET} <titulo>        Titulo del documento (auto-detecta YAML front matter)"
    echo -e "  ${CYAN}-e, --engine${RESET} <motor>        Motor PDF: weasyprint|xelatex|pdflatex|lualatex (default: ${PDF_ENGINE})"
    echo -e "  ${CYAN}-m, --margin${RESET} <t,b,l,r>      Margenes: top,bottom,left,right (default: ${MARGINS})"
    echo -e "  ${CYAN}    --no-standalone${RESET}          Desactiva modo standalone de pandoc"
    echo -e "  ${CYAN}    --force${RESET}                  Reconstruir PDF aunque el .md no haya cambiado"
    echo -e "  ${CYAN}    --dry-run${RESET}                Muestra los comandos sin ejecutar"
    echo -e "  ${CYAN}    --env${RESET} <archivo>          Archivo .env con configuracion (default: .env)"
    echo -e "  ${CYAN}-h, --help${RESET}                  Esta ayuda"
    echo
    echo -e "${BOLD}Variables de entorno / .env:${RESET}"
    echo -e "  ${CYAN}MD2PDF_CSS_DIR${RESET}     Directorio de estilos CSS"
    echo -e "  ${CYAN}MD2PDF_INPUT_DIR${RESET}   Directorio de entrada"
    echo -e "  ${CYAN}MD2PDF_OUTPUT_DIR${RESET}  Directorio de salida"
    echo -e "  ${CYAN}MD2PDF_CSS_FILE${RESET}    Archivo CSS"
    echo -e "  ${CYAN}MD2PDF_ENGINE${RESET}      Motor PDF (weasyprint|xelatex|pdflatex|lualatex)"
    echo -e "  ${CYAN}MD2PDF_TITLE${RESET}       Titulo del documento"
    echo -e "  ${CYAN}MD2PDF_MARGINS${RESET}     Margenes (formato top,bottom,left,right)"
    echo -e "  ${CYAN}MD2PDF_STANDALONE${RESET}  Activar standalone (true|false)"
    echo -e "  ${CYAN}MD2PDF_THEME${RESET}       Tema CSS: podcast|academic"
    echo -e "  ${CYAN}MD2PDF_FORCE${RESET}       Forzar reconstruccion (1|0)"
    echo -e "  ${CYAN}MD2PDF_DRY_RUN${RESET}     Modo simulacion (1=no ejecutar)"
    echo -e "  ${CYAN}MD2PDF_ENV_FILE${RESET}    Ruta al archivo .env"
    echo
    echo -e "${BOLD}Temas disponibles:${RESET}"
    echo -e "  ${CYAN}podcast${RESET}   Sans-serif calido (ambar #c2410c), lectura comoda en pantalla"
    echo -e "  ${CYAN}academic${RESET}  Serif formal (azul marino #0a1628), estilo postulacion"
    echo
    echo -e "${BOLD}Ejemplos:${RESET}"
    echo "  $0 -f documento.md"
    echo "  $0 -f doc.md --theme academic -t \"Mi Ensayo\""
    echo "  $0                                                # convierte todos los .md de input/"
    echo "  $0 -i ./podcast -o ./pdfs --theme podcast --force"
    echo "  $0 --dry-run                                      # previsualiza comandos"
    echo "  $0 -f doc.md -e xelatex                           # usar LaTeX como motor"
    echo "  MD2PDF_THEME=academic $0 -f doc.md                # via variable de entorno"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cargar .env (solo variables MD2PDF_* para evitar ejecucion arbitraria)
# ─────────────────────────────────────────────────────────────────────────────
load_env_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return
    fi

    local val
    while IFS='=' read -r key val || [[ -n "$key" ]]; do
        key="${key// /}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        case "$key" in
            MD2PDF_CSS_DIR)    val="$(echo "$val" | tr -d '"'"'"'')" && CSS_DIR="$val" ;;
            MD2PDF_INPUT_DIR)  val="$(echo "$val" | tr -d '"'"'"'')" && INPUT_DIR="$val" ;;
            MD2PDF_OUTPUT_DIR) val="$(echo "$val" | tr -d '"'"'"'')" && OUTPUT_DIR="$val" ;;
            MD2PDF_CSS_FILE)   val="$(echo "$val" | tr -d '"'"'"'')" && CSS_FILE="$val" ;;
            MD2PDF_ENGINE)     val="$(echo "$val" | tr -d '"'"'"'')" && PDF_ENGINE="$val" ;;
            MD2PDF_TITLE)      val="$(echo "$val" | tr -d '"'"'"'')" && TITLE="$val" ;;
            MD2PDF_MARGINS)    val="$(echo "$val" | tr -d '"'"'"'')" && MARGINS="$val" ;;
            MD2PDF_STANDALONE) val="$(echo "$val" | tr -d '"'"'"'')" && STANDALONE="$val" ;;
            MD2PDF_THEME)      val="$(echo "$val" | tr -d '"'"'"'')" && THEME="$val" ;;
            MD2PDF_FORCE)      val="$(echo "$val" | tr -d '"'"'"'')" && FORCE="$val" ;;
            MD2PDF_DRY_RUN)    val="$(echo "$val" | tr -d '"'"'"'')" && DRY_RUN="$val" ;;
            MD2PDF_ENV_FILE)   val="$(echo "$val" | tr -d '"'"'"'')" && ENV_FILE="$val" ;;
        esac
    done < "$file"
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
        --theme)             THEME="$2";       shift 2 ;;
        -t|--title)          TITLE="$2";       shift 2 ;;
        -e|--engine)         PDF_ENGINE="$2";  shift 2 ;;
        -m|--margin)         MARGINS="$2";     shift 2 ;;
        --env)               ENV_FILE="$2";    shift 2 ;;
        --no-standalone)     STANDALONE=false; shift ;;
        --force)             FORCE=1;          shift ;;
        --dry-run)           DRY_RUN=1;        shift ;;
        -h|--help)           usage; exit 0 ;;
        *)
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

# Cargar .env (los args de CLI tienen prioridad ya que ya estan aplicados)
load_env_file "$ENV_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# Resolver ruta del CSS por tema si no se especifico un archivo CSS
# ─────────────────────────────────────────────────────────────────────────────
resolve_theme_css() {
    local theme="$1"
    local assets_css="$REPO_ROOT/assets/dev/${theme}-style.css"

    case "$theme" in
        podcast|academic) ;;
        *)
            error "tema desconocido: ${BOLD}${theme}${RESET}. Usa: podcast, academic"
            exit 1
            ;;
    esac

    if [[ -f "$assets_css" ]]; then
        CSS_DIR="$(dirname "$assets_css")"
        CSS_FILE="$(basename "$assets_css")"
    else
        warn "CSS de tema '${theme}' no encontrado en assets (${assets_css})"
        warn "Asegurate de tener assets/dev/${theme}-style.css en el repositorio"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Extraer titulo del YAML front matter del archivo .md
# ─────────────────────────────────────────────────────────────────────────────
extract_yaml_title() {
    local md_file="$1"
    local in_front=0

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if [[ "$in_front" -eq 0 ]]; then
                in_front=1
                continue
            else
                break
            fi
        fi
        if [[ "$in_front" -eq 1 && "$line" =~ ^title:\ *\"?(.+)\"?$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return
        fi
    done < "$md_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detectar CSS junto al archivo .md
# ─────────────────────────────────────────────────────────────────────────────
detect_local_css() {
    local md_file="$1"
    local md_dir
    md_dir="$(dirname "$md_file")"

    local candidates=(
        "$md_dir/style.css"
        "$md_dir/galaxia-style.css"
        "$md_dir/podcast-style.css"
        "$md_dir/academic-style.css"
    )

    for css_path in "${candidates[@]}"; do
        if [[ -f "$css_path" ]]; then
            CSS_DIR="$(dirname "$css_path")"
            CSS_FILE="$(basename "$css_path")"
            info "CSS auto-detectado: ${BOLD}${css_path}${RESET}"
            return 0
        fi
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolver el motor PDF con fallback
# ─────────────────────────────────────────────────────────────────────────────
resolve_engine() {
    local engine="$1"

    case "$engine" in
        weasyprint)
            if command -v weasyprint &>/dev/null; then
                echo "weasyprint"
                return
            fi
            warn "weasyprint no encontrado — intentando fallback a xelatex..."
            if command -v xelatex &>/dev/null; then
                echo "xelatex"
                return
            fi
            warn "xelatex no encontrado — intentando fallback a pdflatex..."
            if command -v pdflatex &>/dev/null; then
                echo "pdflatex"
                return
            fi
            error "ningun motor PDF disponible (weasyprint, xelatex, pdflatex)"
            echo "  Instala weasyprint:  pip install weasyprint"
            echo "  Instala xelatex:     brew install basictex  (macOS)"
            echo "                        sudo apt install texlive-xetex  (Linux)"
            exit 1
            ;;
        xelatex|pdflatex|lualatex)
            if command -v "$engine" &>/dev/null; then
                echo "$engine"
                return
            fi
            error "motor ${BOLD}${engine}${RESET} no encontrado"
            echo "  Instalalo con: sudo apt install texlive-latex-recommended  (Linux)"
            echo "                 brew install basictex                       (macOS)"
            exit 1
            ;;
        *)
            error "motor PDF desconocido: ${BOLD}${engine}${RESET}"
            echo "  Usa: weasyprint, xelatex, pdflatex, lualatex"
            exit 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Validaciones previas
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    if ! command -v pandoc &>/dev/null; then
        error "pandoc no esta instalado."
        echo "  macOS:  brew install pandoc"
        echo "  Linux:  sudo apt install pandoc"
        exit 1
    fi

    PDF_ENGINE="$(resolve_engine "$PDF_ENGINE")"

    # Si no se especifico CSS_FILE, usar el tema
    if [[ -z "$CSS_FILE" ]]; then
        resolve_theme_css "$THEME"
    fi

    # Si aun no hay CSS_FILE (no hay assets), dejamos que falle detect_local_css
    # o el convertidor deje pasar (xelatex no necesita CSS)
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
# Determinar si un PDF debe reconstruirse (idempotencia)
# ─────────────────────────────────────────────────────────────────────────────
needs_rebuild() {
    local md_file="$1"
    local pdf_file="$2"

    if [[ "$FORCE" -eq 1 ]]; then
        return 0
    fi

    if [[ ! -f "$pdf_file" ]]; then
        return 0
    fi

    # Comparar mtime: si .md es mas nuevo que .pdf, reconstruir
    if [[ "$md_file" -nt "$pdf_file" ]]; then
        return 0
    fi

    info "Sin cambios en ${BOLD}$(basename "$md_file")${RESET} — se omite (usa --force para reconstruir)"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Convertir un archivo Markdown a PDF
# ─────────────────────────────────────────────────────────────────────────────
convert_one() {
    local md_file="$1"
    local basename="${md_file##*/}"
    local pdf_name="${basename%.md}.pdf"

    # Determinar salida
    local output_path
    if [[ -n "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        output_path="$OUTPUT_DIR/$pdf_name"
    else
        output_path="${md_file%.md}.pdf"
    fi

    # Idempotencia
    if ! needs_rebuild "$md_file" "$output_path"; then
        return 0
    fi

    info "Procesando: ${BOLD}${basename}${RESET}"

    # Auto-detectar CSS local (solo si el motor lo soporta)
    if [[ "$PDF_ENGINE" == "weasyprint" ]]; then
        detect_local_css "$md_file" || true
    fi

    # Titulo: flag CLI > .env > YAML front matter > sin titulo
    local doc_title="$TITLE"
    if [[ -z "$doc_title" ]]; then
        doc_title="$(extract_yaml_title "$md_file" || true)"
    fi

    local pandoc_opts=()
    pandoc_opts+=(--pdf-engine="$PDF_ENGINE")

    if [[ "$PDF_ENGINE" == "weasyprint" ]]; then
        if [[ -n "$CSS_FILE" ]] && [[ -d "$CSS_DIR" ]] && [[ -f "$CSS_DIR/$CSS_FILE" ]]; then
            pandoc_opts+=(--css="$CSS_DIR/$CSS_FILE")
        else
            warn "CSS no disponible — el PDF se generara sin estilo"
        fi
    fi

    if [[ -n "$doc_title" ]]; then
        pandoc_opts+=(--metadata title="$doc_title")
    fi

    if [[ "$STANDALONE" == "true" ]]; then
        pandoc_opts+=(--standalone)
    fi

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
        error "fallo la conversion de ${BOLD}${basename}${RESET}"
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
echo -e "  Tema:     ${THEME}"
echo -e "  CSS:      ${CSS_DIR}/${CSS_FILE:-auto-detectado}"
echo -e "  Motor:    ${PDF_ENGINE}"
if [[ -n "$OUTPUT_DIR" ]]; then
    echo -e "  Salida:   ${OUTPUT_DIR}"
else
    echo -e "  Salida:   ${CYAN}junto al .md${RESET}"
fi
echo -e "  Archivos: ${total}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${RESET}"
echo

failed=0
for f in "${files[@]}"; do
    convert_one "$f" || ((failed++))
done

echo
converted=$((total - failed))
if [[ "$failed" -eq 0 ]]; then
    success "${BOLD}${converted} archivo(s) convertido(s) correctamente.${RESET}"
else
    error "${failed} de ${total} archivo(s) fallaron."
    exit 1
fi
