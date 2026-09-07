#!/usr/bin/env bash
# rafex_picom_runner_linux.sh v1.0.0
# Ejecuta la instancia administrada de Picom desde un servicio de usuario.
# Managed by rafex install_picom_user_service_linux.sh
# shellcheck shell=bash
set -Eeuo pipefail
umask 077

CONFIG_FILE="${RAFEX_PICOM_CONFIG:-${PICOM_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/picom/picom.conf}}"

die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  exit 1
}

select_binary() {
  local candidate
  if [[ -n "${RAFEX_PICOM_BIN:-}" ]]; then
    candidate="$RAFEX_PICOM_BIN"
    [[ -x "$candidate" ]] || die "el binario configurado no es ejecutable: $candidate"
    printf '%s\n' "$candidate"
    return 0
  fi
  if [[ -x "$HOME/.local/bin/picom" ]]; then
    printf '%s\n' "$HOME/.local/bin/picom"
    return 0
  fi
  if [[ -x /usr/bin/picom ]]; then
    printf '%s\n' /usr/bin/picom
    return 0
  fi
  candidate="$(command -v picom 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || die 'no se encontró un binario Picom ejecutable'
  printf '%s\n' "$candidate"
}

main() {
  [[ "$(uname -s)" == Linux ]] || die 'este runner requiere Linux'
  (( EUID != 0 )) || die 'el servicio no debe ejecutarse como root'
  [[ -n "${DISPLAY:-}" ]] || die 'DISPLAY no está disponible; i3 debe importar el entorno X11 antes de iniciar el servicio'
  [[ -f "$CONFIG_FILE" ]] || die "falta la configuración de Picom: $CONFIG_FILE"

  local binary
  binary="$(select_binary)"
  if [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]]; then
    export XAUTHORITY="$HOME/.Xauthority"
  fi
  exec "$binary" --config "$CONFIG_FILE"
}

main "$@"
