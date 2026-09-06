#!/usr/bin/env bash
# shellcheck shell=bash
# Audita runtimes legacy de mise y elimina solo rutas explícitamente conocidas.
set -Eeuo pipefail
umask 077

ACTION="check"
PURGE_LEGACY=0
MISE_BIN="${HOME}/.local/bin/mise"
REGISTRY_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/rafex-runtimes/registry.tsv"
LEGACY_ROOT="${HOME}/.local/share/mise/installs"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso:
  reconcile_runtimes_linux.sh --check
  reconcile_runtimes_linux.sh --plan
  reconcile_runtimes_linux.sh --apply
  reconcile_runtimes_linux.sh --apply --purge-legacy

Audita el manifiesto propio y los runtimes que mise instaló directamente.
Solo --apply --purge-legacy puede eliminar las rutas legacy conocidas.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --purge-legacy) PURGE_LEGACY=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$PURGE_LEGACY" -eq 0 || "$ACTION" == apply ]] || \
    die '--purge-legacy requiere --apply'
}

find_mise() {
  if [[ -x "$MISE_BIN" ]]; then
    printf '%s\n' "$MISE_BIN"
  else
    command -v mise
  fi
}

runtime_command() {
  case "$1" in
    java|graalvm) printf '%s\n' java ;;
    node) printf '%s\n' node ;;
    maven) printf '%s\n' mvn ;;
    gradle) printf '%s\n' gradle ;;
    *) return 1 ;;
  esac
}

replacement_for() {
  local tool="$1" command_name
  command_name="$(runtime_command "$tool")"
  [[ -f "$REGISTRY_FILE" ]] || return 1
  while IFS=$'\t' read -r registered_tool provider _version path _checksum _source; do
    if [[ "$tool" == graalvm ]]; then
      [[ "$registered_tool" == java && "$provider" == graalvm-* ]] || continue
    else
      [[ "$registered_tool" == "$tool" ]] || continue
    fi
    [[ -x "$path/bin/$command_name" ]] || continue
    printf '%s\n' "$path"
    return 0
  done < "$REGISTRY_FILE"
  return 1
}

# A diferencia de replacement_for() (una sola fila, la primera que matchea,
# usada solo para "¿existe algún reemplazo?"), esta lista TODAS las rutas
# propias verificadas para ese tool/provider — el registro puede tener más
# de una versión instalada a la vez (p. ej. dos GraalVM), y un alias legacy
# de mise ("25", "25.0", "latest", ...) puede apuntar legítimamente a
# cualquiera de ellas, no solo a la primera fila del archivo.
replacement_targets_for() {
  local tool="$1" command_name found=1
  command_name="$(runtime_command "$tool")"
  [[ -f "$REGISTRY_FILE" ]] || return 1
  while IFS=$'\t' read -r registered_tool provider _version path _checksum _source; do
    if [[ "$tool" == graalvm ]]; then
      [[ "$registered_tool" == java && "$provider" == graalvm-* ]] || continue
    else
      [[ "$registered_tool" == "$tool" ]] || continue
    fi
    [[ -x "$path/bin/$command_name" ]] || continue
    printf '%s\n' "$path"
    found=0
  done < "$REGISTRY_FILE"
  return "$found"
}

legacy_paths() {
  cat <<EOF
java|${LEGACY_ROOT}/java/temurin-21.0.12+101.0.LTS
java|${LEGACY_ROOT}/java/temurin-21
java|${LEGACY_ROOT}/java/temurin-21.0
node|${LEGACY_ROOT}/node/24.20.0
graalvm|${LEGACY_ROOT}/graalvm/25.0.2
graalvm|${LEGACY_ROOT}/graalvm/25
graalvm|${LEGACY_ROOT}/graalvm/25.0
maven|${LEGACY_ROOT}/maven/3.9.16
gradle|${LEGACY_ROOT}/gradle/9.7.1
EOF
}

direct_mise_runtimes() {
  local tool
  for tool in java graalvm node maven gradle; do
    [[ -d "${LEGACY_ROOT}/${tool}" ]] || continue
    while IFS= read -r path; do
      printf '%s|%s\n' "$tool" "$path"
    done < <(find "${LEGACY_ROOT}/${tool}" -mindepth 1 -maxdepth 1 -type d ! -type l -print)
  done
}

