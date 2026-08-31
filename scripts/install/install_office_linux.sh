#!/usr/bin/env bash
# Instala LibreOffice, diccionarios españoles y locale de sesión del usuario.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
REQUESTED_LOCALE="es_MX"
LOCALE_VALUE="es_MX.UTF-8"
LANGUAGE_VALUE="es_MX:es"
STAMP="$(date +%Y%m%d_%H%M%S)"
readonly -a PACKAGES=(
  libreoffice libreoffice-gtk3 libreoffice-l10n-es libreoffice-help-es
  hunspell-es hyphen-es mythes-es locales
)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_office_linux.sh [--check|--plan|--apply|--status] [--locale LOCALE]

Instala LibreOffice y soporte español. La configuración de idioma se aplica
solo a la sesión del usuario mediante ~/.config/rafex/locale.conf y ~/.profile;
no modifica /etc/default/locale.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --apply) ACTION=apply ;;
      --status) ACTION=status ;;
      --locale)
        (($# >= 2)) || die '--locale requiere un valor'
        REQUESTED_LOCALE="$2"; shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  case "$REQUESTED_LOCALE" in
    es_MX|es_MX.UTF-8|es_MX.utf8) LOCALE_VALUE=es_MX.UTF-8 ;;
    *) die "locale no soportado por este instalador: $REQUESTED_LOCALE" ;;
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

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

locale_available() {
  locale -a 2>/dev/null | awk '{ print tolower($0) }' | grep -Fxq 'es_mx.utf8'
}

report() {
  local package candidate
  printf '═══ Oficina y español (%s) ═══\n' "$LOCALE_VALUE"
  for package in "${PACKAGES[@]}"; do
    if package_installed "$package"; then
      printf '✓ %-24s instalado\n' "$package"
    else
      candidate="$(package_candidate "$package")"
      printf '✗ %-24s ausente (candidato: %s)\n' "$package" "${candidate:-(none)}"
    fi
  done
  if locale_available; then
    ok "locale $LOCALE_VALUE disponible"
  else
    warn "locale $LOCALE_VALUE no generado"
  fi
  if [[ -r "$HOME/.config/rafex/locale.conf" ]]; then
    ok 'configuración de locale de usuario presente'
  else
    warn 'falta ~/.config/rafex/locale.conf'
  fi
  if command -v libreoffice >/dev/null 2>&1; then
    ok 'libreoffice disponible'
  else
    warn 'libreoffice no está disponible'
  fi
}

validate_candidates() {
  local package candidate missing=0
  for package in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package"
      missing=1
    fi
  done
  ((missing == 0)) || die 'algún paquete de oficina no tiene candidato APT'
}

backup_if_needed() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "${target}.bak.${STAMP}"
  info "respaldo creado: ${target}.bak.${STAMP}"
}

install_text_if_changed() {
  local target="$1" mode="$2" source="$3" temp
  temp="$(mktemp "${target}.tmp.XXXXXX")"
  cat "$source" > "$temp"
  if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
    rm -f -- "$temp"
    return 0
  fi
  backup_if_needed "$target"
  install -D -m "$mode" "$temp" "$target"
  rm -f -- "$temp"
}

write_locale_config() {
  local target="$HOME/.config/rafex/locale.conf" source
  mkdir -p "$(dirname "$target")"
  source="$(mktemp)"
  cat > "$source" <<EOF
# Configuración administrada por scripts-random-utils-whatever.
# Se carga desde ~/.profile en sesiones de login.
export LANG="$LOCALE_VALUE"
export LANGUAGE="$LANGUAGE_VALUE"
export LC_MESSAGES="$LOCALE_VALUE"
EOF
  install_text_if_changed "$target" 0644 "$source"
  rm -f -- "$source"
}

write_profile_block() {
  local target="$HOME/.profile" source temp
  source="$(mktemp)"
  cat > "$source" <<'EOF'

# BEGIN rafex spanish locale
if [ -r "$HOME/.config/rafex/locale.conf" ]; then
  unset LC_ALL
  . "$HOME/.config/rafex/locale.conf"
fi
# END rafex spanish locale
EOF
  temp="$(mktemp "${target}.tmp.XXXXXX")"
  if [[ -f "$target" ]]; then
    awk '
      /# BEGIN rafex spanish locale/ { skip=1; next }
      /# END rafex spanish locale/ { skip=0; next }
      !skip { print }
    ' "$target" > "$temp"
  else
    : > "$temp"
  fi
  cat "$source" >> "$temp"
  install_text_if_changed "$target" 0644 "$temp"
  rm -f -- "$source" "$temp"
}

apply_install() {
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  validate_candidates
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  if ! locale_available; then
    [[ -r /etc/locale.gen ]] && sudo cp -a /etc/locale.gen "/etc/locale.gen.bak.${STAMP}"
    info "generando $LOCALE_VALUE"
    sudo locale-gen "$LOCALE_VALUE"
  fi
  write_locale_config
  write_profile_block
  ok 'LibreOffice y locale de sesión configurados'
  warn 'abre una nueva sesión para aplicar LANG, LANGUAGE y LC_MESSAGES'
}

parse_args "$@"
require_debian
case "$ACTION" in
  check|status) report ;;
  plan)
    report
    info "[plan] locale=$LOCALE_VALUE"
    info "[plan] sudo apt-get update && sudo apt-get install -y ${PACKAGES[*]}"
    info '[plan] generar el locale con sudo locale-gen si falta'
    info '[plan] respaldar y actualizar ~/.config/rafex/locale.conf y ~/.profile'
    ;;
  apply) apply_install; report ;;
  *) die "acción no válida: $ACTION" ;;
esac
