#!/usr/bin/env bash
# shellcheck shell=bash
# thinkpad_config_guard_linux.sh v1.3.0
# Utilidades compartidas para registrar cambios del perfil ThinkPad.
# Se debe sourcear; no está pensado para ejecutarse directamente.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '%s\n' 'Este archivo es una biblioteca; úsalo mediante source desde un script Rafex.' >&2
  exit 2
fi

RAFEX_THINKPAD_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/thinkpad-config"
RAFEX_THINKPAD_CHANGE_LOG="$RAFEX_THINKPAD_STATE_DIR/changes.jsonl"
RAFEX_THINKPAD_OWNERSHIP_REGISTRY="${RAFEX_THINKPAD_OWNERSHIP_REGISTRY:-}"
RAFEX_THINKPAD_HISTORY_ROOT="${RAFEX_THINKPAD_HISTORY:-$HOME/.local/share/rafex-thinkpad}"
RAFEX_THINKPAD_HISTORY_FILES="$RAFEX_THINKPAD_HISTORY_ROOT/files"
RAFEX_THINKPAD_HISTORY_MANIFEST="$RAFEX_THINKPAD_HISTORY_ROOT/installed.tsv"
RAFEX_THINKPAD_HISTORY_LOCK="$RAFEX_THINKPAD_HISTORY_ROOT/.history.lock"
RAFEX_THINKPAD_OPERATION_LOCK="${XDG_RUNTIME_DIR:-$RAFEX_THINKPAD_STATE_DIR}/rafex-thinkpad/config.lock"
RAFEX_THINKPAD_LOCK_FD=''

rafex_guard_sha256() {
  local path="$1"
  if [[ -L "$path" ]]; then
    printf 'symlink:%s\n' "$(readlink -- "$path")"
    return 0
  fi
  [[ -f "$path" ]] || { printf '%s\n' absent; return 0; }
  sha256sum "$path" | awk '{print $1}'
}

rafex_guard_json() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

rafex_guard_log() {
  local event="$1" owner="$2" resource="$3" target="$4" before="$5" after="$6" detail="${7:-}"
  mkdir -p -- "$RAFEX_THINKPAD_STATE_DIR"
  chmod 700 "$RAFEX_THINKPAD_STATE_DIR"
  printf '{"timestamp":"%s","event":"%s","owner":"%s","resource":"%s","target":"%s","before":"%s","after":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(rafex_guard_json "$event")" "$(rafex_guard_json "$owner")" \
    "$(rafex_guard_json "$resource")" "$(rafex_guard_json "$target")" \
    "$(rafex_guard_json "$before")" "$(rafex_guard_json "$after")" \
    "$(rafex_guard_json "$detail")" >> "$RAFEX_THINKPAD_CHANGE_LOG"
  chmod 600 "$RAFEX_THINKPAD_CHANGE_LOG"
}

rafex_guard_backup() {
  local path="$1" owner="$2" resource="$3" stamp backup before
  [[ -e "$path" || -L "$path" ]] || return 0
  stamp="$(date +%Y%m%d_%H%M%S)"
  backup="${path}.rafex-${owner}.${stamp}.bak"
  before="$(rafex_guard_sha256 "$path")"
  cp -a -- "$path" "$backup"
  rafex_guard_log backup "$owner" "$resource" "$path" "$before" "$before" "$backup"
  printf '%s\n' "$backup"
}

rafex_guard_record_write() {
  local owner="$1" resource="$2" target="$3" before="$4" detail="${5:-}"
  local after
  after="$(rafex_guard_sha256 "$target")"
  rafex_guard_log applied "$owner" "$resource" "$target" "$before" "$after" "$detail"
  if ! rafex_guard_history_snapshot "$owner" "$resource" "$target" "$after"; then
    rafex_guard_log blocked "$owner" "$resource" "$target" "$before" "$after" 'no se pudo registrar el historial local'
    return 1
  fi
}

# Permite que el instalador propietario de un componente cree una semilla
# ausente cuyo propietario posterior es otro coordinador explícito. Nunca
# permite reemplazar un recurso existente ni delega una escritura conflictiva.
rafex_guard_bootstrap_write() {
  local owner="$1" resource="$2" target="$3" before="$4" detail="${5:-}" expected
  [[ "$before" == absent ]] || {
    rafex_guard_log blocked "$owner" "$resource" "$target" "$before" "$before" \
      'bootstrap rechazado: el recurso ya existe'
    return 1
  }
  expected="$(awk -F'|' -v resource="$resource" '$1 == resource { print $2; exit }' \
    "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY" 2>/dev/null || true)"
  [[ "$expected" == "$owner" ]] || {
    rafex_guard_log blocked "$owner" "$resource" "$target" "$before" absent \
      "bootstrap rechazado; propietario declarado: $expected"
    return 1
  }
  rafex_guard_record_write "$owner" "$resource" "$target" "$before" \
    "bootstrap realizado por $detail"
}

