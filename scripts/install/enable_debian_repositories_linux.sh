#!/usr/bin/env bash
# shellcheck shell=bash
#
# Habilita los componentes oficiales de Debian en fuentes .list y .sources.
# No añade suites inestables, repositorios de terceros ni acepta contraseñas.
set -Eeuo pipefail
umask 077

ACTION="check"
OS_TYPE="$(uname -s)"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
CHANGED=0
SOURCE_FILES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  enable_debian_repositories_linux.sh --check
  enable_debian_repositories_linux.sh --plan
  enable_debian_repositories_linux.sh --apply

Componentes oficiales habilitados:
  main contrib non-free non-free-firmware

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Modificar fuentes y ejecutar apt-get update
  -h, --help             Mostrar esta ayuda

La contraseña de sudo, cuando sea necesaria, se solicita únicamente mediante
`sudo -v`. No se aceptan contraseñas como argumentos ni variables.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$OS_TYPE" == "Linux" ]] || die "este script solo funciona en Debian Linux"
  command -v apt-get >/dev/null 2>&1 || die "apt-get no está disponible"
  if [[ "$ACTION" == "apply" ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo no está instalado; ejecuta configure_sudo_linux.sh primero"
  fi
}

discover_source_files() {
  SOURCE_FILES=()
  [[ -f /etc/apt/sources.list ]] && SOURCE_FILES+=(/etc/apt/sources.list)
  if [[ -d /etc/apt/sources.list.d ]]; then
    while IFS= read -r -d '' file; do
      SOURCE_FILES+=("$file")
    done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \
      \( -name '*.list' -o -name '*.sources' \) -print0 | sort -z)
  fi
}

is_active_list_file() {
  grep -Eq '^[[:space:]]*deb(-src)?([[:space:]]|$)' "$1"
}

is_debian_list_file() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*deb(-src)?([[:space:]]|$)/ && /debian\.(org|net)/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

is_active_sources_file() {
  ! grep -Eiq '^[[:space:]]*Enabled:[[:space:]]*no([[:space:]]|$)' "$1"
}

is_debian_sources_file() {
  awk '
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Enabled:[[:space:]]*no([[:space:]]|$)/ { disabled = 1 }
    /^[[:space:]]*URIs?:.*debian\.(org|net)/ { found = 1 }
    END { exit(found && !disabled ? 0 : 1) }
  ' "$1"
}

missing_components_list() {
  local file="$1"
  awk '
    function has_component(line, component) {
      return line ~ "(^|[[:space:]])" component "([[:space:]]|$)"
    }
    /^[[:space:]]*deb(-src)?([[:space:]]|$)/ {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      seen = 1
      if (!has_component(line, "contrib")) missing_contrib = 1
      if (!has_component(line, "non-free")) missing_nonfree = 1
      if (!has_component(line, "non-free-firmware")) missing_firmware = 1
    }
    END {
      if (seen && missing_contrib) printf "contrib "
      if (seen && missing_nonfree) printf "non-free "
      if (seen && missing_firmware) printf "non-free-firmware"
    }
  ' "$file" | sed 's/[[:space:]]*$//'
}

missing_components_sources() {
  local file="$1"
  awk '
    function has_component(line, component) {
      return line ~ "(^|[[:space:]])" component "([[:space:]]|$)"
    }
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Components:[[:space:]]*/ {
      values = $0
      sub(/^[^:]*:[[:space:]]*/, "", values)
      seen = 1
      if (!has_component(values, "contrib")) missing_contrib = 1
      if (!has_component(values, "non-free")) missing_nonfree = 1
      if (!has_component(values, "non-free-firmware")) missing_firmware = 1
    }
    END {
      if (!seen) {
        printf "Components"
      } else {
        if (missing_contrib) printf "contrib "
        if (missing_nonfree) printf "non-free "
        if (missing_firmware) printf "non-free-firmware"
      }
    }
  ' "$file" | sed 's/[[:space:]]*$//'
}

file_missing_components() {
  case "$1" in
    *.sources) missing_components_sources "$1" ;;
    *) missing_components_list "$1" ;;
  esac
}

