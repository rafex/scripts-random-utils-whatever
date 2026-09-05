#!/usr/bin/env bash
# shellcheck shell=bash
# Gestiona únicamente las instancias Tint2/Polybar del perfil Rafex para i3.
set -Eeuo pipefail
umask 077

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/rafex-i3-bar"
LOCK_FILE="$RUNTIME_DIR/runtime.lock"
TINT2_CONFIG="$CONFIG_HOME/rafex/i3-bars/tint2rc"
POLYBAR_CONFIG="$CONFIG_HOME/rafex/i3-bars/polybar.ini"
TINT2_PID_FILE="$RUNTIME_DIR/tint2.pid"
POLYBAR_PID_FILE="$RUNTIME_DIR/polybar.pid"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  rafex_i3_bar_runtime_linux.sh --sync i3bar|tint2|polybar
  rafex_i3_bar_runtime_linux.sh --reload
  rafex_i3_bar_runtime_linux.sh --stop
  rafex_i3_bar_runtime_linux.sh --status
EOF
}

require_user_session() {
  [[ "$(uname -s)" == Linux ]] || die 'este runtime requiere Linux'
  (( EUID != 0 )) || die 'no se ejecuta como root'
  [[ -n "${DISPLAY:-}" ]] || die 'DISPLAY no está disponible'
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || warn "XDG_RUNTIME_DIR no está definido; se usará /run/user/$UID"
  command -v flock >/dev/null 2>&1 || die 'falta flock'
  command -v pgrep >/dev/null 2>&1 || die 'falta pgrep'
  command -v ps >/dev/null 2>&1 || die 'falta ps'
  mkdir -p -- "$RUNTIME_DIR"
  chmod 700 -- "$RUNTIME_DIR"
}

read_pid() {
  local file="$1" pid=''
  [[ -f "$file" ]] || return 1
  pid="$(head -n 1 "$file")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

pid_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

command_line() {
  ps -o args= -p "$1" 2>/dev/null || true
}

managed_pid_for_config() {
  local config="$1" process_name pid process_line matches=0 found=''
  for process_name in tint2 polybar; do
    while read -r pid; do
      [[ -n "$pid" ]] || continue
      process_line="$(command_line "$pid")"
      [[ "$process_line" == *"$config"* ]] || continue
      matches=$((matches + 1))
      found="$pid"
    done < <(pgrep -x -u "$UID" "$process_name" 2>/dev/null || true)
  done
  if (( matches > 1 )); then
    die "hay varias instancias externas usando una configuración Rafex: $config"
  fi
  [[ -n "$found" ]] && printf '%s\n' "$found"
}

stop_recorded() {
  local name="$1" pid_file="$2" expected="$3" pid line
  pid="$(read_pid "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    rm -f -- "$pid_file"
    return 0
  fi
  if ! pid_alive "$pid"; then
    rm -f -- "$pid_file"
    return 0
  fi
  line="$(command_line "$pid")"
  [[ "$line" == *"$expected"* ]] || die "el PID registrado de $name no coincide con su configuración; no se detendrá"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pid_alive "$pid" || break
    sleep 0.2
  done
  if pid_alive "$pid"; then
    warn "$name no terminó después de SIGTERM; se conserva para no matar procesos ajenos"
    return 1
  fi
  rm -f -- "$pid_file"
  ok "$name administrado detenido"
}

stop_external_bars() {
  local failed=0
  stop_recorded tint2 "$TINT2_PID_FILE" "$TINT2_CONFIG" || failed=1
  stop_recorded polybar "$POLYBAR_PID_FILE" "$POLYBAR_CONFIG" || failed=1
  (( failed == 0 )) || die 'no se pudieron detener todas las barras administradas'
}

adopt_or_start_tint2() {
  local pid
  [[ -f "$TINT2_CONFIG" ]] || die "falta la configuración Tint2: $TINT2_CONFIG"
  command -v tint2 >/dev/null 2>&1 || die 'tint2 no está instalado; instala el paquete Debian y repite'
  pid="$(managed_pid_for_config "$TINT2_CONFIG" || true)"
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid" > "$TINT2_PID_FILE"
    ok 'Tint2 administrado ya estaba activo'
    return 0
  fi
  tint2 -c "$TINT2_CONFIG" >/dev/null 2>&1 &
  pid=$!
  sleep 0.2
  pid_alive "$pid" || die 'Tint2 terminó al iniciar'
  printf '%s\n' "$pid" > "$TINT2_PID_FILE"
  ok 'Tint2 administrado iniciado'
}

adopt_or_start_polybar() {
  local pid
  [[ -f "$POLYBAR_CONFIG" ]] || die "falta la configuración Polybar: $POLYBAR_CONFIG"
  command -v polybar >/dev/null 2>&1 || die 'polybar no está instalado; usa i3-bar --set polybar para instalarlo'
  pid="$(managed_pid_for_config "$POLYBAR_CONFIG" || true)"
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid" > "$POLYBAR_PID_FILE"
    ok 'Polybar administrado ya estaba activo'
    return 0
  fi
  polybar --config="$POLYBAR_CONFIG" rafex >/dev/null 2>&1 &
  pid=$!
  sleep 0.3
  pid_alive "$pid" || die 'Polybar terminó al iniciar; revisa su log o ejecuta polybar -l info'
  printf '%s\n' "$pid" > "$POLYBAR_PID_FILE"
  ok 'Polybar administrado iniciado'
}

sync_mode() {
  local mode="$1"
  case "$mode" in
    i3bar)
      stop_external_bars
      ;;
    tint2)
      stop_recorded polybar "$POLYBAR_PID_FILE" "$POLYBAR_CONFIG" || die 'no se pudo detener Polybar'
      adopt_or_start_tint2
      ;;
    polybar)
      stop_recorded tint2 "$TINT2_PID_FILE" "$TINT2_CONFIG" || die 'no se pudo detener Tint2'
      adopt_or_start_polybar
      ;;
    *) die "perfil de barra inválido: $mode" ;;
  esac
}

