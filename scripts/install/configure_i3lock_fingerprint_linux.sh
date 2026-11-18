#!/usr/bin/env bash
# v1.0.0
set -euo pipefail

config=/etc/pam.d/i3lock
marker='# BEGIN rafex i3lock fingerprint'
action=${1:---check}

if (( $# > 1 )); then
  printf 'Selecciona una sola opción.\n' >&2
  exit 2
fi
case "$action" in
  --help|-h) printf 'Uso: %s [--check|--apply]\n' "${0##*/}"; exit ;;
  --check|--apply) ;;
  *) printf 'Opción desconocida: %s\n' "$action" >&2; exit 2 ;;
esac

[[ "$(uname -s)" == Linux && -f "$config" && ! -L "$config" ]] ||
  { printf 'Se requiere Linux con %s como archivo regular.\n' "$config" >&2; exit 1; }

if [[ "$action" == --check ]]; then
  if grep -Fxq "$marker" "$config"; then
    printf 'Huella configurada en %s.\n' "$config"
  else
    printf 'Huella sin configurar por este script en %s.\n' "$config"
  fi
  exit
fi

if (( EUID != 0 )); then
  exec sudo bash "${BASH_SOURCE[0]}" --apply
fi

user=${SUDO_USER:-}
[[ "$user" =~ ^[a-z_][a-z0-9_-]*$ && "$user" != root ]] ||
  { printf 'Ejecuta --apply desde la cuenta que usa el bloqueador.\n' >&2; exit 1; }

rule="auth [success=ignore default=1] pam_succeed_if.so quiet user = $user"
fingerprint='auth sufficient pam_fprintd.so max-tries=1 timeout=8'
if grep -Fxq "$marker" "$config"; then
  if grep -Fxq "$rule" "$config" && grep -Fxq "$fingerprint" "$config"; then
    printf 'La huella ya está configurada para %s.\n' "$user"
    exit
  fi
  printf 'Ya hay una configuración administrada distinta en %s.\n' "$config" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*auth[[:space:]].*pam_fprintd\.so' "$config" ||
   [[ "$(grep -Fxc '@include common-auth' "$config")" != 1 ]]; then
  printf 'La configuración PAM requiere revisión manual: %s.\n' "$config" >&2
  exit 1
fi

if ! fprintd-list "$user" | grep -Eq '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
  printf 'Registra una huella para %s antes de activar PAM.\n' "$user" >&2
  exit 1
fi
backup="$(mktemp -d /var/backups/i3lock-pam.XXXXXX)"
cp -a -- "$config" "$backup/i3lock"
sed -i "/^@include common-auth$/i $marker\\n$rule\\n$fingerprint\\n# END rafex i3lock fingerprint" "$config"
printf 'Huella habilitada para %s. Respaldo: %s/i3lock\n' "$user" "$backup"
