#!/usr/bin/env bash
# v1.1.0 - Prepara un runtime NSS legado aislado para Firefox OS.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
readonly NSS_TOOLS_PACKAGE="podman"
readonly CA_IMAGE="localhost/rafex/firefoxos-ca:nss-3.21"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly CONTAINER_CONTEXT="${REPO_ROOT}/containers/firefoxos-ca"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_firefoxos_ca_tools_linux.sh --check
  install_firefoxos_ca_tools_linux.sh --plan
  install_firefoxos_ca_tools_linux.sh --apply
  install_firefoxos_ca_tools_linux.sh --status

Instala Podman y construye un runtime aislado con NSS 3.21 para preparar y
validar bases NSS de Firefox OS. No modifica el teléfono ni descarga
certificados raíz.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_debian() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecútalo como usuario normal; sudo se usa internamente en --apply'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | \
    grep -Fqx 'install ok installed'
}

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

package_candidate() {
  apt-cache policy "$1" 2>/dev/null |
    awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

runtime_probe() {
  podman run --rm \
    --network=none \
    --cap-drop=all \
    --security-opt=no-new-privileges \
    --read-only \
    --userns=keep-id \
    --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev \
    --entrypoint /bin/sh \
    "$CA_IMAGE" -c \
    'mkdir /tmp/probe && /opt/legacy-nss/bin/certutil -N -d sql:/tmp/probe --empty-password && /opt/legacy-nss/bin/certutil -L -d sql:/tmp/probe >/dev/null'
}

check_candidate() {
  local candidate
  candidate="$(package_candidate "$NSS_TOOLS_PACKAGE")"
  [[ -n "$candidate" && "$candidate" != '(none)' ]] ||
    die "sin candidato APT: $NSS_TOOLS_PACKAGE"
}

show_status() {
  local candidate version
  printf '═══ Herramientas CA Firefox OS ═══\n'
  candidate="$(package_candidate "$NSS_TOOLS_PACKAGE")"
  if package_installed "$NSS_TOOLS_PACKAGE"; then
    version="$(package_version "$NSS_TOOLS_PACKAGE")"
    ok "$NSS_TOOLS_PACKAGE instalado (${version:-versión desconocida})"
  else
    warn "$NSS_TOOLS_PACKAGE ausente (candidato: ${candidate:-(none)})"
  fi
  if command -v podman >/dev/null 2>&1; then
    ok "Podman disponible: $(command -v podman)"
    if podman image exists "$CA_IMAGE" >/dev/null 2>&1; then
      if runtime_probe; then
        ok "runtime NSS legado disponible y ejecutable: $CA_IMAGE"
      else
        warn "runtime NSS legado presente pero certutil no puede ejecutarse: $CA_IMAGE"
      fi
    else
      info "runtime NSS legado ausente; se construirá con --apply"
    fi
  else
    info 'Podman no está disponible; se instalará con --apply'
  fi
  if [[ -f "${CONTAINER_CONTEXT}/Containerfile" ]]; then
    ok 'contexto de compilación del runtime presente en el repositorio'
  else
    warn 'falta containers/firefoxos-ca/Containerfile en el repositorio'
  fi
  info 'el runtime usa NSS 3.21 dentro de un contenedor sin red durante la operación'
  info 'no se modifica el teléfono ni se inicia adb'
}

show_plan() {
  check_candidate
  [[ -f "${CONTAINER_CONTEXT}/Containerfile" ]] ||
    die 'falta el contexto containers/firefoxos-ca/Containerfile'
  printf '═══ Plan herramientas CA Firefox OS ═══\n'
  if package_installed "$NSS_TOOLS_PACKAGE"; then
    info "${NSS_TOOLS_PACKAGE} ya está instalado"
  else
    info "instalar con APT: $NSS_TOOLS_PACKAGE"
  fi
  if command -v podman >/dev/null 2>&1 && podman image exists "$CA_IMAGE" >/dev/null 2>&1; then
    info "conservar el runtime existente: $CA_IMAGE"
  else
    info "construir $CA_IMAGE desde NSS 3.21 y verificar el SHA-256 oficial del archivo fuente"
  fi
  info 'ejecutar certutil solo dentro de Podman rootless, sin red y sin privilegios adicionales'
  info 'no instalar certutil moderno en el host, no compilar B2G y no tocar el teléfono'
}

apply_install() {
  check_candidate
  [[ -f "${CONTAINER_CONTEXT}/Containerfile" ]] ||
    die 'falta el contexto containers/firefoxos-ca/Containerfile'
  if ! package_installed "$NSS_TOOLS_PACKAGE"; then
    sudo -v
    info 'actualizando índices APT'
    sudo apt-get update
    info "instalando $NSS_TOOLS_PACKAGE desde Debian"
    sudo apt-get --no-remove install --no-install-recommends -y "$NSS_TOOLS_PACKAGE"
  else
    info "$NSS_TOOLS_PACKAGE ya está instalado"
  fi
  command -v podman >/dev/null 2>&1 || die 'Podman no quedó disponible después de la instalación'
  if podman image exists "$CA_IMAGE" >/dev/null 2>&1; then
    ok "runtime NSS legado ya disponible: $CA_IMAGE"
  else
    info "construyendo runtime NSS legado: $CA_IMAGE"
    podman build --pull=missing --tag "$CA_IMAGE" "$CONTAINER_CONTEXT"
    ok "runtime NSS legado construido: $CA_IMAGE"
  fi
  runtime_probe || die "el runtime $CA_IMAGE no puede ejecutar certutil NSS 3.21"
  info 'la instalación de certificados requiere ejecutar después el helper Firefox OS'
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      show_status
      check_candidate
      [[ -f "${CONTAINER_CONTEXT}/Containerfile" ]] ||
        die 'falta el contexto containers/firefoxos-ca/Containerfile'
      ;;
    plan) show_plan ;;
    apply) apply_install ;;
    status) show_status ;;
  esac
}

main "$@"