# Los escritores de i3 comparten esta capa para que, una vez activado el
# despliegue central, cada uno actualice solo su fragmento administrado.
RAFEX_I3_FRAGMENT_LIBRARY="${BASH_SOURCE[0]%/*}/thinkpad_i3_fragments_linux.sh"
if [[ -r "$RAFEX_I3_FRAGMENT_LIBRARY" ]]; then
  # shellcheck disable=SC1090
  source "$RAFEX_I3_FRAGMENT_LIBRARY"
fi

rafex_guard_begin() {
  local lock_dir
  [[ -n "$RAFEX_THINKPAD_LOCK_FD" ]] && return 0
  command -v flock >/dev/null 2>&1 || return 1
  lock_dir="${RAFEX_THINKPAD_OPERATION_LOCK%/*}"
  mkdir -p -- "$lock_dir"
  chmod 700 -- "$lock_dir"
  # Un descriptor fijo es deliberado: algunos Bash empaquetados/ejecutados
  # desde entornos de prueba no soportan de forma consistente la expansión
  # de descriptores con `exec {var}>...`.
  RAFEX_THINKPAD_LOCK_FD=9
  exec 9>"$RAFEX_THINKPAD_OPERATION_LOCK"
  if ! flock -n 9; then
    exec 9>&-
    RAFEX_THINKPAD_LOCK_FD=''
    return 1
  fi
}

rafex_guard_end() {
  [[ -n "$RAFEX_THINKPAD_LOCK_FD" ]] || return 0
  flock -u "$RAFEX_THINKPAD_LOCK_FD" || true
  eval "exec ${RAFEX_THINKPAD_LOCK_FD}>&-"
  RAFEX_THINKPAD_LOCK_FD=''
}

