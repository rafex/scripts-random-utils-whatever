#!/usr/bin/env bash
# picom_toggle_linux.sh v2.0.0
# Controla Picom mediante la unidad de usuario de Rafex cuando está instalada.
# shellcheck shell=bash
set -Eeuo pipefail
umask 077

ACTION=toggle
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_FILE="${CONFIG_HOME}/rafex/picom-autostart-enabled"
LEGACY_STATE_FILE="${CONFIG_HOME}/rafex/openbox-picom-enabled"
CONFIG_FILE="${PICOM_CONFIG:-${CONFIG_HOME}/picom/picom.conf}"
PICOM_SERVICE="rafex-picom.service"
PICOM_BIN="${PICOM_BIN:-}"

usage() {
  cat <<'EOF'
Uso:
  picom_toggle_linux.sh --check
  picom_toggle_linux.sh --enable
  picom_toggle_linux.sh --disable
  picom_toggle_linux.sh --toggle
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION=check; shift ;;
      --enable) ACTION=enable; shift ;;
      --disable) ACTION=disable; shift ;;
      --toggle) ACTION=toggle; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl --user cat "$PICOM_SERVICE" >/dev/null 2>&1
}

service_active() {
  systemctl --user is-active --quiet "$PICOM_SERVICE" 2>/dev/null
}

autostart_enabled() {
  [[ -f "$STATE_FILE" || -f "$LEGACY_STATE_FILE" ]]
}

picom_command() {
  if [[ -n "$PICOM_BIN" ]]; then
    printf '%s\n' "$PICOM_BIN"
  elif [[ -x "$HOME/.local/bin/picom" ]]; then
    printf '%s\n' "$HOME/.local/bin/picom"
  else
    command -v picom
  fi
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -t 1500 'Picom' "$1" || true
}

set_state() {
  local enabled="$1"
  mkdir -p -- "$(dirname -- "$STATE_FILE")"
  if [[ "$enabled" == yes ]]; then
    printf '%s\n' enabled > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    # Openbox anterior todavía consulta este nombre; se conserva durante la
    # migración para que ambos perfiles compartan la misma preferencia.
    printf '%s\n' enabled > "$LEGACY_STATE_FILE"
    chmod 600 "$LEGACY_STATE_FILE"
  else
    rm -f -- "$STATE_FILE" "$LEGACY_STATE_FILE"
  fi
}

import_graphical_environment() {
  [[ -n "${DISPLAY:-}" ]] || return 0
  systemctl --user import-environment DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS \
    >/dev/null 2>&1 || true
}

set_service_overrides() {
  if [[ -n "$PICOM_BIN" ]]; then
    systemctl --user set-environment RAFEX_PICOM_BIN="$PICOM_BIN"
  else
    systemctl --user unset-environment RAFEX_PICOM_BIN
  fi
  if [[ -n "$CONFIG_FILE" ]]; then
    systemctl --user set-environment RAFEX_PICOM_CONFIG="$CONFIG_FILE"
  fi
}

start_service() {
  import_graphical_environment
  set_service_overrides
  systemctl --user start "$PICOM_SERVICE"
}

stop_service() {
  systemctl --user stop "$PICOM_SERVICE"
}

legacy_running_pids() {
  local pid args
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
    if [[ "$args" == *"--config $CONFIG_FILE"* || "$args" == *"--config=$CONFIG_FILE"* ]]; then
      printf '%s\n' "$pid"
    else
      printf '⚠ se conserva un Picom no administrado (pid %s)\n' "$pid" >&2
    fi
  done < <(pgrep -u "$USER" -x picom 2>/dev/null || true)
}

start_legacy() {
  local binary
  binary="$(picom_command 2>/dev/null || true)"
  [[ -x "$binary" ]] || { echo 'picom no está instalado.' >&2; return 1; }
  if pgrep -u "$USER" -x picom >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    "$binary" --config "$CONFIG_FILE" >/dev/null 2>&1 &
  else
    "$binary" >/dev/null 2>&1 &
  fi
}

stop_legacy() {
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done < <(legacy_running_pids)
}

show_check() {
  if systemd_user_available; then
    if service_active; then echo 'picom=running'; else echo 'picom=stopped'; fi
    echo 'backend=systemd-user'
    echo "unit=$PICOM_SERVICE"
  elif pgrep -u "$USER" -x picom >/dev/null 2>&1; then
    echo 'picom=running'
    echo 'backend=legacy-process'
    echo 'unit=missing'
  else
    echo 'picom=stopped'
    echo 'backend=legacy-process'
    echo 'unit=missing'
  fi
  if autostart_enabled; then echo 'autostart=enabled'; else echo 'autostart=disabled'; fi
  echo "config=$CONFIG_FILE"
}

main() {
  parse_args "$@"
  (( EUID != 0 )) || { echo 'ejecútalo como usuario normal.' >&2; exit 1; }
  command -v pgrep >/dev/null 2>&1 || { echo 'pgrep no está disponible.' >&2; exit 1; }
  if [[ "$ACTION" == check ]]; then
    show_check
    return 0
  fi

  if systemd_user_available; then
    case "$ACTION" in
      enable)
        set_state yes
        start_service
        notify 'Activado mediante systemd'
        ;;
      disable)
        set_state no
        stop_service || true
        notify 'Desactivado'
        ;;
      toggle)
        if service_active; then
          set_state no
          stop_service || true
          notify 'Desactivado'
        else
          set_state yes
          start_service
          notify 'Activado mediante systemd'
        fi
        ;;
    esac
    return 0
  fi

  echo '⚠ rafex-picom.service no está instalada; se usa compatibilidad legacy.' >&2
  case "$ACTION" in
    enable)
      set_state yes
      start_legacy
      notify 'Activado (compatibilidad legacy)'
      ;;
    disable)
      set_state no
      stop_legacy
      notify 'Desactivado'
      ;;
    toggle)
      if pgrep -u "$USER" -x picom >/dev/null 2>&1; then
        set_state no
        stop_legacy
        notify 'Desactivado'
      else
        set_state yes
        start_legacy
        notify 'Activado (compatibilidad legacy)'
      fi
      ;;
  esac
}

main "$@"
