#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# update_copilot_chat_linux.sh
# Descarga la penúltima versión minor de GitHub Copilot Chat (.vsix) desde
# el Marketplace de VS Code. Opcionalmente instala con codium/code.
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
  ./update_copilot_chat_linux.sh [--install] [--no-force] [--out DIR] [--bin codium|code]

Variables (opcionales):
  OUT_DIR=./vsix
  INSTALL=0|1
  FORCE=0|1
  EDITOR_BIN=codium|code|/ruta/al/binario
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
need curl; need jq; need sort

mkdir -p "$OUT_DIR"

PAYLOAD=$(jq -nc --arg ext "$EXT_ID" '{
  filters: [{ criteria: [{ filterType: 7, value: $ext }] }],
  flags: 914
}')

JSON="$(curl -fsSL \
  -H "Accept: application/json;api-version=${API_VER}" \
  -H "Content-Type: application/json" \
  --data-raw "$PAYLOAD" \
  "$MARKETPLACE_QUERY_URL")"

publisher="$(jq -r '.results[0].extensions[0].publisher.publisherName' <<<"$JSON")"
extName="$(jq -r '.results[0].extensions[0].extensionName' <<<"$JSON")"

mapfile -t versions < <(jq -r '.results[0].extensions[0].versions[].version' <<<"$JSON" | sort -V)
[[ ${#versions[@]} -lt 2 ]] && { echo "ERROR: no pude obtener suficientes versiones para $EXT_ID"; exit 3; }

latest="${versions[-1]}"
IFS='.' read -r LMAJ LMIN LPAT <<<"$latest"

prev_minor="$(printf '%s\n' "${versions[@]}" \
  | awk -F. -v maj="$LMAJ" -v lmin="$LMIN" '$1==maj && $2<lmin { print $2 }' \
  | sort -n | tail -n 1)"

target=""
if [[ -n "$prev_minor" ]]; then
  target="$(printf '%s\n' "${versions[@]}" \
    | awk -F. -v maj="$LMAJ" -v pmin="$prev_minor" '$1==maj && $2==pmin { print }' \
    | sort -V | tail -n 1)"
else
  target="${versions[-2]}"
fi

vsix_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${extName}/${target}/vspackage"
vsix_path="${OUT_DIR}/${publisher}.${extName}-${target}.vsix"

echo "Ext:        $EXT_ID"
echo "Publisher:   $publisher"
echo "Name:        $extName"
echo "Latest:      $latest"
echo "Target:      $target"
echo "Download:    $vsix_url"
echo "Output:      $vsix_path"

curl -fL --retry 3 --retry-delay 1 -o "$vsix_path" "$vsix_url"
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
