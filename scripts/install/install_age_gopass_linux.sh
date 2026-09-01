#!/usr/bin/env bash
# v1.0.0 - Instala age y gopass con el backend de age opcional.
set -Eeuo pipefail
umask 077

ACTION="check"
readonly GOPASS_REPOSITORY="https://packages.gopass.pw/repos/gopass"
readonly GOPASS_KEY_URL="${GOPASS_REPOSITORY}/gopass-archive-keyring.gpg"
readonly GOPASS_KEY_FINGERPRINT="8086459860A915BA78CAAB6A686E9DE6E1AEFFBE"
readonly GOPASS_KEYRING="/usr/share/keyrings/gopass-archive-keyring.gpg"
readonly GOPASS_SOURCES="/etc/apt/sources.list.d/gopass.sources"
readonly GOPASS_PREFERENCES="/etc/apt/preferences.d/gopass.pref"
readonly GOPASS_STORE="${PASSWORD_STORE_DIR:-${HOME}/.password-store}"
REPOSITORY_TEMP_DIR=""

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

cleanup_repository_temp() {
  if [[ -n "$REPOSITORY_TEMP_DIR" && -d "$REPOSITORY_TEMP_DIR" ]]; then
    rm -rf -- "$REPOSITORY_TEMP_DIR"
  fi
  REPOSITORY_TEMP_DIR=""
}

trap cleanup_repository_temp EXIT

usage() {
  cat <<'EOF'
Uso:
  install_age_gopass_linux.sh --check
  install_age_gopass_linux.sh --plan
  install_age_gopass_linux.sh --apply
  install_age_gopass_linux.sh --status
  install_age_gopass_linux.sh --init-gopass-age

Instala age y la versión oficial de gopass desde el repositorio del proyecto.
--apply no inicializa el almacén; --init-gopass-age crea uno nuevo de forma
interactiva usando el backend experimental de age.
EOF
}

require_linux_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null \
    | awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

show_package() {
  local package_name="$1" candidate
  candidate="$(package_candidate "$package_name")"
  if package_installed "$package_name"; then
    ok "$package_name instalado"
  else
    warn "$package_name no está instalado"
  fi
  if [[ -n "$candidate" && "$candidate" != '(none)' ]]; then
    info "$package_name candidato APT: $candidate"
  else
    warn "$package_name no tiene candidato APT en las fuentes actuales"
  fi
}

show_status() {
  printf '═══ age y gopass ═══\n'
  show_package age
  show_package gopass
  show_package gopass-archive-keyring
  if [[ -f "$GOPASS_SOURCES" ]]; then
    ok "fuente oficial configurada: $GOPASS_SOURCES"
  else
    warn 'fuente oficial de gopass aún no está configurada'
  fi
  if [[ -f "$GOPASS_KEYRING" ]]; then
    ok "keyring oficial presente: $GOPASS_KEYRING"
  else
    warn 'keyring oficial de gopass aún no está instalado'
  fi
  if command -v age >/dev/null 2>&1; then
    info "age: $(age --version 2>/dev/null || true)"
  fi
  if command -v gopass >/dev/null 2>&1; then
    gopass version 2>/dev/null | sed -n '1p' || true
  fi
  printf 'almacén gopass=%s\n' "$GOPASS_STORE"
  if [[ -d "$GOPASS_STORE" ]]; then
    ok 'directorio del almacén existe; no se muestran sus entradas'
  else
    info 'almacén aún no inicializado'
  fi
  info 'la inicialización age se realiza explícitamente con --init-gopass-age'
}

source_content() {
  printf '%s\n' \
    'Types: deb' \
    "URIs: ${GOPASS_REPOSITORY}" \
    'Suites: stable' \
    'Architectures: all amd64 arm64 armhf' \
    'Components: main' \
    "Signed-By: ${GOPASS_KEYRING}"
}

preferences_content() {
  printf '%s\n' \
    '# No preferir paquetes generales del repositorio gopass.' \
    'Package: *' \
    'Pin: origin packages.gopass.pw' \
    'Pin-Priority: 1' \
    '' \
    '# Permitir únicamente los paquetes administrados por este instalador.' \
    'Package: gopass gopass-archive-keyring' \
    'Pin: origin packages.gopass.pw' \
    'Pin-Priority: 900'
}