is_known_legacy_path() {
  local candidate="$1" known_path
  while IFS='|' read -r _known_tool known_path; do
    [[ "$candidate" == "$known_path" ]] && return 0
  done < <(legacy_paths)
  return 1
}

show_registry() {
  echo '═══ Registro de runtimes propios ═══'
  if [[ -s "$REGISTRY_FILE" ]]; then
    awk -F '\t' '{ printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4 }' "$REGISTRY_FILE"
  else
    printf 'registro=missing\n'
  fi
}

audit_legacy() {
  local tool path replacement
  echo '═══ Runtimes legacy detectados ═══'
  while IFS='|' read -r tool path; do
    [[ -e "$path" || -L "$path" ]] || continue
    if replacement="$(replacement_for "$tool" 2>/dev/null)"; then
      printf 'legacy=%s\nreplacement=%s\n' "$path" "$replacement"
      [[ "$ACTION" == plan ]] && info "[plan] eliminar únicamente $path"
    else
      warn "sin reemplazo propio verificado: $path"
    fi
  done < <(legacy_paths)
  while IFS='|' read -r tool path; do
    is_known_legacy_path "$path" && continue
    warn "instalación directa de mise no reconocida: $path; no se borrará automáticamente"
  done < <(direct_mise_runtimes)
}

legacy_identifier() {
  local tool="$1" path="$2" version
  version="${path##*/}"
  case "$tool" in
    java)
      case "$version" in
        temurin-21*) printf 'java@temurin-21\n' ;;
        *) return 1 ;;
      esac
      ;;
    graalvm) printf 'graalvm@%s\n' "$version" ;;
    node|maven|gradle) printf '%s@%s\n' "$tool" "$version" ;;
    *) return 1 ;;
  esac
}

validate_purge_candidates() {
  local tool path replacement identifier active
  local canonical_legacy canonical_active candidate matched
  while IFS='|' read -r tool path; do
    [[ -e "$path" || -L "$path" ]] || continue
    replacement="$(replacement_for "$tool" 2>/dev/null || true)"
    [[ -n "$replacement" ]] || die "no se elimina $path: falta reemplazo verificado"
    [[ "$path" != "$replacement" ]] || die "no se elimina $path: coincide con el reemplazo"

    if [[ -L "$path" ]]; then
      # integrate_registry() ya reemplazó esta ruta legacy por un symlink
      # hacia algún reemplazo propio (mise link --force). Borrarla con
      # rm -rf solo quita el symlink, nunca el directorio real al que
      # apunta. El registro puede tener más de una versión instalada del
      # mismo tool (p. ej. dos GraalVM) y un alias legacy de mise puede
      # apuntar legítimamente a cualquiera de ellas, así que basta con que
      # coincida con AL MENOS una fila verificada — no necesariamente con
      # la primera (replacement_for solo devuelve una).
      canonical_legacy="$(readlink -f -- "$path" 2>/dev/null || true)"
      matched=1
      if [[ -n "$canonical_legacy" ]]; then
        while IFS= read -r candidate; do
          [[ "$(readlink -f -- "$candidate" 2>/dev/null || true)" == "$canonical_legacy" ]] || continue
          matched=0
          break
        done < <(replacement_targets_for "$tool" 2>/dev/null || true)
      fi
      [[ "$matched" -eq 0 ]] || \
        die "no se elimina $path: symlink legacy apunta a un destino inesperado"
      continue
    fi

    # $path sigue siendo un directorio real: el único caso de peligro
    # genuino es que mise todavía lo considere el runtime activo.
    identifier="$(legacy_identifier "$tool" "$path" 2>/dev/null || true)"
    if [[ -n "$identifier" ]]; then
      active="$(mise where "$identifier" 2>/dev/null | awk 'NF { print; exit }' || true)"
      if [[ -n "$active" ]]; then
        canonical_legacy="$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")"
        canonical_active="$(readlink -f -- "$active" 2>/dev/null || printf '%s' "$active")"
        [[ "$canonical_active" != "$canonical_legacy" ]] || \
          die "no se elimina $path: todavía es el runtime activo de $identifier"
      fi
    fi
  done < <(legacy_paths)
}

