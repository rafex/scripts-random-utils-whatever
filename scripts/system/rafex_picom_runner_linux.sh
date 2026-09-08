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
  # El perfil declara una sola autoridad: el paquete Picom de Debian. No se
  # consulta PATH ni ~/.local/bin porque una compilación heredada cambiaría el
  # compositor real sin que el servicio ni el auditor pudieran detectarlo.
  [[ -x /usr/bin/picom ]] || die 'falta el Picom administrado por Debian: /usr/bin/picom'
  printf '%s\n' /usr/bin/picom
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
