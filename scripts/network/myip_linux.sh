#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# myip_linux.sh
# Obtiene la IP pública desde múltiples servicios y muestra consistencia.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'

SITES=(
  "https://ifconfig.me/ip"
  "https://icanhazip.com"
  "https://api.ipify.org"
  "https://checkip.amazonaws.com"
  "https://ident.me"
  "https://ip.sb"
  "https://ipinfo.io/ip"
)

echo -e "${B}IP pública desde varios servicios:${N}"
echo

first=""
declare -a results

for url in "${SITES[@]}"; do
  ip=$(curl -s4 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || echo "—")
  results+=("$ip")
  if [[ -z "$first" && "$ip" != "—" ]]; then
    first="$ip"
  fi
  echo -e "  $(printf '%-40s' "$url") ${G}$ip${N}"
done

echo
echo -e "${B}Resumen:${N}"

if [[ -n "$first" ]]; then
  all_same=true
  for ip in "${results[@]}"; do
    [[ "$ip" != "—" && "$ip" != "$first" ]] && all_same=false
  done
  if $all_same; then
    echo -e "  IP: ${G}$first${N} (consistente en todos los servicios)"
  else
    echo -e "  ${Y}⚠ IPs divergentes${N}"
    for i in "${!SITES[@]}"; do
      [[ "${results[$i]}" != "—" ]] && echo -e "    ${SITES[$i]}: ${results[$i]}"
    done
  fi
else
  echo -e "  ${R}No se pudo obtener IP de ningún servicio.${N}"
fi
