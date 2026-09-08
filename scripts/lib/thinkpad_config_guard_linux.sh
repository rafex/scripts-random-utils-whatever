#!/usr/bin/env bash
# shellcheck shell=bash
# Utilidades compartidas para registrar cambios del perfil ThinkPad.
# Se debe sourcear; no está pensado para ejecutarse directamente.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '%s\n' 'Este archivo es una biblioteca; úsalo mediante source desde un script Rafex.' >&2
  exit 2
fi

RAFEX_THINKPAD_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/thinkpad-config"
RAFEX_THINKPAD_CHANGE_LOG="$RAFEX_THINKPAD_STATE_DIR/changes.jsonl"
RAFEX_THINKPAD_OWNERSHIP_REGISTRY="${RAFEX_THINKPAD_OWNERSHIP_REGISTRY:-}"

rafex_guard_sha256() {
  local path="$1"
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
  [[ -e "$path" ]] || return 0
  stamp="$(date +%Y%m%d_%H%M%S)"
  backup="${path}.rafex-${owner}.${stamp}.bak"
  before="$(rafex_guard_sha256 "$path")"
  cp -a -- "$path" "$backup"
  rafex_guard_log backup "$owner" "$resource" "$path" "$before" "$before" "$backup"
  printf '%s\n' "$backup"
}

rafex_guard_record_write() {
  local owner="$1" resource="$2" target="$3" before="$4" detail="${5:-}"
  rafex_guard_log applied "$owner" "$resource" "$target" "$before" "$(rafex_guard_sha256 "$target")" "$detail"
}

# Rechaza que un instalador se adjudique un recurso cuyo propietario declarado
# es otro. El registro se pasa desde el instalador para que esta biblioteca no
# dependa de una ruta fija fuera del repositorio.
rafex_guard_require_owner() {
  local resource="$1" owner="$2" expected
  [[ -n "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY" && -r "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY" ]] \
    || return 0
  expected="$(awk -F'|' -v resource="$resource" '$1 == resource { print $2; exit }' "$RAFEX_THINKPAD_OWNERSHIP_REGISTRY")"
  if [[ -z "$expected" || "$expected" == "$owner" ]]; then
    return 0
  fi
  rafex_guard_log blocked "$owner" "$resource" '' absent absent "propietario declarado: $expected"
  printf '✗ ERROR: recurso %s pertenece a %s; %s no puede sobrescribirlo\n' \
    "$resource" "$expected" "$owner" >&2
  return 1
}
