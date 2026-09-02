#!/usr/bin/env bash
# eww_widgets_linux.sh v1.2.1
# Controla la columna EWW administrada por Rafex sin reservar espacio del WM.
set -Eeuo pipefail
umask 077

ACTION=status
WINDOW=rafex-widgets
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"
LOCK_ROOT="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}"
LOCK_FILE="$LOCK_ROOT/rafex-eww-widgets.lock"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical 'Widgets EWW' "$1" >/dev/null 2>&1 || true
  else
    warn "$1"
  fi
}

usage() {
  cat <<'EOF'
Uso:
  eww_widgets_linux.sh --open dashboard
  eww_widgets_linux.sh --close dashboard
  eww_widgets_linux.sh --toggle dashboard
  eww_widgets_linux.sh --reload
  eww_widgets_linux.sh --status

La ventana dashboard es una sola columna desktop, al fondo y sin reserve.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --open) ACTION=open ;;
      --close) ACTION=close ;;
      --toggle) ACTION=toggle ;;
      --reload) ACTION=reload ;;
      --status) ACTION=status ;;
      dashboard|status) WINDOW=rafex-widgets ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

resolve_eww() {
  if command -v eww >/dev/null 2>&1; then
    command -v eww
  elif [[ -x "$HOME/.local/bin/eww" ]]; then
    printf '%s\n' "$HOME/.local/bin/eww"
  else
    return 1
  fi
}

acquire_operation_lock() {
  mkdir -p -- "$LOCK_ROOT"
  command -v flock >/dev/null 2>&1 || {
    notify_error 'falta flock; instala util-linux antes de iniciar EWW'
    return 1
  }
  exec 9>"$LOCK_FILE"
  if ! flock -w 15 9; then
    notify_error 'otra operación de EWW sigue en curso; no se abrirá una segunda instancia'
    return 1
  fi
}

window_state() {
  local eww_bin="$1" active_windows

  # EWW v0.5+ replaced the old windows query with active-windows. Keep the
  # command failure distinguishable so toggle never reopens a window just
  # because its state could not be queried.
  active_windows="$("$eww_bin" active-windows 2>/dev/null)" || return 2
  if awk -v window="$WINDOW" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == window || line ~ ("^" window "([[:space:]:]|$)")) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$active_windows"; then
    return 0
  fi
  return 1
}

ensure_daemon() {
  local eww_bin="$1"
  "$eww_bin" ping >/dev/null 2>&1 && return 0
  # El daemon es persistente: nunca debe heredar el bloqueo de la operación.
  "$eww_bin" daemon 9>&- >/dev/null 2>&1 &
  for _ in {1..20}; do
    sleep 0.2
    "$eww_bin" ping >/dev/null 2>&1 && return 0
  done
  return 1
}

open_window() {
  local eww_bin="$1" state
  [[ -n "${DISPLAY:-}" ]] || { notify_error 'DISPLAY ausente; ejecuta esto dentro de la sesión X11'; return 1; }
  [[ -f "$CONFIG_ROOT/eww.yuck" && -f "$CONFIG_ROOT/eww.scss" ]] || {
    notify_error "falta la configuración en $CONFIG_ROOT; ejecuta just install-eww --apply"
    return 1
  }
  ensure_daemon "$eww_bin" || { notify_error 'el daemon EWW no respondió'; return 1; }
  if window_state "$eww_bin"; then
    ok 'ventana rafex-widgets ya estaba abierta'
    return 0
  else
    state=$?
  fi
  if [[ "$state" -eq 2 ]]; then
    notify_error 'no se pudo consultar las ventanas activas de EWW; no se abrirá otra instancia'
    return 1
  fi
  "$eww_bin" open "$WINDOW" 9>&- || { notify_error 'EWW no pudo abrir rafex-widgets'; return 1; }
  ok 'widgets EWW abiertos'
}

