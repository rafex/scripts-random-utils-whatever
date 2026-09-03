#!/usr/bin/env bash
# v1.2.0 - Prepara runtimes NSS históricos y el runtime B2G exacto del Flame.
set -Eeuo pipefail

umask 077
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
SOURCE_BUNDLE="${XDG_DATA_HOME:-${HOME}/.local/share}/rafex/firefoxos-ca/b2g46-source"

readonly PODMAN_PACKAGE="podman"
readonly BASELINE_IMAGE="localhost/rafex/firefoxos-ca:nss-3.21"
readonly EXACT_IMAGE="localhost/rafex/firefoxos-ca:b2g46-flame"
CONTEXT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../containers/firefoxos-ca" && pwd)"
readonly CONTEXT_DIR
readonly OBSERVED_RUNTIME_MANIFEST="${XDG_DATA_HOME:-${HOME}/.local/share}/rafex/firefoxos-ca/runtime/flame-runtime.env"
readonly NSS_ARCHIVE_SHA256="23ea51e472ee2c1211d2ee89e1c5295990046b6a7a54b89afba1481a94713527"
readonly EXPECTED_B2G_VERSION="46.0a1"
readonly EXPECTED_B2G_BUILD_ID="20151221215202"
readonly EXPECTED_B2G_SOURCE_REPOSITORY="4a4a0bcf45995fdc29caefba2766932dfc25be7d"
readonly EXPECTED_NSS_VERSION="3.22.3"
readonly EXPECTED_NSPR_VERSION="4.12"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_firefoxos_ca_tools_linux.sh --check [--source-bundle DIR]
  install_firefoxos_ca_tools_linux.sh --plan [--source-bundle DIR]
  install_firefoxos_ca_tools_linux.sh --apply [--source-bundle DIR]
  install_firefoxos_ca_tools_linux.sh --status [--source-bundle DIR]