reload_current() {
  local state_file="$CONFIG_HOME/rafex/i3-bar-profile" mode='i3bar'
  if [[ -f "$state_file" ]]; then
    mode="$(head -n 1 "$state_file")"
  fi
  case "$mode" in i3bar|tint2|polybar) ;; *) mode=i3bar ;; esac
  if [[ "$mode" == tint2 ]] && [[ -f "$TINT2_PID_FILE" ]]; then
    sync_mode tint2
    kill -USR1 "$(read_pid "$TINT2_PID_FILE" 2>/dev/null || printf '0')" 2>/dev/null || true
  elif [[ "$mode" == polybar ]]; then
    stop_recorded polybar "$POLYBAR_PID_FILE" "$POLYBAR_CONFIG" || true
    adopt_or_start_polybar
  fi
}

show_status() {
  local state_file="$CONFIG_HOME/rafex/i3-bar-profile" mode='i3bar' pid line
  [[ -f "$state_file" ]] && mode="$(head -n 1 "$state_file")"
  printf 'state=%s\n' "$mode"
  for pair in "tint2:$TINT2_PID_FILE:$TINT2_CONFIG" "polybar:$POLYBAR_PID_FILE:$POLYBAR_CONFIG"; do
    IFS=: read -r name pid_file config <<<"$pair"
    pid="$(read_pid "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && pid_alive "$pid"; then
      line="$(command_line "$pid")"
      if [[ "$line" == *"$config"* ]]; then
        printf '%s=managed-running\n' "$name"
      else
        printf '%s=pid-mismatch\n' "$name"
      fi
    else
      printf '%s=stopped\n' "$name"
    fi
  done
}

main() {
  local action='' mode=''
  while (($#)); do
    case "$1" in
      --sync) [[ $# -ge 2 ]] || die '--sync requiere un perfil'; action=sync; mode="$2"; shift 2 ;;
      --reload) action=reload; shift ;;
      --stop) action=stop; shift ;;
      --status) action=status; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
  [[ -n "$action" ]] || { usage >&2; exit 2; }
  if [[ "$action" == status ]]; then
    show_status
    exit 0
  fi
  require_user_session
  exec 9>"$LOCK_FILE"
  flock -n 9 || die 'otra operación de barra Rafex está en curso'
  case "$action" in
    sync) sync_mode "$mode" ;;
    reload) reload_current ;;
    stop) stop_external_bars ;;
  esac
}

main "$@"
