#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# clean_apple_meta_macos.sh
# Limpia metadatos Apple (._*, .DS_Store, xattrs) en volúmenes montados.
# Solo macOS.
# ─────────────────────────────────────────────────────────────────────────────

CLEAN_PATH="${CLEAN_PATH:-}"
ARG_PATH=""
SKIP_XATTR=false
DRY_RUN=false

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
# Uso
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}Uso:${RESET}"
  echo "  $0 [opciones]"
  echo
  echo -e "${BOLD}Opciones:${RESET}"
  echo -e "  ${CYAN}-p, --path${RESET}    <ruta>   Ruta del volumen o directorio a limpiar"
  echo -e "  ${CYAN}    --no-xattr${RESET}          Omitir limpieza de atributos extendidos con xattr"
  echo -e "  ${CYAN}    --dry-run${RESET}           Mostrar qué se eliminaría sin borrar nada"
  echo -e "  ${CYAN}-h, --help${RESET}              Mostrar esta ayuda"
  echo
  echo -e "${BOLD}Variables de entorno:${RESET}"
  echo -e "  ${CYAN}CLEAN_PATH${RESET}   Ruta del volumen o directorio a limpiar"
  echo
  echo -e "${BOLD}Ejemplo:${RESET}"
  echo "  $0 --path /Volumes/rafex/repository"
  echo "  $0 --path /Volumes/nas/datos --no-xattr"
  echo "  $0 --path /Volumes/nas/datos --dry-run"
  echo "  CLEAN_PATH=/Volumes/nas/datos $0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Validar macOS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  error "Este script solo está soportado en macOS."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--path)
      ARG_PATH="$2"
      shift 2
      ;;
    --no-xattr)
      SKIP_XATTR=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "argumento desconocido: $1"
      echo
      usage
      exit 1
      ;;
  esac
done

# Los args explícitos tienen prioridad sobre variables de entorno
[[ -n "$ARG_PATH" ]] && CLEAN_PATH="$ARG_PATH"

# ─────────────────────────────────────────────────────────────────────────────
# Validar ruta
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$CLEAN_PATH" ]]; then
  CLEAN_PATH="$(pwd)"
  info "No se indicó ruta. Usando directorio actual: ${BOLD}${CLEAN_PATH}${RESET}"
fi

if [[ ! -d "$CLEAN_PATH" ]]; then
  error "La ruta no existe o no es un directorio: ${BOLD}${CLEAN_PATH}${RESET}"
  exit 1
fi

# Resolver ruta absoluta
CLEAN_PATH="$(cd "$CLEAN_PATH" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Modo dry-run: mostrar sin borrar
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  warn "Modo dry-run activado. No se eliminará nada."
  echo

  info "Atributos extendidos encontrados:"
  if ! xattr -rl "$CLEAN_PATH" 2>/dev/null | grep -q .; then
    echo "    (ninguno)"
  else
    xattr -rl "$CLEAN_PATH" 2>/dev/null | head -40
  fi
  echo

  info "Archivos ._* encontrados:"
  local_count="$(find "$CLEAN_PATH" -name '._*' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$local_count" -eq 0 ]]; then
    echo "    (ninguno)"
  else
    find "$CLEAN_PATH" -name '._*' -type f 2>/dev/null
  fi
  echo

  info "Archivos .DS_Store encontrados:"
  ds_count="$(find "$CLEAN_PATH" -name '.DS_Store' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$ds_count" -eq 0 ]]; then
    echo "    (ninguno)"
  else
    find "$CLEAN_PATH" -name '.DS_Store' -type f 2>/dev/null
  fi
  echo
  success "Fin del análisis (dry-run). Ejecuta sin --dry-run para limpiar."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Limpieza real
# ─────────────────────────────────────────────────────────────────────────────
echo
info "Ruta a limpiar: ${BOLD}${CLEAN_PATH}${RESET}"
echo

# 1. Limpiar atributos extendidos
if [[ "$SKIP_XATTR" == "false" ]]; then
  info "Limpiando atributos extendidos con xattr -rc ..."
  if xattr -rc "$CLEAN_PATH" 2>/dev/null; then
    success "Atributos extendidos eliminados."
  else
    warn "xattr -rc finalizó con advertencias (puede ser normal en algunos volúmenes)."
  fi
else
  warn "Limpieza de atributos extendidos omitida (--no-xattr)."
fi
echo

# 2. Eliminar archivos ._*
info "Buscando archivos ._* ..."
apple_double_count="$(find "$CLEAN_PATH" -name '._*' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$apple_double_count" -gt 0 ]]; then
  info "Eliminando ${BOLD}${apple_double_count}${RESET} archivo(s) ._* ..."
  find "$CLEAN_PATH" -name '._*' -type f -delete 2>/dev/null
  success "Archivos ._* eliminados."
else
  success "No se encontraron archivos ._*."
fi
echo

# 3. Eliminar archivos .DS_Store
info "Buscando archivos .DS_Store ..."
ds_count="$(find "$CLEAN_PATH" -name '.DS_Store' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$ds_count" -gt 0 ]]; then
  info "Eliminando ${BOLD}${ds_count}${RESET} archivo(s) .DS_Store ..."
  find "$CLEAN_PATH" -name '.DS_Store' -type f -delete 2>/dev/null
  success "Archivos .DS_Store eliminados."
else
  success "No se encontraron archivos .DS_Store."
fi
echo

success "Limpieza completada en: ${BOLD}${CLEAN_PATH}${RESET}"
