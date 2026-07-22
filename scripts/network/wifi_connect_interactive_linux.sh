#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wifi_connect_interactive_linux.sh
# Conecta a una red WiFi con selección interactiva de red e interfaz.
# Soporta modo directo con flags -s (SSID) y -b (BSSID).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
die() { echo -e "${R}Error:${N} $*" >&2; exit 1; }

usage() {
  echo -e "Uso: $0 [-i <iface>] [-s <ssid> | -b <bssid>]"
  echo "  -i|--iface <iface>  Interfaz WiFi (defecto: primera encontrada)"
  echo "  -s|--ssid  <ssid>   Conectar directo al SSID (usa \$WIFI_PASS)"
  echo "  -b|--bssid <mac>    Conectar directo al BSSID (usa \$WIFI_PASS)"
  echo "  -h|--help           Esta ayuda"
  echo
  echo "Sin flags: modo interactivo con lista de redes."
  echo "Con -s/-b: la variable de entorno WIFI_PASS se usa como contraseña."
  exit 0
}

run_nmcli() {
  if [[ "$(id -u)" -eq 0 ]]; then
    nmcli "$@"
  elif nmcli "$@" 2>/dev/null; then
    return 0
  elif command -v sudo &>/dev/null; then
    if sudo -n true 2>/dev/null || [[ -t 0 ]]; then sudo nmcli "$@"
    else pkexec nmcli "$@"; fi
  else
    pkexec nmcli "$@"
  fi
}

IFACE_ARG=""; SSID_ARG=""; BSSID_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--iface) IFACE_ARG="$2"; shift 2 ;;
    -s|--ssid)  SSID_ARG="$2";  shift 2 ;;
    -b|--bssid) BSSID_ARG="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) die "Flag desconocido: $1 (usa -h para ayuda)" ;;
  esac
done