describe_sources() {
  local file
  local missing
  local active=0
  echo
  echo -e "${BOLD}${CYAN}═══ Componentes APT de Debian ═══${RESET}"
  if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
    warn "no se encontraron archivos de fuentes APT"
    return 0
  fi
  for file in "${SOURCE_FILES[@]}"; do
    if [[ "$file" == *.sources ]]; then
      is_debian_sources_file "$file" || continue
    else
      is_debian_list_file "$file" || continue
    fi
    active=1
    missing="$(file_missing_components "$file")"
    if [[ -n "$missing" ]]; then
      warn "$file: faltan $missing"
    else
      ok "$file: main contrib non-free non-free-firmware"
    fi
  done
  [[ "$active" -eq 1 ]] || warn "no se encontraron entradas Debian activas"
}

transform_list_file() {
  awk '
    function has_component(line, component) {
      return line ~ "(^|[[:space:]])" component "([[:space:]]|$)"
    }
    /^[[:space:]]*#/ || $0 !~ /^[[:space:]]*deb(-src)?([[:space:]]|$)/ {
      print
      next
    }
    {
      line = $0
      comment = ""
      if (match(line, /[[:space:]]+#/)) {
        comment = substr(line, RSTART)
        line = substr(line, 1, RSTART - 1)
      }
      for (i = 1; i <= 3; i++) {
        component = (i == 1 ? "contrib" : i == 2 ? "non-free" : "non-free-firmware")
        if (!has_component(line, component)) {
          line = line " " component
        }
      }
      print line comment
    }
  ' "$1"
}

transform_sources_file() {
  awk '
    function has_component(line, component) {
      return line ~ "(^|[[:space:]])" component "([[:space:]]|$)"
    }
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Components:[[:space:]]*/ {
      colon = index($0, ":")
      prefix = substr($0, 1, colon)
      values = substr($0, colon + 1)
      for (i = 1; i <= 3; i++) {
        component = (i == 1 ? "contrib" : i == 2 ? "non-free" : "non-free-firmware")
        if (!has_component(values, component)) {
          values = values " " component
        }
      }
      sub(/^[[:space:]]+/, "", values)
      print prefix " " values
      next
    }
    { print }
  ' "$1"
}

apply_source_file() {
  local file="$1"
  local missing
  local temporary
  missing="$(file_missing_components "$file")"
  [[ -n "$missing" ]] || return 0

  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] $file: agregar $missing"
    CHANGED=1
    return 0
  fi

  temporary="$(mktemp)"
  if [[ "$file" == *.sources ]]; then
    transform_sources_file "$file" > "$temporary"
  else
    transform_list_file "$file" > "$temporary"
  fi
  sudo cp -a "$file" "${file}.bak.${BACKUP_STAMP}"
  sudo install -m 0644 "$temporary" "$file"
  rm -f "$temporary"
  info "actualizado $file; respaldo: ${file}.bak.${BACKUP_STAMP}"
  CHANGED=1
}

create_fallback_sources() {
  local destination='/etc/apt/sources.list.d/90-debian-all-components.list'
  local codename
  local temporary
  local content

  codename="$({ . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}"; })"
  [[ -n "$codename" ]] || die "no se pudo detectar VERSION_CODENAME"
  content="deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware"

  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] crear $destination para Debian $codename"
    CHANGED=1
    return 0
  fi
  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  sudo install -D -m 0644 "$temporary" "$destination"
  rm -f "$temporary"
  info "fuentes Debian creadas: $destination"
  CHANGED=1
}

main() {
  parse_args "$@"
  require_linux
  discover_source_files
  describe_sources

  if [[ "$ACTION" == "check" ]]; then
    exit 0
  fi

  if [[ "$ACTION" == "apply" ]]; then
    sudo -v
  fi

  local active=0
  local file
  for file in "${SOURCE_FILES[@]}"; do
    if [[ "$file" == *.sources ]]; then
      is_debian_sources_file "$file" || continue
    else
      is_debian_list_file "$file" || continue
    fi
    active=1
    apply_source_file "$file"
  done
  if [[ "$active" -eq 0 ]]; then
    create_fallback_sources
  fi

  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] apt-get update si se detectan cambios"
  elif [[ "$CHANGED" -eq 1 ]]; then
    sudo apt-get update
    ok "componentes Debian habilitados y listas APT actualizadas"
  else
    ok "los componentes Debian ya estaban habilitados; no se ejecutó apt-get update"
  fi
}

main "$@"
