#!/usr/bin/env bash
# v1.0.0 — Suspensión por tapa, sin reiniciar logind.
set -euo pipefail
action=check
docked=suspend
chosen=false
target=/etc/systemd/logind.conf.d/90-rafex-lid-suspend.conf
marker='# Managed by rafex configure_lid_suspend_linux.sh'
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
render() {
  printf '%s\n' "$marker" '[Login]' 'HandleLidSwitch=suspend' \
    'HandleLidSwitchExternalPower=suspend' "HandleLidSwitchDocked=$docked" 'LidSwitchIgnoreInhibited=no'
}
while (( $# )); do
  case "$1" in
    --check|--plan|--status|--apply)
      [[ "$chosen" == false ]] || die 'Selecciona una sola acción'
      chosen=true; action=${1#--}; shift ;;
    --docked)
      [[ $# -ge 2 ]] || die 'Falta suspend o ignore'
      docked=$2
      [[ "$docked" == suspend || "$docked" == ignore ]] || die 'Dock: suspend o ignore'
      shift 2 ;;
    --help|-h)
      printf '%s\n' 'Uso: configure_lid_suspend_linux.sh --check|--plan|--status|--apply [--docked suspend|ignore]'
      exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
done
[[ "$(uname -s)" == Linux && -d /run/systemd/system ]] || die 'Requiere Linux con systemd'
for tool in systemctl systemd-analyze systemd-inhibit awk; do
  command -v "$tool" >/dev/null || die "Falta $tool"
done
printf 'Suspensión anunciada por el kernel: '
cat /sys/power/state
grep -qw mem /sys/power/state || die 'El kernel no anuncia suspensión mem'
systemctl is-active --quiet systemd-logind || die 'logind no está activo'
[[ ! -L /etc/systemd/logind.conf.d && ! -L "$target" ]] || die 'Ruta enlazada no admitida'
if [[ -e "$target" ]]; then
  [[ -f "$target" ]] || die 'Destino no regular'
  grep -qxF "$marker" "$target" || die 'Configuración no administrada en el destino'
fi
config=$(systemd-analyze cat-config systemd/logind.conf)
printf '%s\n' 'Política propuesta (pendiente de reinicio manual):'
render
printf '\nInhibidores actuales:\n'
systemd-inhibit --list --no-pager || true
printf '\nOpciones de tapa en disco:\n'
printf '%s\n' "$config" | awk '/^# \// {source=$0} /^[[:space:]]*(HandleLidSwitch|HandleLidSwitchExternalPower|HandleLidSwitchDocked|LidSwitchIgnoreInhibited)[[:space:]]*=/ {print source; print}'
[[ "$action" != status ]] || exit 0
conflicts=$(printf '%s\n' "$config" | awk -v own="$target" -v dock="$docked" '
  /^# \// {source=substr($0,3); section=""; next}
  /^[[:space:]]*\[/ {section=$0; gsub(/[[:space:]]/, "", section); next}
  section == "[Login]" && source != own {
    line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    n=split(line,a,"="); key=a[1]; gsub(/[[:space:]]/, "", key)
    expected=""
    if (key=="HandleLidSwitch" || key=="HandleLidSwitchExternalPower") expected="suspend"
    if (key=="HandleLidSwitchDocked") expected=dock
    if (key=="LidSwitchIgnoreInhibited") expected="no"
    value=a[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    if (expected!="" && (n!=2 || value!=expected)) print source ": " line
  }')
[[ -z "$conflicts" ]] || die "Opciones conflictivas; revisar manualmente: $conflicts"
[[ "$action" == apply ]] || exit 0
priv=()
if (( EUID != 0 )); then command -v sudo >/dev/null || die 'Falta sudo'; priv=(sudo); fi
"${priv[@]}" install -d -m 755 /etc/systemd/logind.conf.d
temp=$(mktemp)
staged=''
cleanup() {
  rm -f -- "$temp"
  [[ -z "$staged" ]] || "${priv[@]}" rm -f -- "$staged"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
render > "$temp"
if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
  printf '%s\n' 'Configuración idéntica. Sin cambios; reinicia manualmente si aún no se ha cargado.'
  exit 0
fi
if [[ -f "$target" ]]; then
  backup=$("${priv[@]}" mktemp "${target}.bak-$(date +%Y%m%d-%H%M%S).XXXXXX")
  "${priv[@]}" cp -p "$target" "$backup"
  printf 'Respaldo: %s\n' "$backup"
else
  printf '%s\n' 'Primera instalación: reversión retirando únicamente este drop-in.'
fi
staged=$("${priv[@]}" mktemp /etc/systemd/logind.conf.d/.rafex-lid.XXXXXX)
"${priv[@]}" install -o root -g root -m 644 "$temp" "$staged"
"${priv[@]}" mv -f "$staged" "$target"
staged=''
printf '%s\n' 'Configuración instalada. PENDIENTE: reinicio manual para cargarla.' \
  'No se reinició logind ni se modificaron BIOS, bloqueo de pantalla o parámetros del kernel.'
