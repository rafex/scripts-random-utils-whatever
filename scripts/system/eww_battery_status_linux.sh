#!/usr/bin/env bash
# eww_battery_status_linux.sh v1.0.0
# Emite telemetría de alimentación segura para un defpoll de EWW.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

readonly VERSION="v1.0.0"

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  eww_battery_status_linux.sh
  eww_battery_status_linux.sh --status
  eww_battery_status_linux.sh --check

Emite AC, carga actual, estado y salud estimada para EWW. No usa watch:
EWW ejecuta este helper mediante defpoll cada 10 segundos.
EOF
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal'
}

first_readable() {
  local path
  for path in "$@"; do
    [[ -r "$path" ]] || continue
    printf '%s\n' "$path"
    return 0
  done
  return 1
}

read_file_or_nd() {
  local path="$1" value
  if [[ -r "$path" ]]; then
    IFS= read -r value < "$path" || true
    [[ -n "$value" ]] && printf '%s\n' "$value" || printf 'N/D\n'
  else
    printf 'N/D\n'
  fi
}

find_ac_online() {
  first_readable \
    /sys/class/power_supply/AC*/online \
    /sys/class/power_supply/ADP*/online \
    /sys/class/power_supply/AC/online \
    /sys/class/power_supply/ADP/online || true
}

find_battery_file() {
  local name="$1"
  first_readable /sys/class/power_supply/BAT*/"$name" || true
}

upower_health() {
  local device details health
  command -v upower >/dev/null 2>&1 || { printf 'N/D\n'; return 0; }
  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    details="$(upower -i "$device" 2>/dev/null || true)"
    health="$(awk -F': ' '/^[[:space:]]*capacity:/ { print $2; exit }' <<< "$details")"
    if [[ -n "$health" ]]; then
      printf '%s (estimada)\n' "$health"
      return 0
    fi
  done < <(upower -e 2>/dev/null | awk '/battery/ { print; exit }')
  printf 'N/D\n'
}

print_status() {
  local ac_file battery_capacity battery_status ac_value
  ac_file="$(find_ac_online)"
  battery_capacity="$(find_battery_file capacity)"
  battery_status="$(find_battery_file status)"
  ac_value="$(read_file_or_nd "$ac_file")"
  printf 'AC: %s\n' "$ac_value"
  printf 'Carga: %s\n' "$(read_file_or_nd "$battery_capacity")"
  printf 'Estado: %s\n' "$(read_file_or_nd "$battery_status")"
  printf 'Salud: %s\n' "$(upower_health)"
}

main() {
  case "${1:-}" in
    '') ;;
    --status) ;;
    --check)
      require_linux_user
      printf 'helper=%s\n' "$VERSION"
      [[ -d /sys/class/power_supply ]] && printf 'power_supply=sysfs disponible\n' || printf 'power_supply=N/D\n'
      exit 0
      ;;
    --help|-h) usage; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
  [[ $# -le 1 ]] || die 'solo se admite una opción'
  require_linux_user
  print_status
}

main "$@"