IFACES=($(nmcli -t -f TYPE,DEVICE device status | awk -F: '$1=="wifi"{print $2}'))
[[ ${#IFACES[@]} -eq 0 ]] && die "No se encontraron interfaces WiFi."

if [[ -n "$IFACE_ARG" ]]; then
  IFACE="$IFACE_ARG"
  [[ " ${IFACES[*]} " == *" $IFACE "* ]] || die "Interfaz $IFACE no existe."
elif [[ ${#IFACES[@]} -eq 1 ]]; then
  IFACE="${IFACES[0]}"
else
  echo -e "${Y}Interfaces WiFi disponibles:${N}"
  for i in "${!IFACES[@]}"; do
    echo -e "  ${B}$((i+1)))${N} ${IFACES[$i]}"
  done
  read -rp $'\nSelecciona interfaz [1-'"${#IFACES[@]}"$']: ' SEL
  [[ "$SEL" =~ ^[0-9]+$ ]] && SEL=$((SEL-1)) || die "Número inválido"
  [[ -n "${IFACES[$SEL]:-}" ]] || die "Selección inválida"
  IFACE="${IFACES[$SEL]}"
fi

MNM=$(nmcli -g GENERAL.NM-MANAGED device show "$IFACE" 2>/dev/null)
if [[ "$MNM" != "sí" && "$MNM" != "yes" ]]; then
  echo -e "${Y}→${N} Habilitando gestión de ${B}$IFACE${N}..."
  run_nmcli device set "$IFACE" managed yes
fi

# ─────────────────────────────────────────────────────────────────────────────
# Conectar: prefiere connection up si el perfil ya existe, para evitar el
# bug key-mgmt de nmcli al crear perfiles duplicados con device wifi connect.
# ─────────────────────────────────────────────────────────────────────────────
wifi_connect() {
  local target="$1" pass="${2:-}" args=("${@:3}")

  local current
  current=$(nmcli -t -f GENERAL.CONNECTION device show "$IFACE" 2>/dev/null | awk -F: '{print $2}')
  if [[ -n "$current" ]]; then
    local current_ssid
    current_ssid=$(nmcli -t -f 802-11-wireless.ssid connection show id "$current" 2>/dev/null | awk -F: '{print $2}')
    if [[ "$current_ssid" == "$target" ]]; then
      echo -e "  ${G}✓${N} Ya conectado a ${B}${target}${N} (perfil ${B}${current}${N})"
      return 0
    fi
  fi

  local existing
  while IFS=: read -r conn_name conn_type; do
    [[ "$conn_type" == "802-11-wireless" ]] || continue
    local conn_ssid
    conn_ssid=$(nmcli -t -f 802-11-wireless.ssid connection show id "$conn_name" 2>/dev/null \
      | awk -F: '{print $2}')
    if [[ "$conn_ssid" == "$target" ]]; then
      existing="$conn_name"
      break
    fi
  done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)

  if [[ -n "$existing" ]]; then
    echo -e "  ${Y}ℹ${N} Perfil existente: ${B}${existing}${N}, reconectando..."
    if [[ -n "$pass" ]]; then
      nmcli connection modify "$existing" wifi-sec.psk "$pass" 2>/dev/null || true
    fi
    local profile_iface
    profile_iface=$(nmcli -t -f connection.interface-name connection show id "$existing" 2>/dev/null | awk -F: '{print $2}')
    if [[ -n "$profile_iface" && "$profile_iface" != "$IFACE" ]]; then
      nmcli connection modify "$existing" connection.interface-name "$IFACE" 2>/dev/null || true
    fi
    run_nmcli connection up "$existing"
    local real_iface
    real_iface=$(nmcli -t -f DEVICE connection show --active 2>/dev/null | awk -F: -v n="$existing" '$1==n{print $2; exit}')
    IFACE="${real_iface:-$IFACE}"
    return
  fi

  if [[ -n "$pass" ]]; then
    run_nmcli device wifi connect "$target" password "$pass" "${args[@]}"
  else
    run_nmcli device wifi connect "$target" "${args[@]}"
  fi
}

# ── MODO DIRECTO ──
if [[ -n "$SSID_ARG" || -n "$BSSID_ARG" ]]; then
  CONN_ARGS=(ifname "$IFACE")
  [[ -n "$BSSID_ARG" ]] && CONN_ARGS+=(bssid "$BSSID_ARG")
  TARGET="${SSID_ARG:-$BSSID_ARG}"
  SEC=$(nmcli -t -f SSID,SECURITY device wifi list ifname "$IFACE" 2>/dev/null | awk -F: -v s="$TARGET" '$1==s{print $2; exit}')
  if [[ "$SEC" != *"ninguno"* && -n "$SEC" ]]; then
    [[ -z "${WIFI_PASS:-}" ]] && die "Variable WIFI_PASS no está definida y la red requiere contraseña."
    wifi_connect "$TARGET" "$WIFI_PASS" "${CONN_ARGS[@]}"
  else
    wifi_connect "$TARGET" "" "${CONN_ARGS[@]}"
  fi
  echo -e "\n${G}✓${N} Conectado a ${B}$TARGET${N} por ${B}$IFACE${N}"
  exit 0
fi

# ── MODO INTERACTIVO ──
echo -e "${G}→${N} Escaneando redes en ${B}$IFACE${N}..."
echo -e "\n${Y}Redes disponibles:${N}"
printf "  %-3s  %-17s  %-24s  %-6s  %-18s  %s\n" "Nº" "BSSID" "SSID" "Banda" "Seguridad" "Señal"
echo "  ---  -----------------  -------------------------  ------  ------------------  -----"

declare -a AP_BSSID AP_SSID AP_SIGNAL AP_SECURITY AP_BAND

i=0; _b=""; _s=""; _sig=""; _sec=""; _ch=""

flush_ap() {
  [[ -z "$_s" ]] && return
  [[ "$_s" == "--" ]] && _s=""
  local band="2.4GHz"
  [[ "$_ch" -ge 36 ]] 2>/dev/null && band="5GHz"
  i=$((i+1))
  AP_BSSID+=("$_b"); AP_SSID+=("$_s"); AP_SIGNAL+=("$_sig"); AP_SECURITY+=("${_sec:---}"); AP_BAND+=("$band")
  printf "  %-3d  %-17s  %-24s  %-6s  %-18s  %s%%\n" "$i" "$_b" "${_s:-(oculta)}" "$band" "${_sec:---}" "$_sig"
}

while IFS= read -r line; do
  case "$line" in
    BSSID:*)   [[ -n "$_b" ]] && flush_ap; read -r _ _b <<< "$line" ;;
    SSID:*)    read -r _ _s <<< "$line" ;;
    SIGNAL:*)  read -r _ _sig <<< "$line" ;;
    SECURITY:*) read -r _ _sec <<< "$line" ;;
    CHAN:*)    read -r _ _ch <<< "$line" ;;
  esac
