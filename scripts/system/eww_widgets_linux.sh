#!/usr/bin/env bash
# eww_widgets_linux.sh v1.1.0
# Controla la columna EWW administrada por Rafex sin reservar espacio del WM.
set -Eeuo pipefail
umask 077

ACTION=status
WINDOW=rafex-widgets
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"

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

is_open() {
  local eww_bin="$1"
  "$eww_bin" windows 2>/dev/null | grep -Eq "(^|[[:space:]])${WINDOW}([[:space:]]|:).*([Oo]pen|true|visible)"
}

ensure_daemon() {
  local eww_bin="$1"
  "$eww_bin" ping >/dev/null 2>&1 && return 0
  "$eww_bin" daemon >/dev/null 2>&1 &
  for _ in {1..20}; do
    sleep 0.2
    "$eww_bin" ping >/dev/null 2>&1 && return 0
  done
  return 1
}

open_window() {
  local eww_bin="$1"
  [[ -n "${DISPLAY:-}" ]] || { notify_error 'DISPLAY ausente; ejecuta esto dentro de la sesión X11'; return 1; }
  [[ -f "$CONFIG_ROOT/eww.yuck" && -f "$CONFIG_ROOT/eww.scss" ]] || {
    notify_error "falta la configuración en $CONFIG_ROOT; ejecuta just install-eww --apply"
    return 1
  }
  ensure_daemon "$eww_bin" || { notify_error 'el daemon EWW no respondió'; return 1; }
  if is_open "$eww_bin"; then
    ok 'ventana rafex-widgets ya estaba abierta'
    return 0
  fi
  "$eww_bin" open "$WINDOW" || { notify_error 'EWW no pudo abrir rafex-widgets'; return 1; }
  ok 'widgets EWW abiertos'
}

close_window() {
  local eww_bin="$1"
  "$eww_bin" ping >/dev/null 2>&1 || { info 'daemon EWW detenido'; return 0; }
  if is_open "$eww_bin"; then
    "$eww_bin" close "$WINDOW" || { notify_error 'EWW no pudo cerrar rafex-widgets'; return 1; }
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
    "$eww_bin" windows 2>/dev/null || true
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
  local eww_bin
  eww_bin="$(resolve_eww 2>/dev/null || true)"
  [[ -n "$eww_bin" ]] || { notify_error 'eww no está instalado'; return 1; }
  case "$ACTION" in
    open) open_window "$eww_bin" ;;
    close) close_window "$eww_bin" ;;
    toggle)
      if [[ -n "${DISPLAY:-}" ]] && ensure_daemon "$eww_bin" && is_open "$eww_bin"; then
        close_window "$eww_bin"
      else
        open_window "$eww_bin"
      fi
      ;;
    reload)
      "$eww_bin" ping >/dev/null 2>&1 || { info 'daemon EWW detenido; no se recarga'; return 0; }
      "$eww_bin" reload || { notify_error 'EWW no pudo recargar su configuración'; return 1; }
      ok 'configuración EWW recargada'
      ;;
    *) die "acción desconocida: $ACTION" ;;
  esac
}

main "$@"