backup_if_changed() {
  local source_file="$1" target_file="$2" mode="$3" backup_dir="$4" tmp_basename
  if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
    return 1
  fi
  if [[ -e "$target_file" ]]; then
    tmp_basename="$(basename -- "$target_file").bak.$(date +%Y%m%d_%H%M%S)"
    sudo install -d -m 0750 -- "$backup_dir"
    sudo cp -a -- "$target_file" "$backup_dir/$tmp_basename"
    info "respaldo creado: $backup_dir/$tmp_basename"
  fi
  sudo install -D -m "$mode" -- "$source_file" "$target_file"
  return 0
}

verify_key() {
  local key_file="$1" fingerprints
  command -v gpg >/dev/null 2>&1 || die 'gpg es necesario para validar el keyring oficial'
  fingerprints="$(gpg --show-keys --with-colons "$key_file" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print toupper($10) }')"
  [[ "$fingerprints" == *"$GOPASS_KEY_FINGERPRINT"* ]] \
    || die 'la huella del keyring gopass no coincide; se cancela la instalación'
}

configure_repository() {
  local key_file source_file preferences_file backup_dir changed=0
  REPOSITORY_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gopass-repository.XXXXXX")"
  key_file="$REPOSITORY_TEMP_DIR/gopass-archive-keyring.gpg"
  source_file="$REPOSITORY_TEMP_DIR/gopass.sources"
  preferences_file="$REPOSITORY_TEMP_DIR/gopass.pref"
  backup_dir="/var/backups/rafex-gopass"

  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    -o "$key_file" "$GOPASS_KEY_URL"
  verify_key "$key_file"
  source_content > "$source_file"
  preferences_content > "$preferences_file"

  if backup_if_changed "$key_file" "$GOPASS_KEYRING" 0644 "$backup_dir"; then changed=1; fi
  if backup_if_changed "$source_file" "$GOPASS_SOURCES" 0644 "$backup_dir"; then changed=1; fi
  if backup_if_changed "$preferences_file" "$GOPASS_PREFERENCES" 0644 "$backup_dir"; then changed=1; fi
  if ((changed == 0)); then
    ok 'fuente, preferencias y keyring gopass ya están actualizados'
  fi
  cleanup_repository_temp
}

show_plan() {
  printf '═══ Plan age y gopass ═══\n'
  if package_installed age; then info 'age ya está instalado'; else info 'instalar age desde Debian'; fi
  if package_installed gopass; then info 'gopass ya está instalado'; else info 'configurar el repositorio oficial y pin de gopass'; fi
  info 'instalar gopass y gopass-archive-keyring con APT firmado'
  info 'no inicializar el almacén ni crear identidades en modo plan'
  info 'no se escribirá nada en modo plan'
}

apply_installation() {
  command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  command -v curl >/dev/null 2>&1 || die 'falta curl para descargar el keyring oficial'
  sudo -v
  configure_repository
  info 'actualizando índices APT del repositorio oficial de gopass'
  sudo apt-get update
  [[ -n "$(package_candidate age)" && "$(package_candidate age)" != '(none)' ]] \
    || die 'age no tiene candidato APT'
  [[ -n "$(package_candidate gopass)" && "$(package_candidate gopass)" != '(none)' ]] \
    || die 'gopass oficial no tiene candidato APT después de configurar su fuente'
  info 'instalando age, gopass y gopass-archive-keyring'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    age gopass gopass-archive-keyring
  ok 'age y gopass instalados; el almacén aún no fue inicializado'
}

init_gopass_age() {
  command -v gopass >/dev/null 2>&1 || die 'falta gopass; ejecuta --apply primero'
  [[ -t 0 && -t 1 ]] || die '--init-gopass-age requiere una terminal interactiva'
  local first_entry=""
  if [[ -d "$GOPASS_STORE" ]]; then
    first_entry="$(find "$GOPASS_STORE" -mindepth 1 -print -quit 2>/dev/null || true)"
  fi
  [[ -z "$first_entry" ]] || die "el almacén $GOPASS_STORE no está vacío; no se sobrescribe"
  info 'se iniciará un almacén nuevo con el backend experimental age'
  info 'gopass solicitará la frase de protección de la identidad; no se registrará'
  gopass setup --crypto age
  ok 'almacén gopass age inicializado'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --init-gopass-age|--init) ACTION="init" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux_debian
  case "$ACTION" in
    check)
      printf '═══ Check age y gopass ═══\n'
      show_package age
      show_package gopass
      show_status
      ;;
    plan) show_plan ;;
    apply) apply_installation ;;
    status) show_status ;;
    init) init_gopass_age ;;
  esac
}

main "$@"
