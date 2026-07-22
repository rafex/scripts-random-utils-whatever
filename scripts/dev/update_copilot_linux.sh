#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# update_copilot_linux.sh
# Descarga la penúltima versión minor de GitHub Copilot Chat (.vsix) desde
# el Marketplace de VS Code. Variante con múltiples flags de API para mayor
# compatibilidad. Opcionalmente instala con codium/code.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

EXT_ID="GitHub.copilot-chat"
MARKETPLACE_QUERY_URL="https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
API_VER="3.0-preview.1"

OUT_DIR="${OUT_DIR:-./vsix}"
INSTALL="${INSTALL:-0}"
FORCE="${FORCE:-1}"
EDITOR_BIN="${EDITOR_BIN:-}"

usage() {
  cat <<'EOF'
Uso:
  ./update_copilot_linux.sh [--install] [--no-force] [--out DIR] [--bin codium|code]

Variables:
  OUT_DIR=./vsix
  INSTALL=0|1
  FORCE=0|1
  EDITOR_BIN=codium|code|/ruta
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --no-force) FORCE=0; shift ;;
    --out) OUT_DIR="${2:?Falta DIR}"; shift 2 ;;
    --bin) EDITOR_BIN="${2:?Falta binario}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Arg desconocido: $1"; usage; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta '$1'"; exit 2; }; }
need curl; need jq; need sort; need awk

mkdir -p "$OUT_DIR"

mk_payload() {
  local flags="$1"
  jq -nc --arg ext "$EXT_ID" --argjson flags "$flags" '{
    filters: [{ criteria: [{ filterType: 7, value: $ext }] }],
    flags: $flags
  }'
}

do_query() {
  local flags="$1" payload
  payload="$(mk_payload "$flags")"
  curl -fsSL --compressed \
    -H "Accept: application/json;api-version=${API_VER}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0" \
    --data-raw "$payload" \
    "$MARKETPLACE_QUERY_URL"
}

FLAGS_CANDIDATES=(914 2151 103 870 0)
JSON=""
USED_FLAGS=""
for f in "${FLAGS_CANDIDATES[@]}"; do
  JSON="$(do_query "$f" || true)"
  [[ -z "$JSON" ]] && continue
  ext_count="$(jq -r '.results[0].extensions | length // 0' <<<"$JSON" 2>/dev/null || echo 0)"
  ver_count="$(jq -r '.results[0].extensions[0].versions | length // 0' <<<"$JSON" 2>/dev/null || echo 0)"
  if [[ "$ext_count" -gt 0 && "$ver_count" -gt 1 ]]; then
    USED_FLAGS="$f"; break
  fi
done

if [[ -z "${USED_FLAGS:-}" ]]; then
  echo "ERROR: no pude obtener suficientes versiones para $EXT_ID"
  exit 3
fi

publisher="$(jq -r '.results[0].extensions[0].publisher.publisherName' <<<"$JSON")"
extName="$(jq -r '.results[0].extensions[0].extensionName' <<<"$JSON")"

mapfile -t versions < <(jq -r '.results[0].extensions[0].versions[].version' <<<"$JSON" | sort -V)
latest="${versions[-1]}"
IFS='.' read -r LMAJ LMIN LPAT <<<"$latest"

prev_minor="$(printf '%s\n' "${versions[@]}" \
  | awk -F. -v maj="$LMAJ" -v lmin="$LMIN" '$1==maj && $2<lmin { print $2 }' \
  | sort -n | tail -n 1)"

if [[ -n "$prev_minor" ]]; then
  target="$(printf '%s\n' "${versions[@]}" \
    | awk -F. -v maj="$LMAJ" -v pmin="$prev_minor" '$1==maj && $2==pmin { print }' \
    | sort -V | tail -n 1)"
else
  target="${versions[-2]}"
fi

vsix_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${extName}/${target}/vspackage"
vsix_path="${OUT_DIR}/${publisher}.${extName}-${target}.vsix"

echo "Flags usados: $USED_FLAGS"
echo "Ext:         $EXT_ID"
echo "Publisher:   $publisher"
echo "Name:        $extName"
echo "Latest:      $latest"
echo "Target:      $target"
echo "Download:    $vsix_url"
echo "Output:      $vsix_path"

curl -fL --compressed --retry 3 --retry-delay 1 -o "$vsix_path" "$vsix_url"
echo "OK: descargado"

if [[ "$INSTALL" -eq 1 ]]; then
  if [[ -z "$EDITOR_BIN" ]]; then
    if command -v codium >/dev/null 2>&1; then EDITOR_BIN="codium"
    elif command -v code >/dev/null 2>&1; then EDITOR_BIN="code"
    else echo "ERROR: no encuentro 'codium' ni 'code'. Pasa --bin o EDITOR_BIN=..."; exit 4; fi
  fi
  force_flag=""
  [[ "$FORCE" -eq 1 ]] && force_flag="--force"
  echo "Instalando con: $EDITOR_BIN --install-extension \"$vsix_path\" $force_flag"
  "$EDITOR_BIN" --install-extension "$vsix_path" $force_flag
  echo "OK: instalado"
fi