mise_id_for_entry() {
  local tool="$1" provider="$2" version="$3"
  case "$tool:$provider" in
    java:temurin|java:semeru) printf 'java@%s\n' "$version" ;;
    java:graalvm-*) printf 'graalvm@%s\n' "$version" ;;
    node:nodejs|maven:official|gradle:official) printf '%s@%s\n' "$tool" "$version" ;;
    *) return 1 ;;
  esac
}

integrate_registry() {
  local tool provider version path mise_path identifier
  mise_path="$(find_mise)"
  [[ -f "$REGISTRY_FILE" ]] || return 0
  while IFS=$'\t' read -r tool provider version path _checksum _source; do
    [[ -n "$tool" && -x "$path/bin/$(runtime_command "$tool")" ]] || continue
    identifier="$(mise_id_for_entry "$tool" "$provider" "$version" 2>/dev/null || true)"
    [[ -n "$identifier" ]] || continue
    "$mise_path" link --force "$identifier" "$path"
  done < "$REGISTRY_FILE"

  if [[ -L "$HOME/.local/share/java-runtimes/current-java" ]]; then
    local java_path
    java_path="$(readlink -f -- "$HOME/.local/share/java-runtimes/current-java" 2>/dev/null || true)"
    while IFS=$'\t' read -r tool provider version path _checksum _source; do
      [[ "$tool" == java ]] || continue
      [[ "$(readlink -f -- "$path" 2>/dev/null || true)" == "$java_path" ]] || continue
      identifier="$(mise_id_for_entry "$tool" "$provider" "$version")"
      "$mise_path" use --global "$identifier"
      break
    done < "$REGISTRY_FILE"
  fi
  if [[ -L "$HOME/.local/share/node-runtimes/current-node" ]]; then
    local node_path
    node_path="$(readlink -f -- "$HOME/.local/share/node-runtimes/current-node" 2>/dev/null || true)"
    while IFS=$'\t' read -r tool provider version path _checksum _source; do
      [[ "$tool" == node ]] || continue
      [[ "$(readlink -f -- "$path" 2>/dev/null || true)" == "$node_path" ]] || continue
      "$mise_path" use --global "node@$version"
      break
    done < "$REGISTRY_FILE"
  fi
  for tool in maven gradle; do
    local current_path
    current_path="$HOME/.local/share/build-runtimes/current-$tool"
    [[ -L "$current_path" ]] || continue
    path="$(readlink -f -- "$current_path" 2>/dev/null || true)"
    while IFS=$'\t' read -r _tool provider version _path _checksum _source; do
      [[ "$_tool" == "$tool" ]] || continue
      [[ "$(readlink -f -- "$_path" 2>/dev/null || true)" == "$path" ]] || continue
      "$mise_path" use --global "$tool@$version"
      break
    done < "$REGISTRY_FILE"
  done
}

purge_legacy() {
  local tool path replacement
  validate_purge_candidates
  while IFS='|' read -r tool path; do
    [[ -e "$path" || -L "$path" ]] || continue
    replacement="$(replacement_for "$tool" 2>/dev/null || true)"
    [[ -n "$replacement" ]] || die "no se elimina $path: falta reemplazo verificado"
    [[ "$path" != "$replacement" ]] || die "no se elimina $path: coincide con el reemplazo"
    rm -rf -- "$path"
    info "legacy eliminado: $path"
  done < <(legacy_paths)
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este script requiere Linux'
  show_registry
  audit_legacy
  if [[ "$ACTION" == apply ]]; then
    find_mise >/dev/null || die 'mise no está instalado'
    integrate_registry
    "$(find_mise)" reshim
    if [[ "$PURGE_LEGACY" -eq 1 ]]; then
      purge_legacy
      # Borrar una ruta legacy desregistra esa versión de mise (sus shims
      # resuelven en vivo contra mise/installs/<tool>/<version>): sin este
      # segundo enlace, node/java/mvn/gradle dejarían de resolver hasta la
      # siguiente corrida. Se re-crea de inmediato en la misma invocación.
      integrate_registry
      "$(find_mise)" reshim
      show_registry
      audit_legacy
    else
      info 'no se eliminó ningún runtime; usa --purge-legacy explícitamente'
    fi
    ok 'reconciliación completada'
  fi
}

main "$@"
