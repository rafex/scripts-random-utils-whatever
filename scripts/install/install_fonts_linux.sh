#!/usr/bin/env bash
# install_fonts_linux.sh v1.1.0
# Instala fuentes para web, programación, emojis, Nerd Font y cobertura CJK.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PROFILE="web-programming"
NERD_VERSION="v3.4.0"
NERD_ARCHIVE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.tar.xz"
NERD_ARCHIVE_SHA256="ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582"
NERD_FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/rafex/JetBrainsMonoNerdFont"
NERD_TEMP_DIR=""
readonly -a BASE_PACKAGES=(
  fonts-dejavu fonts-liberation2 fonts-noto-core fonts-noto-color-emoji
  fonts-inter fonts-ibm-plex fonts-hack fonts-roboto fonts-firacode
  fonts-jetbrains-mono fonts-cascadia-code fonts-inconsolata
  fonts-crosextra-carlito fonts-crosextra-caladea
)
readonly -a CJK_PACKAGES=(fonts-noto-cjk)
readonly -a NERD_PACKAGES=(curl)
readonly -a NERD_FONT_FILES=(
  JetBrainsMonoNerdFontMono-Regular.ttf
  JetBrainsMonoNerdFontMono-Bold.ttf
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_fonts_linux.sh [--check|--plan|--apply|--status] [--profile PERFIL]

Perfiles:
  web-programming  Fuentes latinas, UI, emoji y programación.
  nerd             Perfil base más JetBrains Mono Nerd Font para EWW/iconos.
  cjk              Perfil base más Noto CJK (ocupa bastante espacio).
  all              Perfil base más Nerd Font y Noto CJK.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --profile)
        (($# >= 2)) || die '--profile requiere un valor'
        PROFILE="$2"; shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  case "$PROFILE" in
    web-programming|nerd|cjk|all) ;;
    *) die "perfil desconocido: $PROFILE" ;;
  esac
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador solo funciona en Linux'
  [[ "$EUID" -ne 0 ]] || die 'ejecuta el instalador como usuario normal'
  [[ -r /etc/os-release ]] || die 'no se puede identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian ]] || die "se requiere Debian; se detectó ${ID:-desconocida}"
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

selected_packages() {
  printf '%s\n' "${BASE_PACKAGES[@]}"
  if [[ "$PROFILE" == nerd || "$PROFILE" == all ]]; then
    printf '%s\n' "${NERD_PACKAGES[@]}"
  fi
  if [[ "$PROFILE" == cjk || "$PROFILE" == all ]]; then
    printf '%s\n' "${CJK_PACKAGES[@]}"
  fi
}

profile_has_nerd_font() {
  [[ "$PROFILE" == nerd || "$PROFILE" == all ]]
}

nerd_font_installed() {
  local file
  for file in "${NERD_FONT_FILES[@]}"; do
    [[ -s "$NERD_FONT_DIR/$file" ]] || return 1
  done
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

report() {
  local package candidate
  printf '═══ Fuentes (%s) ═══\n' "$PROFILE"
  while IFS= read -r package; do
    if package_installed "$package"; then
      printf '✓ %-28s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-28s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done < <(selected_packages)
  if profile_has_nerd_font; then
    if nerd_font_installed; then
      ok "JetBrains Mono Nerd Font ${NERD_VERSION} instalada para EWW/iconos"
    else
      warn "JetBrains Mono Nerd Font ${NERD_VERSION} ausente: ejecuta --apply --profile $PROFILE"
    fi
  fi
  if command -v fc-match >/dev/null 2>&1; then
    printf 'sans='; fc-match sans -f '%{family}\n' 2>/dev/null | head -n 1
    printf 'monospace='; fc-match monospace -f '%{family}\n' 2>/dev/null | head -n 1
    if profile_has_nerd_font && nerd_font_installed; then
      printf 'eww-icons='; fc-match 'JetBrainsMono Nerd Font Mono' -f '%{family}\n' 2>/dev/null | head -n 1
    fi
  else
    warn 'fc-match no está disponible'
  fi
}

cleanup_nerd_temp() {
  if [[ -n "$NERD_TEMP_DIR" && -d "$NERD_TEMP_DIR" ]]; then
    rm -rf -- "$NERD_TEMP_DIR"
  fi
}

install_nerd_font() {
  local archive file target temporary
  nerd_font_installed && { ok "JetBrains Mono Nerd Font ${NERD_VERSION} ya está instalada"; return 0; }
  command -v curl >/dev/null 2>&1 || die 'falta curl para descargar la Nerd Font'
  command -v tar >/dev/null 2>&1 || die 'falta tar para instalar la Nerd Font'
  command -v sha256sum >/dev/null 2>&1 || die 'falta sha256sum para verificar la Nerd Font'
  NERD_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafex-nerd-font.XXXXXX")"
  trap cleanup_nerd_temp EXIT
  archive="$NERD_TEMP_DIR/JetBrainsMono.tar.xz"
  info "descargando JetBrains Mono Nerd Font ${NERD_VERSION} desde el repositorio oficial"
  curl -fL --retry 3 --connect-timeout 15 --output "$archive" "$NERD_ARCHIVE_URL"
  printf '%s  %s\n' "$NERD_ARCHIVE_SHA256" "$archive" | sha256sum -c - >/dev/null ||
    die 'la verificación SHA-256 de la Nerd Font falló'
  mkdir -p -- "$NERD_FONT_DIR"
  for file in "${NERD_FONT_FILES[@]}"; do
    target="$NERD_FONT_DIR/$file"
    tar -xJf "$archive" -C "$NERD_TEMP_DIR" -- "$file" || die "falta el archivo esperado en la Nerd Font: $file"
    temporary="$(mktemp "${target}.tmp.XXXXXX")"
    cp -- "$NERD_TEMP_DIR/$file" "$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$target"
  done
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$NERD_FONT_DIR" >/dev/null 2>&1 || true
  nerd_font_installed || die 'la instalación de la Nerd Font no quedó completa'
  ok "JetBrains Mono Nerd Font ${NERD_VERSION} instalada en $NERD_FONT_DIR"
}

validate_candidates() {
  local package candidate missing=0
  while IFS= read -r package; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done < <(selected_packages)
  ((missing == 0)) || die 'alguna fuente no tiene candidato APT'
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  local -a packages=()
  mapfile -t packages < <(selected_packages)
  info "instalando: ${packages[*]}"
  sudo apt-get install -y "${packages[@]}"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
  ok 'fuentes instaladas y caché actualizada'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check|status) report ;;
  plan)
    report
    info "[plan] perfil=$PROFILE"
    info '[plan] sudo apt-get update y apt-get install de las fuentes seleccionadas'
    if profile_has_nerd_font; then
      info "[plan] descargar, verificar y extraer JetBrains Mono Nerd Font ${NERD_VERSION} en $NERD_FONT_DIR"
    fi
    ;;
  apply)
    apply_install
    if profile_has_nerd_font; then install_nerd_font; fi
    report
    ;;
  *) die "acción no válida: $ACTION" ;;
esac
