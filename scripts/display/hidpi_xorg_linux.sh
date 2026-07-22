#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hidpi_xorg_linux.sh
# Detecta la resolución y DPI del monitor conectado y ajusta el escalado
# de Xorg (xrandr --scale) y Xft.dpi en ~/.Xresources.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

MIN_DPI=72
MAX_DPI=90
DEFAULT_DPI=84

choose_scale_by_res() {
  local w="$1" h="$2"
  if (( w >= 3800 || h >= 2100 )); then echo "0.5"; return; fi
  if (( w >= 3000 )); then echo "0.666"; return; fi
  if (( w >= 2500 )); then echo "0.75"; return; fi
  echo "1.0"
}

dpi_for_scale() {
  local scale="$1" dpi
  case "$scale" in
    0.5)   dpi=90  ;;
    0.666) dpi=88  ;;
    0.75)  dpi=84  ;;
    1.0)   dpi=76  ;;
    *)     dpi="$DEFAULT_DPI" ;;
  esac
  (( dpi < MIN_DPI )) && dpi="$MIN_DPI"
  (( dpi > MAX_DPI )) && dpi="$MAX_DPI"
  echo "$dpi"
}

get_output_info() {
  local out="$1" mode w h wmm hmm conn_line mm_line

  mode="$(xrandr | awk -v o="$out" '
    $1==o && $2=="connected" {inside=1; next}
    inside && /\*/ {print $1; exit}
    inside && $1 ~ /^[A-Z0-9-]+$/ {exit}
  ' 2>/dev/null || true)"

  if [[ -n "${mode:-}" ]]; then
    w="${mode%x*}"
    h="${mode#*x}"
  fi

  conn_line="$(xrandr | awk -v o="$out" '$1==o && $2=="connected"{print; exit}' 2>/dev/null || true)"

  if [[ -n "${conn_line:-}" ]] && echo "$conn_line" | grep -qE '[0-9]+mm x [0-9]+mm'; then
    wmm="$(echo "$conn_line" | grep -oE '[0-9]+mm x [0-9]+mm' | awk '{print $1}' | sed 's/mm//')"
    hmm="$(echo "$conn_line" | grep -oE '[0-9]+mm x [0-9]+mm' | awk '{print $3}' | sed 's/mm//')"
  else
    mm_line="$(xrandr --verbose | awk -v o="$out" '
      $1==o {inside=1}
      inside && /mm x/ {print; exit}
      inside && $1 ~ /^[A-Z0-9-]+$/ && $1!=o {exit}
    ' 2>/dev/null || true)"

    if [[ -n "${mm_line:-}" ]] && echo "$mm_line" | grep -qE '[0-9]+mm x [0-9]+mm'; then
      wmm="$(echo "$mm_line" | grep -oE '[0-9]+mm x [0-9]+mm' | awk '{print $1}' | sed 's/mm//')"
      hmm="$(echo "$mm_line" | grep -oE '[0-9]+mm x [0-9]+mm' | awk '{print $3}' | sed 's/mm//')"
    fi
  fi

  echo "${w:-} ${h:-} ${wmm:-} ${hmm:-}"
}

calc_dpi() {
  local wpx="$1" wmm="$2"
  if [[ -z "$wpx" || -z "$wmm" || "$wmm" == "0" ]] || ! [[ "$wpx" =~ ^[0-9]+$ && "$wmm" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo ""
    return
  fi
  python3 - <<PY
wpx=int("$wpx")
wmm=float("$wmm")
dpi = (wpx*25.4)/wmm
print(int(round(dpi)))
PY
}

# ── Main ──
if ! command -v xrandr >/dev/null 2>&1; then
  echo "ERROR: xrandr no está instalado."
  exit 1
fi

mapfile -t outputs < <(xrandr | awk '$2=="connected"{print $1}')
[[ ${#outputs[@]} -eq 0 ]] && { echo "No hay outputs conectados."; exit 0; }

target=""
for o in "${outputs[@]}"; do
  if [[ "$o" == HDMI* || "$o" == DP* || "$o" == DVI* ]]; then
    target="$o"; break
  fi
done
[[ -z "$target" ]] && target="${outputs[0]}"

read -r w h wmm hmm < <(get_output_info "$target")

scale="1.0"
dpi="$DEFAULT_DPI"
dpi_measured="$(calc_dpi "${w:-}" "${wmm:-}")"

if [[ -n "${dpi_measured:-}" ]]; then
  if (( dpi_measured >= 180 )); then scale="0.5"
  elif (( dpi_measured >= 145 )); then scale="0.666"
  elif (( dpi_measured >= 125 )); then scale="0.75"
  else scale="1.0"; fi
else
  if [[ -n "${w:-}" && -n "${h:-}" ]]; then
    scale="$(choose_scale_by_res "$w" "$h")"
  fi
fi

dpi="$(dpi_for_scale "$scale")"

echo "Target: $target"
echo "Modo: ${w:-?}x${h:-?}  mm: ${wmm:-?}x${hmm:-?}  DPI_medido: ${dpi_measured:-N/A}"
echo "Aplicando: scale=$scale  Xft.dpi=$dpi"

xrandr --output "$target" --scale "${scale}x${scale}"

XRES="$HOME/.Xresources"
if [[ -f "$XRES" ]]; then
  if grep -qE '^\s*Xft\.dpi:' "$XRES"; then
    sed -i.bak -E "s/^\s*Xft\.dpi:\s*[0-9]+/Xft.dpi: ${dpi}/" "$XRES"
  else
    printf "\nXft.dpi: %s\n" "$dpi" >> "$XRES"
  fi
else
  cat > "$XRES" <<EOF
Xft.dpi: ${dpi}
Xft.antialias: true
Xft.hinting: true
Xft.hintstyle: hintslight
Xft.rgba: rgb
EOF
fi

xrdb -merge "$XRES" || true
echo "OK."
