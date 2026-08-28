#!/usr/bin/env bash
# shellcheck shell=bash
# Funciones compartidas para registrar runtimes descargados por el repositorio.

RUNTIME_REGISTRY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rafex-runtimes"
RUNTIME_REGISTRY_FILE="${RUNTIME_REGISTRY_DIR}/registry.tsv"

runtime_registry_init() {
  mkdir -p "$RUNTIME_REGISTRY_DIR"
  [[ -e "$RUNTIME_REGISTRY_FILE" ]] || : >"$RUNTIME_REGISTRY_FILE"
  chmod 700 "$RUNTIME_REGISTRY_DIR"
  chmod 600 "$RUNTIME_REGISTRY_FILE"
}

runtime_registry_upsert() {
  local tool="$1" provider="$2" version="$3" path="$4" checksum="$5" source="$6"
  local temporary
  runtime_registry_init
  temporary="$(mktemp "${RUNTIME_REGISTRY_FILE}.tmp.XXXXXX")"
  awk -F '\t' -v tool="$tool" -v provider="$provider" -v version="$version" \
    '$1 != tool || $2 != provider || $3 != version' "$RUNTIME_REGISTRY_FILE" >"$temporary"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$tool" "$provider" "$version" "$path" "$checksum" "$source" >>"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$RUNTIME_REGISTRY_FILE"
}

runtime_registry_remove() {
  local tool="$1" provider="$2" version="$3" temporary
  [[ -f "$RUNTIME_REGISTRY_FILE" ]] || return 0
  temporary="$(mktemp "${RUNTIME_REGISTRY_FILE}.tmp.XXXXXX")"
  awk -F '\t' -v tool="$tool" -v provider="$provider" -v version="$version" \
    '$1 != tool || $2 != provider || $3 != version' "$RUNTIME_REGISTRY_FILE" >"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$RUNTIME_REGISTRY_FILE"
}

runtime_registry_list() {
  [[ -f "$RUNTIME_REGISTRY_FILE" ]] || return 0
  awk -F '\t' -v tool="${1:-}" '$1 == tool || tool == ""' "$RUNTIME_REGISTRY_FILE"
}
