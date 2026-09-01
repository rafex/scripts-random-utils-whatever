#!/usr/bin/env bash
# shellcheck shell=bash
# Genera estados seguros y compactos para el panel Conky de la ThinkPad.
set -Eeuo pipefail
umask 077

export LC_ALL=C

SECTION="all"

usage() {
  cat <<'EOF'
Uso:
  conky_status_linux.sh
  conky_status_linux.sh --section <all|network|power|temperature|audio|lab|security>
  conky_status_linux.sh --network|--power|--temperature|--audio|--lab|--security
  conky_status_linux.sh --check
EOF
}

has_command() { command -v "$1" >/dev/null 2>&1; }
trim() { awk '{$1=$1; print}'; }

network_status() {
  local wifi_state="" wifi_device="" wwan_state="" signal="" quality=""
  if ! has_command nmcli; then printf 'Red: N/D\n'; return 0; fi
  wifi_device="$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null |
    awk -F: '$2 == "wifi" {print $1; exit}' || true)"
  wifi_state="$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null |
    awk -F: '$2 == "wifi" {print $3; exit}' || true)"
  wwan_state="$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null |
    awk -F: '$2 == "gsm" {print $3; exit}' || true)"
  if [[ -n "$wifi_device" && -r /proc/net/wireless ]]; then
    quality="$(awk -v interface="$wifi_device" '$1 == interface ":" {gsub(/[.]/, "", $3); print $3; exit}' /proc/net/wireless || true)"
    if [[ "$quality" =~ ^[0-9]+$ ]]; then
      signal="$(awk -v quality="$quality" 'BEGIN {value = int((quality * 100) / 70); if (value > 100) value = 100; print value}')"
    fi
  fi
  if [[ "$wifi_state" == connected ]]; then
    if [[ "$signal" =~ ^[0-9]+$ ]]; then
      printf 'Wi-Fi: conectado (%s%%)\n' "$signal"
    else
      printf 'Wi-Fi: conectado (señal N/D)\n'
    fi
  else
    printf 'Wi-Fi: %s\n' "${wifi_state:-desconectado}"
  fi
  if [[ "$wwan_state" == connected ]]; then
    printf 'WWAN: conectada (respaldo)\n'
  else
    printf 'WWAN: %s\n' "${wwan_state:-desconectada}"
  fi
  if [[ "$wifi_state" == connected ]]; then
    printf 'Ruta preferida: Wi-Fi → WWAN\n'
  elif [[ "$wwan_state" == connected ]]; then
    printf 'Ruta activa: WWAN\n'
  else
    printf 'Ruta: N/D\n'
  fi
}

tlp_thresholds() {
  local battery start_threshold stop_threshold tlp_output
  shopt -s nullglob
  for battery in /sys/class/power_supply/BAT*; do
    start_threshold="$(cat "$battery/charge_control_start_threshold" 2>/dev/null || true)"
    stop_threshold="$(cat "$battery/charge_control_end_threshold" 2>/dev/null || true)"
    if [[ "$start_threshold" =~ ^[0-9]+$ && "$stop_threshold" =~ ^[0-9]+$ ]]; then
      shopt -u nullglob
      printf '%s/%s\n' "$start_threshold" "$stop_threshold"
      return 0
    fi
  done
  shopt -u nullglob
  if has_command tlp-stat; then
    tlp_output="$(tlp-stat -b 2>/dev/null || true)"
    start_threshold="$(printf '%s\n' "$tlp_output" | awk -F= '/charge_control_start_threshold/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
    stop_threshold="$(printf '%s\n' "$tlp_output" | awk -F= '/charge_control_end_threshold/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
    if [[ "$start_threshold" =~ ^[0-9]+$ && "$stop_threshold" =~ ^[0-9]+$ ]]; then
      printf '%s/%s\n' "$start_threshold" "$stop_threshold"
      return 0
    fi
  fi
  return 1
}

read_battery_sysfs() {
  local battery capacity status thresholds
  shopt -s nullglob
  for battery in /sys/class/power_supply/BAT*; do
    [[ -r "$battery/capacity" ]] || continue
    capacity="$(cat "$battery/capacity" 2>/dev/null || true)"
    status="$(cat "$battery/status" 2>/dev/null || true)"
    printf 'Batería: %s%% (%s)\n' "${capacity:-N/D}" "${status:-N/D}"
    if thresholds="$(tlp_thresholds)"; then printf 'TLP: %s\n' "$thresholds"; else printf 'TLP: N/D\n'; fi
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  return 1
}

power_status() {
  local battery_device="" details percentage state rate thresholds ac_device
  if has_command upower; then
    battery_device="$(upower -e 2>/dev/null | awk '/battery/ {print; exit}' || true)"
    if [[ -n "$battery_device" ]]; then
      details="$(upower -i "$battery_device" 2>/dev/null || true)"
      percentage="$(printf '%s\n' "$details" | awk -F: '/percentage:/ {print $2; exit}' | trim)"
      state="$(printf '%s\n' "$details" | awk -F: '/state:/ {print $2; exit}' | trim)"
      rate="$(printf '%s\n' "$details" | awk -F: '/energy-rate:/ {print $2; exit}' | trim)"
      printf 'Batería: %s (%s)\n' "${percentage:-N/D}" "${state:-N/D}"
      printf 'Consumo: %s\n' "${rate:-N/D}"
    elif ! read_battery_sysfs; then
      printf 'Batería: N/D\nTLP: N/D\n'
    fi
  elif ! read_battery_sysfs; then
    printf 'Batería: N/D\nTLP: N/D\n'
  fi
  if thresholds="$(tlp_thresholds)"; then printf 'TLP: %s\n' "$thresholds"; else printf 'TLP: N/D\n'; fi
  shopt -s nullglob
  for ac_device in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
    [[ -r "$ac_device/online" ]] || continue
    if [[ "$(cat "$ac_device/online" 2>/dev/null || true)" == 1 ]]; then
      printf 'Fuente: AC\n'
    else
      printf 'Fuente: batería\n'
    fi
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  printf 'Fuente: N/D\n'
}