Instala Podman y prepara un baseline NSS histórico. El runtime autorizado
para editar el Flame solo se construye si se proporciona un bundle local con
el árbol NSS/B2G y los parches exactos del build observado. No modifica el
teléfono ni descarga fuentes B2G automáticamente.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --source-bundle)
        (($# >= 2)) || die '--source-bundle requiere un directorio'
        SOURCE_BUNDLE="$2"
        shift
        ;;
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
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] ||
    die 'este instalador requiere Debian o un derivado compatible'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  command -v apt-get >/dev/null 2>&1 || die 'falta apt-get'
  command -v dpkg-query >/dev/null 2>&1 || die 'falta dpkg-query'
  if [[ "$ACTION" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fqx 'install ok installed'
}

package_candidate() {
  apt-cache policy "$1" 2>/dev/null | awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

check_candidate() {
  local candidate
  candidate="$(package_candidate "$PODMAN_PACKAGE")"
  [[ -n "$candidate" && "$candidate" != '(none)' ]] || die "sin candidato APT: $PODMAN_PACKAGE"
}

manifest_value() {
  local manifest="$1" key="$2"
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$manifest"
}

validate_source_bundle() {
  local manifest archive patches_manifest source_manifest patches_hash source_hash expected archive_hash
  local manifest_line patch_paths actual_patch_paths b2g_paths actual_b2g_paths
  [[ -d "$SOURCE_BUNDLE" && ! -L "$SOURCE_BUNDLE" ]] ||
    die "NO-GO: no existe el bundle local B2G exacto: $SOURCE_BUNDLE"
  manifest="${SOURCE_BUNDLE}/source-manifest.env"
  archive="${SOURCE_BUNDLE}/nss-3.22.3-with-nspr-4.12.tar.gz"
  patches_manifest="${SOURCE_BUNDLE}/patches.sha256"
  source_manifest="${SOURCE_BUNDLE}/b2g-source.sha256"
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'NO-GO: falta source-manifest.env verificable'
  [[ -f "$archive" && ! -L "$archive" ]] || die 'NO-GO: falta el archivo NSS/NSPR fijado del bundle'
  [[ -f "$patches_manifest" && ! -L "$patches_manifest" ]] || die 'NO-GO: falta patches.sha256'
  [[ -f "$source_manifest" && ! -L "$source_manifest" ]] || die 'NO-GO: falta b2g-source.sha256'
  [[ -d "${SOURCE_BUNDLE}/b2g" && ! -L "${SOURCE_BUNDLE}/b2g" ]] || die 'NO-GO: falta el árbol B2G del bundle'
  find "$SOURCE_BUNDLE" -type l -print -quit 2>/dev/null | grep -q . && die 'NO-GO: el bundle no puede contener enlaces simbólicos'

  [[ "$(manifest_value "$manifest" B2G_VERSION)" == "$EXPECTED_B2G_VERSION" ]] || die 'NO-GO: B2G_VERSION no coincide'
  [[ "$(manifest_value "$manifest" B2G_BUILD_ID)" == "$EXPECTED_B2G_BUILD_ID" ]] || die 'NO-GO: B2G_BUILD_ID no coincide'
  [[ "$(manifest_value "$manifest" B2G_SOURCE_REPOSITORY)" == "$EXPECTED_B2G_SOURCE_REPOSITORY" ]] || die 'NO-GO: SourceRepository no coincide'
  [[ "$(manifest_value "$manifest" NSS_VERSION)" == "$EXPECTED_NSS_VERSION" ]] || die 'NO-GO: NSS_VERSION no coincide'
  [[ "$(manifest_value "$manifest" NSPR_VERSION)" == "$EXPECTED_NSPR_VERSION" ]] || die 'NO-GO: NSPR_VERSION no coincide'
  [[ "$(manifest_value "$manifest" B2G_SOURCE_STATUS)" == matched ]] || die 'NO-GO: el estado de fuentes B2G no es matched'
  [[ "$(manifest_value "$manifest" B2G_PATCH_STATUS)" == matched ]] || die 'NO-GO: el estado de parches B2G no es matched'
  [[ "$(manifest_value "$manifest" B2G_LIBNSS3_SHA256)" =~ ^[[:xdigit:]]{64}$ ]] || die 'NO-GO: falta el hash de libnss3.so del Flame'
  [[ -f "$OBSERVED_RUNTIME_MANIFEST" ]] || die 'NO-GO: identifica primero el runtime del Flame con firefoxos-ca --identify-runtime'
  [[ "$(manifest_value "$manifest" B2G_VERSION)" == "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_VERSION)" ]] || die 'NO-GO: la versión B2G del bundle no coincide con el teléfono'
  [[ "$(manifest_value "$manifest" B2G_BUILD_ID)" == "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_BUILD_ID)" ]] || die 'NO-GO: el Build ID del bundle no coincide con el teléfono'
  [[ "$(manifest_value "$manifest" B2G_SOURCE_REPOSITORY)" == "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_SOURCE_REPOSITORY)" ]] || die 'NO-GO: SourceRepository del bundle no coincide con el teléfono'
  [[ "$(manifest_value "$manifest" B2G_LIBNSS3_SHA256)" == "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_LIBNSS3_SHA256)" ]] || die 'NO-GO: el hash de libnss3.so del bundle no coincide con el teléfono observado'

  archive_hash="$(sha256sum -- "$archive" | awk '{print $1}')"
  [[ "$archive_hash" == "$NSS_ARCHIVE_SHA256" ]] || die 'NO-GO: SHA-256 del archivo NSS/NSPR no coincide'
  while IFS= read -r manifest_line; do
    [[ "$manifest_line" =~ ^[[:xdigit:]]{64}[[:space:]][[:space:]]patches/[A-Za-z0-9._/-]+\.patch$ ]] ||
      die 'NO-GO: patches.sha256 contiene una ruta no permitida'
    [[ "$manifest_line" != *'..'* && "$manifest_line" != *'//'* ]] ||
      die 'NO-GO: patches.sha256 contiene una ruta insegura'
  done < "$patches_manifest"
  while IFS= read -r manifest_line; do
    [[ "$manifest_line" =~ ^[[:xdigit:]]{64}[[:space:]][[:space:]]b2g/[A-Za-z0-9._/-]+$ ]] ||
      die 'NO-GO: b2g-source.sha256 contiene una ruta no permitida'
    [[ "$manifest_line" != *'..'* && "$manifest_line" != *'//'* ]] ||
      die 'NO-GO: b2g-source.sha256 contiene una ruta insegura'
  done < "$source_manifest"
  (cd -- "$SOURCE_BUNDLE" && sha256sum --check --strict -- "$patches_manifest") ||
    die 'NO-GO: el manifiesto de parches no coincide con el bundle'
  (cd -- "$SOURCE_BUNDLE" && sha256sum --check --strict -- "$source_manifest") ||
    die 'NO-GO: el manifiesto del árbol B2G no coincide con el bundle'
  patches_hash="$(sha256sum -- "$patches_manifest" | awk '{print $1}')"
  source_hash="$(sha256sum -- "$source_manifest" | awk '{print $1}')"
  expected="$(manifest_value "$manifest" B2G_PATCHES_SHA256)"
  [[ "$expected" == "$patches_hash" ]] || die 'NO-GO: B2G_PATCHES_SHA256 no coincide'
  expected="$(manifest_value "$manifest" B2G_SOURCE_TREE_SHA256)"
  [[ "$expected" == "$source_hash" ]] || die 'NO-GO: B2G_SOURCE_TREE_SHA256 no coincide'
  patch_paths="$(sed -n 's/^[[:xdigit:]]\{64\}[[:space:]][[:space:]]//p' "$patches_manifest" | sort)"
  actual_patch_paths="$(find "$SOURCE_BUNDLE/patches" -maxdepth 1 -type f -name '*.patch' -printf 'patches/%f\n' 2>/dev/null | sort)"
  [[ -n "$patch_paths" && "$patch_paths" == "$actual_patch_paths" ]] ||
    die 'NO-GO: el bundle no contiene un manifiesto completo de parches B2G'
  b2g_paths="$(sed -n 's/^[[:xdigit:]]\{64\}[[:space:]][[:space:]]//p' "$source_manifest" | sort)"
  actual_b2g_paths="$(find "$SOURCE_BUNDLE/b2g" -type f -printf 'b2g/%P\n' 2>/dev/null | sort)"
  [[ -n "$b2g_paths" && "$b2g_paths" == "$actual_b2g_paths" ]] ||
    die 'NO-GO: el bundle no contiene un manifiesto completo del árbol B2G'

  ok 'bundle NSS/B2G local validado para el build Flame observado'
}

runtime_probe() {
  podman run --rm --network=none --cap-drop=all --security-opt=no-new-privileges \
    --read-only --userns=keep-id --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev --entrypoint /bin/sh "$1" -c \
    'mkdir /tmp/probe && /opt/legacy-nss/bin/certutil -N -d sql:/tmp/probe --empty-password && /opt/legacy-nss/bin/certutil -L -d sql:/tmp/probe >/dev/null'
}

image_label() {
  podman image inspect --format "{{ index .Config.Labels \"$2\" }}" "$1" 2>/dev/null || true
}

build_baseline() {
  if podman image exists "$BASELINE_IMAGE" >/dev/null 2>&1; then
    ok "baseline NSS ya disponible: $BASELINE_IMAGE"
    return 0
  fi
  info "construyendo baseline histórico solo para diagnóstico: $BASELINE_IMAGE"
  podman build --pull=missing --tag "$BASELINE_IMAGE" "$CONTEXT_DIR"
  runtime_probe "$BASELINE_IMAGE" || die 'el baseline NSS no puede ejecutar certutil'
  ok "baseline NSS construido: $BASELINE_IMAGE"
}

build_exact_runtime() (
  local build_context build_manifest patches_hash source_hash lib_hash
  validate_source_bundle
  build_manifest="${SOURCE_BUNDLE}/source-manifest.env"
  patches_hash="$(sha256sum -- "${SOURCE_BUNDLE}/patches.sha256" | awk '{print $1}')"
  source_hash="$(sha256sum -- "${SOURCE_BUNDLE}/b2g-source.sha256" | awk '{print $1}')"
  lib_hash="$(manifest_value "$build_manifest" B2G_LIBNSS3_SHA256)"
  build_context="$(mktemp -d "${TMPDIR:-/tmp}/rafex-firefoxos-ca-build.XXXXXX")"
  trap 'rm -rf -- "$build_context"' EXIT
  mkdir -p -- "${build_context}/b2g46-source"
  cp -- "${CONTEXT_DIR}/Containerfile.b2g46" "${build_context}/Containerfile"
  cp -a -- "${SOURCE_BUNDLE}/." "${build_context}/b2g46-source/"
  podman build --pull=missing --file "${build_context}/Containerfile" \
    --tag "$EXACT_IMAGE" \
    --build-arg "NSS_VERSION=${EXPECTED_NSS_VERSION}" \
    --build-arg "NSPR_VERSION=${EXPECTED_NSPR_VERSION}" \
    --build-arg "B2G_VERSION=${EXPECTED_B2G_VERSION}" \
    --build-arg "B2G_BUILD_ID=${EXPECTED_B2G_BUILD_ID}" \
    --build-arg "B2G_SOURCE_REPOSITORY=${EXPECTED_B2G_SOURCE_REPOSITORY}" \
    --build-arg "B2G_LIBNSS3_SHA256=${lib_hash}" \
    --build-arg "B2G_PATCHES_SHA256=${patches_hash}" \
    --build-arg "B2G_SOURCE_TREE_SHA256=${source_hash}" \
    --build-arg 'RUNTIME_STATUS=matched' \
    "$build_context"
  [[ "$(image_label "$EXACT_IMAGE" org.rafex.firefoxos.runtime-status)" == matched ]] ||
    die 'NO-GO: la imagen no quedó etiquetada como runtime matched'
  runtime_probe "$EXACT_IMAGE" || die 'NO-GO: el runtime B2G no puede ejecutar certutil'
  ok "runtime B2G exacto construido: $EXACT_IMAGE"
)

show_status() {
  local candidate version exact_status source_status
  printf '═══ Herramientas NSS para Firefox OS Flame ═══\n'
  candidate="$(package_candidate "$PODMAN_PACKAGE")"
  if package_installed "$PODMAN_PACKAGE"; then
    version="$(dpkg-query -W -f='${Version}' "$PODMAN_PACKAGE" 2>/dev/null || true)"
    ok "$PODMAN_PACKAGE instalado (${version:-versión desconocida})"
  else
    warn "$PODMAN_PACKAGE ausente (candidato: ${candidate:-(none)})"
  fi
  if [[ -f "$OBSERVED_RUNTIME_MANIFEST" ]]; then
    ok 'manifiesto del build Flame observado presente'
    printf 'build observado: %s / %s\n' "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_VERSION)" "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_BUILD_ID)"
    printf 'libnss3.so SHA-256: %s\n' "$(manifest_value "$OBSERVED_RUNTIME_MANIFEST" B2G_LIBNSS3_SHA256)"
  else
    info 'manifiesto del runtime del Flame: aún no identificado'
  fi
  if command -v podman >/dev/null 2>&1; then
    ok "Podman disponible: $(command -v podman)"
    if podman image exists "$BASELINE_IMAGE" >/dev/null 2>&1; then
      ok "baseline histórico presente: $BASELINE_IMAGE (solo diagnóstico)"
    else
      warn "baseline histórico ausente: $BASELINE_IMAGE"
    fi
    if podman image exists "$EXACT_IMAGE" >/dev/null 2>&1; then
      exact_status="$(image_label "$EXACT_IMAGE" org.rafex.firefoxos.runtime-status)"
      if [[ "$exact_status" == matched ]]; then
        ok "runtime exacto etiquetado matched: $EXACT_IMAGE"
      else
        warn "runtime $EXACT_IMAGE presente pero no está autorizado"
      fi
    else
      warn "runtime exacto ausente: $EXACT_IMAGE"
    fi
  else
    warn 'Podman no está disponible'
  fi
  if [[ -d "$SOURCE_BUNDLE" ]]; then
    source_status='presente; valida con --check o --apply'
  else
    source_status='ausente; no se puede reproducir el runtime exacto'
  fi
  printf 'bundle B2G: %s\n' "$source_status"
  info 'no se instala certutil en el host, no se reemplaza libnssckbi.so y no se modifica el teléfono'
}

show_plan() {
  printf '═══ Plan runtime NSS exacto del Flame ═══\n'
  info "conservar o construir el baseline NSS 3.21: $BASELINE_IMAGE (diagnóstico únicamente)"
  info "buscar bundle local verificado en: $SOURCE_BUNDLE"
  info 'validar Build ID, SourceRepository, SHA-256 de NSS/NSPR, parches y libnss3.so'
  info "construir $EXACT_IMAGE solo con ese bundle; ejecutar certutil rootless, sin red y sin capacidades"
  info 'el helper CA rechazará cualquier imagen baseline o NSS genérica durante --apply'
  info 'si falta el árbol/parche exacto, el resultado será NO-GO sin escribir el Flame'
}

apply_install() {
  check_candidate
  [[ -f "${CONTEXT_DIR}/Containerfile" && -f "${CONTEXT_DIR}/Containerfile.b2g46" ]] ||
    die 'falta el contexto Podman versionado de Firefox OS'
  if ! package_installed "$PODMAN_PACKAGE"; then
    sudo -v
    info 'actualizando índices APT'
    sudo apt-get update
    info "instalando $PODMAN_PACKAGE desde Debian"
    sudo apt-get --no-remove install --no-install-recommends -y "$PODMAN_PACKAGE"
  fi
  command -v podman >/dev/null 2>&1 || die 'Podman no quedó disponible después de la instalación'
  build_baseline
  if [[ ! -d "$SOURCE_BUNDLE" ]]; then
    die "NO-GO: falta el bundle B2G exacto; no se construirá $EXACT_IMAGE ni se tocará el teléfono"
  fi
  build_exact_runtime
}

main() {
  parse_args "$@"
  require_debian
  case "$ACTION" in
    check)
      show_status
      check_candidate
      [[ -f "${CONTEXT_DIR}/Containerfile" && -f "${CONTEXT_DIR}/Containerfile.b2g46" ]] ||
        die 'falta el contexto Podman versionado de Firefox OS'
      if [[ -d "$SOURCE_BUNDLE" ]]; then validate_source_bundle; else warn 'NO-GO: falta el bundle B2G exacto'; fi
      ;;
    plan) show_plan ;;
    apply) apply_install ;;
    status) show_status ;;
  esac
}

main "$@"