close_window() {
  local eww_bin="$1" state
  "$eww_bin" ping >/dev/null 2>&1 || { info 'daemon EWW detenido'; return 0; }
  if window_state "$eww_bin"; then
    state=0
  else
    state=$?
  fi
  if [[ "$state" -eq 2 ]]; then
    notify_error 'no se pudo consultar las ventanas activas de EWW; no se cerrará ninguna ventana'
    return 1
  elif [[ "$state" -eq 0 ]]; then
    "$eww_bin" close "$WINDOW" 9>&- || { notify_error 'EWW no pudo cerrar rafex-widgets'; return 1; }
    ok 'widgets EWW cerrados'
  else
    info 'rafex-widgets ya estaba cerrado'
  fi
}

status() {
  local eww_bin
  printf '═══ Widgets EWW Rafex ═══\n'
  if [[ -f "$CONFIG_ROOT/eww.yuck" ]]; then ok "Yuck: $CONFIG_ROOT/eww.yuck"; else warn 'Yuck ausente'; fi
  if [[ -f "$CONFIG_ROOT/eww.scss" ]]; then ok "SCSS: $CONFIG_ROOT/eww.scss"; else warn 'SCSS ausente'; fi
  eww_bin="$(resolve_eww 2>/dev/null || true)"
  [[ -n "$eww_bin" ]] || { warn 'eww no está instalado'; return 0; }
  printf 'binario=%s\n' "$eww_bin"
  if "$eww_bin" ping >/dev/null 2>&1; then
    ok 'daemon EWW activo'
    printf '%s\n' 'ventanas activas:'
    "$eww_bin" active-windows 2>/dev/null || warn 'no se pudo consultar ventanas activas'
    printf '%s\n' 'ventanas definidas:'
    "$eww_bin" list-windows 2>/dev/null || warn 'no se pudo consultar ventanas definidas'
  else
    info 'daemon EWW detenido'
  fi
  if [[ -n "${DISPLAY:-}" ]]; then printf 'DISPLAY=%s\n' "$DISPLAY"; else warn 'DISPLAY ausente; no se lanza EWW'; fi
}

main() {
  parse_args "$@"
  [[ "$EUID" -ne 0 ]] || die 'ejecútalo como usuario normal'
  if [[ "$ACTION" == status ]]; then
    status
    return 0
  fi
  acquire_operation_lock || return 1
  local eww_bin
  eww_bin="$(resolve_eww 2>/dev/null || true)"
  [[ -n "$eww_bin" ]] || { notify_error 'eww no está instalado'; return 1; }
  case "$ACTION" in
    open) open_window "$eww_bin" ;;
    close) close_window "$eww_bin" ;;
    toggle)
      [[ -n "${DISPLAY:-}" ]] || { open_window "$eww_bin"; return; }
      ensure_daemon "$eww_bin" || { notify_error 'el daemon EWW no respondió'; return 1; }
      local state
      if window_state "$eww_bin"; then
        state=0
      else
        state=$?
      fi
      case "$state" in
        0) close_window "$eww_bin" ;;
        1) open_window "$eww_bin" ;;
        *)
          notify_error 'no se pudo consultar las ventanas activas de EWW; no se cambiará su estado'
          return 1
          ;;
      esac
      ;;
    reload)
      "$eww_bin" ping >/dev/null 2>&1 || { info 'daemon EWW detenido; no se recarga'; return 0; }
      if [[ -z "${DISPLAY:-}" ]]; then
        info 'DISPLAY ausente; no se recarga la ventana EWW desde esta sesión'
        return 0
      fi
      local state
      if window_state "$eww_bin"; then
        state=0
      else
        state=$?
      fi
      [[ "$state" -ne 2 ]] || {
        notify_error 'no se pudo consultar las ventanas activas de EWW; no se recargará'
        return 1
      }
      if [[ "$state" -eq 0 ]]; then
        "$eww_bin" close "$WINDOW" 9>&- || { notify_error 'EWW no pudo cerrar rafex-widgets antes de recargar'; return 1; }
      fi
      "$eww_bin" reload 9>&- || { notify_error 'EWW no pudo recargar su configuración'; return 1; }
      if [[ "$state" -eq 0 ]]; then
        "$eww_bin" open "$WINDOW" 9>&- || { notify_error 'EWW no pudo volver a abrir rafex-widgets'; return 1; }
      fi
      ok 'configuración EWW recargada'
      ;;
    *) die "acción desconocida: $ACTION" ;;
  esac
}

main "$@"