rafex_guard_history_relative_target() {
  local target="$1"
  case "$target" in
    "$HOME"/*) printf 'home/%s\n' "${target#"$HOME"/}" ;;
    /etc/*) printf 'etc/%s\n' "${target#/etc/}" ;;
    /usr/local/*) printf 'usr-local/%s\n' "${target#/usr/local/}" ;;
    /lib/*) printf 'lib/%s\n' "${target#/lib/}" ;;
    *) return 1 ;;
  esac
}

rafex_guard_history_init() {
  mkdir -p -- "$RAFEX_THINKPAD_HISTORY_FILES"
  chmod 700 -- "$RAFEX_THINKPAD_HISTORY_ROOT" "$RAFEX_THINKPAD_HISTORY_FILES"
  if [[ ! -d "$RAFEX_THINKPAD_HISTORY_ROOT/.git" ]]; then
    command -v git >/dev/null 2>&1 || return 1
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" init -q
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" config user.name 'Rafex ThinkPad'
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" config user.email 'rafex-thinkpad@localhost'
  fi
  if [[ ! -e "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore" ]]; then
    printf '%s\n' '*.tmp' '*.bak' '*.swp' '.history.lock' > "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore"
    chmod 600 -- "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore"
  elif ! grep -Fqx '.history.lock' "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore"; then
    printf '%s\n' '.history.lock' >> "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore"
    chmod 600 -- "$RAFEX_THINKPAD_HISTORY_ROOT/.gitignore"
  fi
  if [[ ! -e "$RAFEX_THINKPAD_HISTORY_MANIFEST" ]]; then
    printf '%s\n' '# timestamp|owner|resource|target|sha256|mode|snapshot' > "$RAFEX_THINKPAD_HISTORY_MANIFEST"
    chmod 600 -- "$RAFEX_THINKPAD_HISTORY_MANIFEST"
  fi
}

rafex_guard_history_snapshot() {
  local owner="$1" resource="$2" target="$3" hash="$4"
  local relative snapshot temporary mode stamp lock_fd
  relative="$(rafex_guard_history_relative_target "$target")" || return 0
  command -v git >/dev/null 2>&1 || return 1
  command -v flock >/dev/null 2>&1 || return 1
  rafex_guard_history_init || return 1
  # El descriptor 8 está reservado para el lock del historial; el descriptor
  # 9 se usa por rafex_guard_begin para el lock de operación.
  lock_fd=8
  exec 8>"$RAFEX_THINKPAD_HISTORY_LOCK"
  flock -x "$lock_fd"
  snapshot="$RAFEX_THINKPAD_HISTORY_FILES/$relative"
  mkdir -p -- "$(dirname -- "$snapshot")"
  if [[ -f "$target" ]]; then
    temporary="$(mktemp "$(dirname -- "$snapshot")/.snapshot.XXXXXX")"
    if ! cp -p -- "$target" "$temporary" 2>/dev/null; then
      command -v sudo >/dev/null 2>&1 || { rm -f -- "$temporary"; flock -u "$lock_fd"; exec 8>&-; return 1; }
      sudo -n cp -p -- "$target" "$temporary" || { rm -f -- "$temporary"; flock -u "$lock_fd"; exec 8>&-; return 1; }
    fi
    mv -f -- "$temporary" "$snapshot"
    if ! mode="$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target")"; then
      mode="$(sudo -n stat -c '%a' "$target" 2>/dev/null || sudo -n stat -f '%Lp' "$target")" || { flock -u "$lock_fd"; exec 8>&-; return 1; }
    fi
  elif [[ -L "$target" ]]; then
    temporary="$(mktemp "$(dirname -- "$snapshot")/.snapshot.XXXXXX")"
    rm -f -- "$temporary"
    ln -s -- "$(readlink -- "$target")" "$temporary"
    mv -f -- "$temporary" "$snapshot"
    mode='symlink'
  else
    rm -f -- "$snapshot"
    mode='absent'
  fi
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '%s\n' '# timestamp|owner|resource|target|sha256|mode|snapshot'
    awk -F'|' -v resource="$resource" -v target="$target" \
      'NR > 1 && !($3 == resource && $4 == target) { print }' \
      "$RAFEX_THINKPAD_HISTORY_MANIFEST"
    printf '%s|%s|%s|%s|%s|%s|files/%s\n' "$stamp" "$owner" "$resource" "$target" "$hash" "$mode" "$relative"
  } > "${RAFEX_THINKPAD_HISTORY_MANIFEST}.tmp"
  mv -f -- "${RAFEX_THINKPAD_HISTORY_MANIFEST}.tmp" "$RAFEX_THINKPAD_HISTORY_MANIFEST"
  chmod 600 -- "$RAFEX_THINKPAD_HISTORY_MANIFEST"
  git -C "$RAFEX_THINKPAD_HISTORY_ROOT" add -- .gitignore installed.tsv
  if [[ -e "$snapshot" || -L "$snapshot" ]]; then
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" add -- "files/$relative"
  else
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" rm -q --cached --ignore-unmatch -- "files/$relative" || true
  fi
  if ! git -C "$RAFEX_THINKPAD_HISTORY_ROOT" diff --cached --quiet; then
    git -C "$RAFEX_THINKPAD_HISTORY_ROOT" commit -q -m "snapshot: ${owner}/${resource}"
  fi
  rafex_guard_log history-snapshot "$owner" "$resource" "$target" "$hash" "$hash" \
    "repo=$RAFEX_THINKPAD_HISTORY_ROOT"
  flock -u "$lock_fd"
  eval "exec ${lock_fd}>&-"
}

# Rechaza que un instalador se adjudique un recurso cuyo propietario declarado
# es otro. El registro se pasa desde el instalador para que esta biblioteca no
# dependa de una ruta fija fuera del repositorio.
rafex_guard_require_owner() {
  local resource="$1" owner="$2" expected
  if [[ -z "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY" || ! -r "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY" ]]; then
    rafex_guard_log blocked "$owner" "$resource" '' absent absent 'registro de propietarios ausente'
    printf '✗ ERROR: falta el registro de propietarios; no se permite escribir %s\n' "$resource" >&2
    return 1
  fi
  expected="$(awk -F'|' -v resource="$resource" '$1 == resource { print $2; exit }' "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY")"
  if [[ "$expected" == "$owner" ]]; then
    return 0
  fi
  rafex_guard_log blocked "$owner" "$resource" '' absent absent "propietario declarado: $expected"
  printf '✗ ERROR: recurso %s pertenece a %s; %s no puede sobrescribirlo\n' \
    "$resource" "$expected" "$owner" >&2
  return 1
}