done < <(nmcli -m multiline -f BSSID,SSID,SIGNAL,SECURITY,CHAN device wifi list ifname "$IFACE" 2>/dev/null)
flush_ap

[[ $i -eq 0 ]] && die "No se encontraron redes."
TOTAL=$i

read -rp $'\nSelecciona red por número, o escribe SSID/BSSID: ' SEL_RED
BSSID_SEL=""; SSID_SEL=""
if [[ "$SEL_RED" =~ ^[0-9]+$ ]]; then
  [[ "$SEL_RED" -ge 1 && "$SEL_RED" -le "$TOTAL" ]] || die "Número inválido"
  idx=$((SEL_RED-1))
  BSSID_SEL="${AP_BSSID[$idx]}"; SSID_SEL="${AP_SSID[$idx]}"
elif [[ "$SEL_RED" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
  BSSID_SEL="${SEL_RED^^}"
  for j in "${!AP_BSSID[@]}"; do
    [[ "${AP_BSSID[$j]^^}" == "$BSSID_SEL" ]] && { SSID_SEL="${AP_SSID[$j]}"; break; }
  done
else
  SSID_SEL="$SEL_RED"
fi
[[ -n "$BSSID_SEL" && -z "$SSID_SEL" ]] && SSID_SEL="$BSSID_SEL"

SEC=""
[[ -n "$BSSID_SEL" ]] && for j in "${!AP_BSSID[@]}"; do
  [[ "${AP_BSSID[$j]^^}" == "${BSSID_SEL^^}" ]] && { SEC="${AP_SECURITY[$j]}"; break; }
done
[[ -z "$SEC" ]] && for j in "${!AP_SSID[@]}"; do
  [[ "${AP_SSID[$j]}" == "$SSID_SEL" ]] && { SEC="${AP_SECURITY[$j]}"; break; }
done

CONN_ARGS=(ifname "$IFACE")
[[ -n "$BSSID_SEL" ]] && CONN_ARGS+=(bssid "$BSSID_SEL")

if [[ "$SEC" != "--" && "$SEC" != *"ninguno"* && -n "$SEC" ]]; then
  if [[ -n "${WIFI_PASS:-}" ]]; then
    wifi_connect "$SSID_SEL" "$WIFI_PASS" "${CONN_ARGS[@]}"
  else
    read -rsp $'Contraseña de la red: ' PASS; echo
    [[ -z "$PASS" ]] && die "La contraseña no puede estar vacía."
    wifi_connect "$SSID_SEL" "$PASS" "${CONN_ARGS[@]}"
  fi
else
  wifi_connect "$SSID_SEL" "" "${CONN_ARGS[@]}"
fi

LABEL="$SSID_SEL"
[[ -n "$BSSID_SEL" ]] && LABEL="$SSID_SEL ($BSSID_SEL)"
echo -e "\n${G}✓${N} Conectado a ${B}$LABEL${N} por ${B}$IFACE${N}"
