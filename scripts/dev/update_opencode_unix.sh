#!/usr/bin/env bash
# v1.0.0 — Actualiza la instalación local oficial y su copia del perfil.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' 'Uso: update_opencode_unix.sh --check|--plan|--status|--apply [--version X.Y.Z]'
}
action=check
selected=false
version=''
while (( $# )); do
  case "$1" in
    --check|--plan|--status|--apply)
      [[ "$selected" == false ]] || die 'Selecciona una sola acción'
      action=${1#--}; selected=true; shift ;;
    --version)
      [[ $# -ge 2 ]] || die 'Falta versión'
      version=${2#v}
      [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Usa una versión estable X.Y.Z'
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
done
case "$(uname -s)" in Linux|Darwin) ;; *) die 'Solo macOS y Linux' ;; esac
(( EUID != 0 )) || die 'Ejecuta como usuario normal, sin sudo'
[[ "$HOME" == /* && "$HOME" != / ]] || die 'HOME inválido'
original="$HOME/.opencode/bin/opencode"
active="$HOME/.local/bin/opencode"
for path in "$HOME/.opencode" "$HOME/.opencode/bin" "$HOME/.local" "$HOME/.local/bin" "$original" "$active"; do
  [[ ! -L "$path" ]] || die "Ruta enlazada no admitida: $path"
done
for path in "$original" "$active"; do
  [[ -f "$path" && -x "$path" && -O "$path" ]] || die "Falta binario local propio: $path; revisa el instalador del perfil"
  printf '%s: ' "$path"
  "$path" --version
done
resolved=$(command -v opencode || true)
if [[ -n "$resolved" && "$resolved" != "$active" && "$resolved" != "$original" ]]; then
  die "Otra instalación precede en PATH: $resolved; usa su gestor de paquetes"
fi
printf 'Destino: %s; versión solicitada: %s\n' "$active" "${version:-última estable}"
[[ "$action" == apply ]] || {
  printf '%s\n' 'Sin cambios. Apply descarga el instalador oficial, respalda ambos binarios y sincroniza la copia local.'
  exit 0
}
command -v curl >/dev/null || die 'Falta curl'
[[ -w "${original%/*}" && -w "${active%/*}" ]] || die 'Directorios no escribibles'
umask 077
lock="$HOME/.opencode/.rafex-update.lock"
mkdir "$lock" 2>/dev/null || die 'Actualización bloqueada; comprueba si otra ejecución sigue activa'
backup=''
stage=''
restore=false
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$restore" == true ]]; then
    printf '%s\n' 'Actualización fallida: restaurando ambos binarios.' >&2
    install -m 755 "$backup/original" "$original" || rc=1
    install -m 755 "$backup/active" "$active" || rc=1
  fi
  [[ -z "$stage" ]] || rm -f -- "$stage"
  rmdir "$lock" || true
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
backup=$(mktemp -d "$HOME/.opencode/rafex-update-$(date +%Y%m%d-%H%M%S).XXXXXX")
cp -p "$original" "$backup/original"
cp -p "$active" "$backup/active"
printf 'Respaldo: %s\n' "$backup"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  https://opencode.ai/install -o "$backup/install.sh"
bash -n "$backup/install.sh"
args=(--no-modify-path)
[[ -z "$version" ]] || args+=(--version "$version")
restore=true
# VERSION no debe alterar implícitamente la versión solicitada por CLI.
env -u VERSION bash "$backup/install.sh" "${args[@]}"
installed=$("$original" --version)
[[ "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Versión instalada inválida'
[[ -z "$version" || "$installed" == "$version" ]] || die 'No se instaló la versión solicitada'
stage=$(mktemp "$HOME/.local/bin/.opencode-update.XXXXXX")
install -m 755 "$original" "$stage"
[[ "$("$stage" --version)" == "$installed" ]] || die 'La copia no supera la validación'
mv -f "$stage" "$active"
stage=''
cmp -s "$original" "$active" || die 'Los binarios no coinciden'
restore=false
printf 'OpenCode actualizado: %s. Reinicia las sesiones abiertas.\n' "$installed"