valid_temperature() {
  local value="$1"
  [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v value="$value" 'BEGIN {exit !(value >= -50 && value <= 150)}'
}

temperature_status() {
  local output cpu_temp nvme_temp
  if ! has_command sensors; then printf 'CPU: N/D | NVMe: N/D\n'; return 0; fi
  output="$(sensors 2>/dev/null || true)"
  cpu_temp="$(printf '%s\n' "$output" | awk '
    function first_temp( i, value) {
      for (i = 1; i <= NF; i++) {
        value = $i; gsub(/[+°C]/, "", value)
        if (value ~ /^-?[0-9]+([.][0-9]+)?$/ && value >= -50 && value <= 150) return value
      }
      return "N/D"
    }
    /Package id 0:/ && (cpu == "" || cpu == "N/D") {cpu = first_temp()}
    /^Core 0:/ && (cpu == "" || cpu == "N/D") {cpu = first_temp()}
    END {print (cpu == "" ? "N/D" : cpu)}')"
  nvme_temp="$(printf '%s\n' "$output" | awk '
    function first_temp( i, value) {
      for (i = 1; i <= NF; i++) {
        value = $i; gsub(/[+°C]/, "", value)
        if (value ~ /^-?[0-9]+([.][0-9]+)?$/ && value >= -50 && value <= 150) return value
      }
      return "N/D"
    }
    /Composite:/ && (nvme == "" || nvme == "N/D") {nvme = first_temp()}
    END {print (nvme == "" ? "N/D" : nvme)}')"
  [[ "$cpu_temp" == N/D ]] || valid_temperature "$cpu_temp" || cpu_temp=N/D
  [[ "$nvme_temp" == N/D ]] || valid_temperature "$nvme_temp" || nvme_temp=N/D
  printf 'CPU: %s°C | NVMe: %s°C\n' "$cpu_temp" "$nvme_temp"
}

audio_status() {
  local volume muted
  if ! has_command wpctl; then printf 'Audio: N/D\n'; return 0; fi
  volume="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null |
    awk '{for (i = 1; i <= NF; i++) if ($i ~ /^0[.][0-9]+$/) {printf "%d", $i * 100; exit}}' || true)"
  muted="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null |
    awk '/MUTED/ {print "mute"; exit}' || true)"
  if [[ "$volume" =~ ^[0-9]+$ ]]; then
    printf 'Audio: %s%% (%s)\n' "$volume" "${muted:-activo}"
  else
    printf 'Audio: N/D\n'
  fi
}

lab_status() {
  local kvm="no" vm_count="N/D" podman_count="N/D" runtimes=() runtime
  if [[ -e /dev/kvm ]]; then
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then kvm="sí"; else kvm="N/D"; fi
  fi
  if has_command virsh; then
    vm_count="$(virsh -c qemu:///session list --name --state-running 2>/dev/null |
      sed '/^[[:space:]]*$/d' | wc -l | trim || true)"
  fi
  if has_command podman; then
    podman_count="$(podman ps -q 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | trim || true)"
  fi
  for runtime in java node mvn gradle; do has_command "$runtime" && runtimes+=("$runtime"); done
  printf 'KVM: %s | VMs activas: %s\n' "$kvm" "$vm_count"
  printf 'Podman: %s contenedor(es) | runtimes: %s\n' "$podman_count" "${runtimes[*]:-N/D}"
}

service_state() { systemctl is-active --quiet "$1" 2>/dev/null && printf 'activo' || printf 'N/D'; }

security_status() {
  local ufw_state="N/D"
  if has_command ufw && [[ "$(/usr/sbin/ufw status 2>/dev/null || true)" == *"Status: active"* ]]; then ufw_state="activo"; fi
  printf 'Seguridad: UFW %s | Fail2ban %s\n' "$ufw_state" "$(service_state fail2ban.service)"
  printf 'AppArmor %s | auditd %s | USBGuard %s\n' \
    "$(service_state apparmor.service)" "$(service_state auditd.service)" "$(service_state usbguard.service)"
  printf 'ClamAV %s\n' "$(service_state clamav-daemon.service)"
}

check_status() {
  local command_name
  printf '═══ Dependencias Conky ═══\n'
  for command_name in nmcli upower sensors wpctl virsh podman systemctl ufw; do
    if has_command "$command_name"; then printf '✓ %s\n' "$command_name"; else printf '⚠ %s no disponible\n' "$command_name"; fi
  done
  printf 'DISPLAY=%s\n' "${DISPLAY:-ausente}"
  printf 'Conky no se inicia desde este diagnóstico.\n'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section) [[ $# -ge 2 ]] || { echo '--section requiere un valor' >&2; exit 2; }; SECTION="$2"; shift 2 ;;
      --network|--power|--temperature|--audio|--lab|--security) SECTION="${1#--}"; shift ;;
      --all) SECTION=all; shift ;;
      --check) SECTION=check; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

main() {
  parse_args "$@"
  case "$SECTION" in
    check) check_status ;;
    network) network_status ;;
    power) power_status ;;
    temperature) temperature_status ;;
    audio) audio_status ;;
    lab) lab_status ;;
    security) security_status ;;
    all) network_status; power_status; temperature_status; audio_status; lab_status; security_status ;;
    *) echo "sección desconocida: $SECTION" >&2; exit 2 ;;
  esac
}

main "$@"
