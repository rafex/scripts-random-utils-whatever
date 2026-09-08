#!/usr/bin/env bash
# shellcheck shell=bash
# Biblioteca de publicación segura de configuración de usuario ThinkPad.
# Se debe sourcear desde rafex_config_linux.sh.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '%s\n' 'Este archivo es una biblioteca; úsalo mediante source.' >&2
  exit 2
fi

rafex_publish_die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  return 1
}

rafex_publish_sha256() {
  local path="$1"
  if [[ -L "$path" ]]; then
    printf 'symlink:%s\n' "$(readlink "$path")"
  elif [[ -f "$path" ]]; then
    sha256sum -- "$path" | awk '{print $1}'
  elif [[ -e "$path" ]]; then
    printf 'other\n'
  else
    printf 'absent\n'
  fi
}

rafex_publish_json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

rafex_publish_log() {
  local event="$1" resource="$2" target="$3" before="$4" after="$5" detail="${6:-}"
  mkdir -p -- "$RAFEX_PUBLISH_STATE_DIR"
  chmod 700 -- "$RAFEX_PUBLISH_STATE_DIR"
  printf '{"timestamp":"%s","event":"%s","resource":"%s","target":"%s","before":"%s","after":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(rafex_publish_json_escape "$event")" \
    "$(rafex_publish_json_escape "$resource")" \
    "$(rafex_publish_json_escape "$target")" \
    "$(rafex_publish_json_escape "$before")" \
    "$(rafex_publish_json_escape "$after")" \
    "$(rafex_publish_json_escape "$detail")" >> "$RAFEX_PUBLISH_LOG"
  chmod 600 -- "$RAFEX_PUBLISH_LOG"
}

rafex_publish_assert_inside() {
  local path="$1" root="$2" resolved_root resolved_path
  resolved_root="$(realpath -m -- "$root")"
  resolved_path="$(realpath -m -- "$path")"
  [[ "$resolved_path" == "$resolved_root"/* ]] ||
    rafex_publish_die "ruta fuera del árbol permitido: $path"
}

rafex_publish_backup() {
  local target="$1" relative="$2" backup_root="$3" destination
  [[ -e "$target" || -L "$target" ]] || return 0
  destination="$backup_root/$relative"
  mkdir -p -- "$(dirname -- "$destination")"
  cp -a -- "$target" "$destination"
  printf '%s\n' "$destination"
}

rafex_publish_is_exact_symlink() {
  local target="$1" source="$2"
  [[ -L "$target" ]] || return 1
  [[ "$(readlink -f -- "$target")" == "$(realpath -m -- "$source")" ]]
}

rafex_publish_refuse_unmanaged() {
  local target="$1" source="$2" allow_adopt="${3:-0}"
  [[ -e "$target" || -L "$target" ]] || return 0
  rafex_publish_is_exact_symlink "$target" "$source" && return 0
  (( allow_adopt == 1 )) && return 0
  rafex_publish_die "destino no administrado; usa --adopt tras revisar el respaldo: $target"
}

rafex_publish_install_symlink() {
  local source="$1" target="$2" mode="$3" allow_adopt="$4" relative="$5" backup_root="$6" temporary before after
  [[ -f "$source" ]] || rafex_publish_die "fuente ausente: $source"
  rafex_publish_assert_inside "$source" "$RAFEX_PUBLISH_CHECKOUT"
  if rafex_publish_is_exact_symlink "$target" "$source"; then
    return 0
  fi
  rafex_publish_refuse_unmanaged "$target" "$source" "$allow_adopt"
  before="$(rafex_publish_sha256 "$target")"
  if (( allow_adopt == 1 )); then
    rafex_publish_backup "$target" "$relative" "$backup_root" >/dev/null || true
  fi
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-link.XXXXXX")"
  rm -f -- "$temporary"
  ln -s -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
  after="$(rafex_publish_sha256 "$target")"
  rafex_publish_log published "static" "$target" "$before" "$after" "symlink=$source"
}

rafex_publish_install_generated() {
  local source="$1" target="$2" mode="$3" allow_adopt="$4" relative="$5" backup_root="$6" temporary before after
  : "$mode" # El modo queda en el manifiesto; los symlinks heredan el modo de la fuente.
  [[ -f "$source" ]] || rafex_publish_die "generado ausente: $source"
  rafex_publish_assert_inside "$source" "$RAFEX_PUBLISH_GENERATED_ROOT"
  if rafex_publish_is_exact_symlink "$target" "$source"; then
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]] && (( allow_adopt == 0 )); then
    rafex_publish_die "destino generado no administrado; usa --adopt tras revisar el respaldo: $target"
  fi
  before="$(rafex_publish_sha256 "$target")"
  if (( allow_adopt == 1 )); then
    rafex_publish_backup "$target" "$relative" "$backup_root" >/dev/null || true
  fi
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-generated-link.XXXXXX")"
  rm -f -- "$temporary"
  ln -s -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
  after="$(rafex_publish_sha256 "$target")"
  rafex_publish_log published "generated" "$target" "$before" "$after" "source=$source"
}

rafex_publish_lock() {
  mkdir -p -- "$RAFEX_PUBLISH_STATE_DIR"
  exec 9>"$RAFEX_PUBLISH_LOCK_FILE"
  flock -n 9 || rafex_publish_die 'ya existe otra operación del publicador en curso'
}
