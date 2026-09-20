#!/usr/bin/env bash
# install_i3_workspace_usage_linux.sh v1.0.0
# Instala el registrador privado de uso de workspaces para el perfil ThinkPad.
# shellcheck shell=bash
set -Eeuo pipefail
umask 077

ACTION=check
CHOSEN=false
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
SOURCE="$REPO_ROOT/scripts/system/i3_workspace_usage_linux.py"
UNIT_SOURCE="$PROFILE_ROOT/config/systemd/user/rafex-i3-workspace-usage.service"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
I3_CONFIG="$CONFIG_HOME/i3/config"
TARGET="$HOME/.local/bin/i3-workspace-usage.py"
UNIT_TARGET="$CONFIG_HOME/systemd/user/rafex-i3-workspace-usage.service"
BEGIN='# >>> rafex-i3-workspace-usage managed >>>'

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: install_i3_workspace_usage_linux.sh --check|--plan|--apply|--status

Instala el registrador privado de clases/instancias de ventanas i3 para el
perfil thinkpad-x1-yoga-1st. No usa sudo ni habilita la unidad globalmente.
EOF
}

while (($#)); do
  case "$1" in
    --check|--plan|--apply|--status)
      [[ "$CHOSEN" == false ]] || die 'selecciona una sola acción'
      ACTION="${1#--}"; CHOSEN=true ;;
    --help|-h) usage; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
  shift
done

[[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
(( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
command -v python3 >/dev/null 2>&1 || die 'falta python3'
command -v systemctl >/dev/null 2>&1 || die 'falta systemctl'
[[ -f "$SOURCE" ]] || die "falta el helper: $SOURCE"
[[ -f "$UNIT_SOURCE" ]] || die "falta la unidad: $UNIT_SOURCE"

is_managed() { [[ -f "$1" ]] && grep -Fq 'Managed by rafex install_i3_workspace_usage_linux.sh' "$1"; }

copy_managed() {
  local source="$1" target="$2" mode="$3" temporary
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then return; fi
  if [[ -e "$target" ]] && ! is_managed "$target"; then
    die "se rehúsa sobrescribir archivo no administrado: $target"
  fi
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  install -m "$mode" -- "$source" "$temporary"
  mv -f -- "$temporary" "$target"
}

status() {
  printf 'helper=%s\n' "$( [[ -x "$TARGET" ]] && echo installed || echo missing )"
  printf 'unit=%s\n' "$( [[ -f "$UNIT_TARGET" ]] && echo installed || echo missing )"
  printf 'i3-autostart=%s\n' "$( grep -Fq "$BEGIN" "$I3_CONFIG" 2>/dev/null && echo present || echo missing )"
  printf 'service=%s\n' "$(systemctl --user is-active rafex-i3-workspace-usage.service 2>/dev/null || true)"
}

case "$ACTION" in
  check)
    if [[ -x "$TARGET" ]]; then ok "helper instalado: $TARGET"; else warn "helper ausente: ejecuta --apply"; fi
    if [[ -f "$UNIT_TARGET" ]]; then ok "unidad instalada: $UNIT_TARGET"; else warn "unidad ausente: ejecuta --apply"; fi
    if grep -Fq "$BEGIN" "$I3_CONFIG" 2>/dev/null; then ok 'autostart i3 presente'; else warn 'autostart i3 ausente: reaplica el perfil ThinkPad'; fi
    ;;
  status) status ;;
  plan)
    info "instalar $SOURCE → $TARGET"
    info "instalar $UNIT_SOURCE → $UNIT_TARGET"
    info 'ejecutar systemctl --user daemon-reload; i3 iniciará la unidad en la próxima sesión'
    ;;
  apply)
    copy_managed "$SOURCE" "$TARGET" 0700
    copy_managed "$UNIT_SOURCE" "$UNIT_TARGET" 0644
    systemctl --user daemon-reload
    if grep -Fq "$BEGIN" "$I3_CONFIG" 2>/dev/null; then
      ok 'autostart i3 presente; reinicia i3 para comenzar a registrar'
    else
      warn 'autostart i3 ausente; ejecuta just install-profile thinkpad-x1-yoga-1st para publicar el perfil actualizado'
    fi
    ok 'registrador instalado; no se habilitó globalmente ni se modificó i3'
    ;;
esac
