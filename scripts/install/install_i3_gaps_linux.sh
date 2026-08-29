#!/usr/bin/env bash
# shellcheck shell=bash
# Configura los gaps nativos de i3 en Debian; no instala el fork i3-gaps.
set -Eeuo pipefail
umask 077

ACTION="check"
INNER_GAP="4px"
OUTER_GAP="6px"
I3_CONFIG="${I3_GAPS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/i3/config}"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BEGIN_MARKER="# BEGIN rafex i3-gaps"
END_MARKER="# END rafex i3-gaps"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_i3_gaps_linux.sh --check
  install_i3_gaps_linux.sh --plan
  install_i3_gaps_linux.sh --apply

Opciones:
  --check       Diagnostica i3 y la configuración sin modificar nada.
  --plan        Muestra las acciones previstas sin modificar nada.
  --dry-run     Alias de --plan.
  --apply       Instala/verifica i3-wm y configura gaps nativos.
  --help        Muestra esta ayuda.

Este script usa el soporte de gaps integrado en i3 >= 4.22. No compila ni
instala el proyecto antiguo i3-gaps.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_commands() {
  [[ "$(uname -s)" == Linux ]] || die "este script solo funciona en Linux"
  local command_name
  for command_name in awk cmp cp date grep mktemp mv i3 sort; do
    command -v "$command_name" >/dev/null 2>&1 || {
      [[ "$command_name" == i3 ]] && continue
      die "falta la herramienta: $command_name"
    }
  done
}

version_at_least() {
  local version="$1" minimum="4.22"
  [[ -n "$version" ]] || return 1
  [[ "$(printf '%s\n' "$minimum" "$version" | sort -V | head -n 1)" == "$minimum" ]]
}

i3_version() {
  i3 --version 2>/dev/null | awk '{print $3; exit}' || true
}

has_managed_block() {
  [[ -f "$I3_CONFIG" ]] && grep -Fq "$BEGIN_MARKER" "$I3_CONFIG" &&
    grep -Fq "$END_MARKER" "$I3_CONFIG"
}

has_unmanaged_gaps() {
  [[ -f "$I3_CONFIG" ]] || return 1
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { inside=1; next }
    $0 == end { inside=0; next }
    !inside && $0 ~ /^[[:space:]]*(gaps|smart_gaps)[[:space:]]/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$I3_CONFIG"
}

show_status() {
  local version
  echo '═══ Gaps nativos de i3 ═══'
  if command -v i3 >/dev/null 2>&1; then
    version="$(i3_version)"
    printf 'i3=%s\n' "${version:-desconocido}"
    if version_at_least "$version"; then
      ok 'i3 admite gaps nativos (>= 4.22)'
    else
      warn 'la versión de i3 es anterior a 4.22 o no se pudo determinar'
    fi
  else
    printf 'i3=missing\n'
  fi
  printf 'config=%s\n' "$I3_CONFIG"
  if [[ -f "$I3_CONFIG" ]]; then
    if has_managed_block; then
      ok 'bloque rafex i3-gaps presente'
    else
      warn 'bloque rafex i3-gaps ausente'
    fi
    if has_unmanaged_gaps; then
      warn 'existen directivas gaps fuera del bloque administrado'
    else
      ok 'no hay directivas gaps externas en conflicto'
    fi
  else
    warn 'no existe la configuración de i3; instala primero el perfil ThinkPad'
  fi
}

gaps_block() {
  cat <<EOF
$BEGIN_MARKER
gaps inner $INNER_GAP
gaps outer $OUTER_GAP
smart_gaps on
$END_MARKER
EOF
}

backup_config() {
  local backup="${I3_CONFIG}.bak.${BACKUP_STAMP}"
  cp -a -- "$I3_CONFIG" "$backup"
  info "respaldo creado: $backup"
}

render_config() {
  local destination="$1" block_file="$2"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block_file="$block_file" '
    function emit_block(line) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }
    $0 == begin {
      emit_block()
      inside=1
      found=1
      next
    }
    inside && $0 == end { inside=0; next }
    !inside { print }
    END {
      if (!found) {
        print ""
        emit_block()
      }
    }
  ' "$I3_CONFIG" > "$destination"
}

apply_config() {
  local block_file temporary
  [[ -f "$I3_CONFIG" ]] || die "no existe $I3_CONFIG; instala primero just install-profile thinkpad-x1-yoga-1st"
  has_unmanaged_gaps && die "hay directivas gaps fuera del bloque administrado; revísalas antes de continuar"
  block_file="$(mktemp)"
  temporary="$(mktemp)"
  gaps_block > "$block_file"
  render_config "$temporary" "$block_file"
  rm -f -- "$block_file"
  if cmp -s "$I3_CONFIG" "$temporary"; then
    rm -f -- "$temporary"
    ok 'los gaps nativos ya están configurados'
    return 0
  fi
  if ! i3 -C -c "$temporary"; then
    rm -f -- "$temporary"
    die 'la configuración propuesta de i3 no es válida; no se modificó el archivo actual'
  fi
  backup_config
  chmod --reference="$I3_CONFIG" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$I3_CONFIG"
  ok "gaps configurados: inner=$INNER_GAP outer=$OUTER_GAP smart_gaps=on"
}

ensure_i3_package() {
  if command -v i3 >/dev/null 2>&1; then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
  sudo -v
  sudo apt-get update
  sudo apt-get install -y i3-wm
}

main() {
  parse_args "$@"
  require_commands

  case "$ACTION" in
    check)
      show_status
      ;;
    plan)
      show_status
      info '[plan] verificar o instalar i3-wm desde Debian'
      info "[plan] respaldar $I3_CONFIG"
      info "[plan] insertar inner=$INNER_GAP, outer=$OUTER_GAP y smart_gaps=on"
      info '[plan] validar con i3 -C y recargar solo dentro de la sesión gráfica'
      ;;
    apply)
      ensure_i3_package
      version_at_least "$(i3_version)" || die 'i3 debe ser versión 4.22 o posterior para usar gaps nativos'
      apply_config
      if [[ -n "${DISPLAY:-}" ]] && command -v i3-msg >/dev/null 2>&1; then
        i3 -C -c "$I3_CONFIG"
        i3-msg reload >/dev/null
        ok 'i3 validado y recargado'
      else
        i3 -C -c "$I3_CONFIG"
        info 'sesión gráfica no detectada; ejecuta i3-msg reload dentro de i3'
      fi
      ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
