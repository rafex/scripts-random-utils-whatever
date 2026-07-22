#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wifi_toggle_interface_linux.sh
# Alterna entre WiFi interno y USB de forma interactiva.
# Útil en laptops con doble interfaz WiFi (ej. Broadcom interna + adaptador USB).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
die() { echo -e "${R}Error:${N} $*" >&2; exit 1; }

IFACES=($(nmcli -t -f TYPE,DEVICE device status | awk -F: '$1=="wifi"{print $2}'))
[[ ${#IFACES[@]} -lt 2 ]] && die "Se necesita más de una interfaz WiFi para alternar."

echo -e "${Y}Interfaces WiFi detectadas:${N}"
for iface in "${IFACES[@]}"; do
  driver=$(basename "$(readlink /sys/class/net/"$iface"/device/driver 2>/dev/null)" 2>/dev/null || echo "?")
  bus=$(readlink /sys/class/net/"$iface"/device 2>/dev/null | grep -q pci && echo "PCI" || echo "USB")
  echo -e "  ${B}$iface${N}  driver=${driver}  bus=${bus}"
done

echo -e "\n${Y}1)${N} Apagar WiFi interno, encender USB"
echo -e "${Y}2)${N} Apagar WiFi USB, encender interno"
echo -e "${Y}3)${N} Solo apagar WiFi interno"
echo -e "${Y}4)${N} Solo encender WiFi interno"
echo -e "${Y}5)${N} Mostrar estado"
read -rp $'Seleccioná: ' OPC

is_internal() {
  local d
  d=$(basename "$(readlink /sys/class/net/"$1"/device/driver 2>/dev/null)" 2>/dev/null || echo "")
  [[ "$d" == "wl" || "$d" == "b43" || "$d" == "brcmfmac" || "$d" == "iwlwifi" ]]
}

off_internal() {
  for iface in "${IFACES[@]}"; do
    if is_internal "$iface"; then
      echo -e "${R}→${N} Apagando interno ${B}$iface${N}..."
      nmcli device disconnect "$iface" 2>/dev/null || true
      nmcli device set "$iface" managed no 2>/dev/null || true
    fi
  done
}

on_internal() {
  for iface in "${IFACES[@]}"; do
    if is_internal "$iface"; then
      echo -e "${G}→${N} Encendiendo interno ${B}$iface${N}..."
      nmcli device set "$iface" managed yes 2>/dev/null || true
    fi
  done
}

case "$OPC" in
  1)
    off_internal
    for iface in "${IFACES[@]}"; do
      if ! is_internal "$iface"; then
        echo -e "${G}→${N} Asegurando externo ${B}$iface${N}..."
        nmcli device set "$iface" managed yes 2>/dev/null || true
      fi
    done
    ;;
  2)
    on_internal
    for iface in "${IFACES[@]}"; do
      if ! is_internal "$iface"; then
        echo -e "${R}→${N} Apagando externo ${B}$iface${N}..."
        nmcli device disconnect "$iface" 2>/dev/null || true
        nmcli device set "$iface" managed no 2>/dev/null || true
      fi
    done
    ;;
  3) off_internal ;;
  4) on_internal ;;
  5)
    nmcli -f DEVICE,TYPE,STATE device status 2>/dev/null | grep -E "wifi|DEVICE"
    exit 0
    ;;
  *) die "Opción inválida" ;;
esac

echo -e "\n${G}✓${N} Estado actual:"
nmcli -f DEVICE,TYPE,DRIVER,STATE device status 2>/dev/null | grep wifi
