#!/usr/bin/env bash
# shellcheck shell=bash
# Instala Conky y lo integra de forma idempotente en i3 y Openbox.
set -Eeuo pipefail
umask 077

ACTION=check
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONKY_CONFIG="$CONFIG_HOME/conky/conky.conf"
HELPER_TARGET="$HOME/.local/bin/conky-status.sh"
LAUNCHER_TARGET="$HOME/.local/bin/conky-launch.sh"
I3_CONFIG="$CONFIG_HOME/i3/config"
OPENBOX_AUTOSTART="$CONFIG_HOME/openbox/autostart"
SOURCE_CONFIG="$PROFILE_ROOT/config/conky/conky.conf"
SOURCE_HELPER="$REPO_ROOT/scripts/system/conky_status_linux.sh"
SOURCE_LAUNCHER="$PROFILE_ROOT/config/conky/start-conky.sh"
I3_BEGIN='# BEGIN rafex conky'
I3_END='# END rafex conky'
OPENBOX_BEGIN='# BEGIN rafex conky'
OPENBOX_END='# END rafex conky'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
ok() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
die() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  install_conky_linux.sh --check
  install_conky_linux.sh --plan
  install_conky_linux.sh --apply
  install_conky_linux.sh --status

Opciones:
  --check       Comprueba Debian, plantillas y dependencias sin modificar nada.
  --plan        Muestra las acciones previstas sin modificar nada.
  --dry-run     Alias de --plan.
  --apply       Instala conky-all y configura i3/Openbox.
  --status      Muestra el estado instalado y las instancias de Conky.
  --help        Muestra esta ayuda.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION=check; shift ;;
      --plan|--dry-run) ACTION=plan; shift ;;
      --apply) ACTION=apply; shift ;;
      --status) ACTION=status; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_platform() {
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se pudo identificar la distribución'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] || die 'este instalador requiere Debian o una distribución derivada'
}

require_commands() {
  local command_name
  for command_name in apt-cache cmp cp date dirname mkdir mktemp mv pgrep; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

candidate_available() {
  LC_ALL=C apt-cache policy conky-all 2>/dev/null |
    awk '$1 == "Candidate:" && $2 != "" && $2 != "(none)" {found=1} END {exit !found}'
}

package_installed() {
  dpkg-query -W -f='${Status}' conky-all 2>/dev/null |
    grep -q 'install ok installed'
}

validate_sources() {
  [[ -f "$SOURCE_CONFIG" ]] || die "falta la configuración: $SOURCE_CONFIG"
  [[ -f "$SOURCE_HELPER" ]] || die "falta el helper: $SOURCE_HELPER"
  [[ -f "$SOURCE_LAUNCHER" ]] || die "falta el lanzador: $SOURCE_LAUNCHER"
}

backup_path() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  cp -a -- "$path" "${path}.bak.${STAMP}"
  info "respaldo creado: ${path}.bak.${STAMP}"
}

install_file() {
  local source="$1" target="$2" mode="$3" temporary
  mkdir -p "$(dirname -- "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then return 0; fi
  backup_path "$target"
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  cp -- "$source" "$temporary"
  chmod "$mode" "$temporary"
  mv -f -- "$temporary" "$target"
}

ensure_managed_window_type() {
  local target="$1" temporary
  [[ -f "$target" ]] || return 0
  grep -Fq '    -- BEGIN rafex theme' "$target" || return 0
  if grep -Eq "^[[:space:]]*own_window_type[[:space:]]*=[[:space:]]*'override',[[:space:]]*$" "$target"; then
    return 0
  fi
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  awk '{
    if ($0 ~ /^[[:space:]]*own_window_type[[:space:]]*=/) {
      print "    own_window_type = '\''override'\'',"
    } else {
      print
    }
  }' "$target" > "$temporary"
  backup_path "$target"
  chmod --reference="$target" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$target"
  ok 'configuración Conky administrada actualizada para i3/Openbox'
}

write_i3_block() {
  cat <<'EOF'
# BEGIN rafex conky
exec_always --no-startup-id ~/.local/bin/conky-launch.sh
# END rafex conky
EOF
}

write_openbox_block() {
  cat <<'EOF'
# BEGIN rafex conky
if [ -x "$HOME/.local/bin/conky-launch.sh" ]; then
    "$HOME/.local/bin/conky-launch.sh" &
fi
# END rafex conky
EOF
}

replace_block() {
  local target="$1" begin="$2" end="$3" block_file="$4" temporary
  temporary="$(mktemp)"
  if [[ -f "$target" ]]; then
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function emit(line) {while ((getline line < block_file) > 0) print line; close(block_file)}
      $0 == begin {emit(); inside=1; found=1; next}
      inside && $0 == end {inside=0; next}
      !inside {print}
      END {if (!found) {print ""; emit()}}
    ' "$target" > "$temporary"
  else
    cat "$block_file" > "$temporary"
  fi
  if [[ -f "$target" ]] && cmp -s "$target" "$temporary"; then rm -f -- "$temporary"; return 0; fi
  backup_path "$target"
  if [[ -f "$target" ]]; then chmod --reference="$target" "$temporary" 2>/dev/null || true; fi
  mv -f -- "$temporary" "$target"
}

configure_integrations() {
  local block_file i3_backup had_i3=0
  mkdir -p "$CONFIG_HOME/openbox"
  if [[ -f "$CONKY_CONFIG" ]] && ! grep -Fq '    -- BEGIN rafex theme' "$CONKY_CONFIG"; then
    warn "existe una configuración Conky no administrada; no se sobrescribe: $CONKY_CONFIG"
  elif [[ -f "$CONKY_CONFIG" ]]; then
    ensure_managed_window_type "$CONKY_CONFIG"
  else
    install_file "$SOURCE_CONFIG" "$CONKY_CONFIG" 0644
  fi
  install_file "$SOURCE_HELPER" "$HELPER_TARGET" 0755
  install_file "$SOURCE_LAUNCHER" "$LAUNCHER_TARGET" 0755
  block_file="$(mktemp)"
  write_i3_block > "$block_file"
  if [[ -f "$I3_CONFIG" ]]; then
    had_i3=1
    replace_block "$I3_CONFIG" "$I3_BEGIN" "$I3_END" "$block_file"
    if command -v i3 >/dev/null 2>&1 && ! i3 -C -c "$I3_CONFIG" >/dev/null 2>&1; then
      i3_backup="${I3_CONFIG}.bak.${STAMP}"
      if [[ -f "$i3_backup" ]]; then
        mv -f -- "$i3_backup" "$I3_CONFIG"
      elif [[ "$had_i3" -eq 0 ]]; then
        rm -f -- "$I3_CONFIG"
      fi
      die "la configuración i3 no es válida después de añadir Conky: $I3_CONFIG"
    fi
    ok 'autoinicio de Conky integrado en i3'
  else
    warn "no existe $I3_CONFIG; i3 deberá integrarse manualmente"
  fi
  write_openbox_block > "$block_file"
  replace_block "$OPENBOX_AUTOSTART" "$OPENBOX_BEGIN" "$OPENBOX_END" "$block_file"
  rm -f -- "$block_file"
  ok 'autoinicio de Conky integrado en Openbox'
}

show_status() {
  local instance_count=0
  echo '═══ Panel Conky ThinkPad ═══'
  if dpkg-query -W -f='${Status}' conky-all 2>/dev/null | grep -q 'install ok installed'; then ok 'conky-all instalado'; else warn 'conky-all no está instalado'; fi
  printf 'config=%s\nhelper=%s\nlauncher=%s\n' "$CONKY_CONFIG" "$HELPER_TARGET" "$LAUNCHER_TARGET"
  if [[ -f "$CONKY_CONFIG" ]]; then ok 'configuración Conky presente'; else warn 'configuración Conky ausente'; fi
  if [[ -x "$HELPER_TARGET" ]]; then ok 'helper Conky presente'; else warn 'helper Conky ausente'; fi
  if [[ -x "$LAUNCHER_TARGET" ]]; then ok 'lanzador Conky presente'; else warn 'lanzador Conky ausente'; fi
  if [[ -f "$I3_CONFIG" ]] && grep -Fq "$I3_BEGIN" "$I3_CONFIG"; then ok 'bloque Conky presente en i3'; else warn 'bloque Conky ausente en i3'; fi
  if [[ -f "$OPENBOX_AUTOSTART" ]] && grep -Fq "$OPENBOX_BEGIN" "$OPENBOX_AUTOSTART"; then ok 'bloque Conky presente en Openbox'; else warn 'bloque Conky ausente en Openbox'; fi
  if command -v pgrep >/dev/null 2>&1; then instance_count="$(pgrep -u "$(id -u)" -x conky 2>/dev/null | wc -l | awk '{$1=$1; print}' || true)"; fi
  printf 'instancias-usuario=%s\nDISPLAY=%s\n' "$instance_count" "${DISPLAY:-ausente}"
  [[ -z "${DISPLAY:-}" ]] && info 'sin DISPLAY: el diagnóstico no intenta iniciar Conky'
}

main() {
  parse_args "$@"
  require_platform
  require_commands
  validate_sources
  case "$ACTION" in
    check)
      echo '═══ Comprobación de Conky ═══'
      if candidate_available; then
        ok 'conky-all tiene candidato APT'
      elif package_installed; then
        ok 'conky-all ya está instalado aunque APT no ofrece candidato activo'
      else
        warn 'conky-all no tiene candidato APT'
      fi
      printf 'plantilla=%s\nhelper=%s\nlanzador=%s\n' "$SOURCE_CONFIG" "$SOURCE_HELPER" "$SOURCE_LAUNCHER"
      show_status
      ;;
    plan)
      echo '═══ Plan de instalación de Conky ═══'
      if candidate_available; then
        info '[plan] instalar conky-all desde Debian'
      elif package_installed; then
        info '[plan] conservar conky-all ya instalado; APT no ofrece candidato activo'
      else
        warn 'conky-all no tiene candidato APT'
      fi
      info "[plan] instalar $CONKY_CONFIG"
      info "[plan] instalar $HELPER_TARGET y $LAUNCHER_TARGET"
      info '[plan] actualizar los bloques administrados de i3 y Openbox'
      info '[plan] no modificar i3bar, i3status, tint2, Xorg, NetworkManager, WWAN ni Picom'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      if ! candidate_available && ! package_installed; then
        die 'conky-all no está instalado y no tiene candidato APT; revisa las fuentes Debian'
      fi
      if candidate_available; then
        sudo -v
        sudo apt-get update
        sudo apt-get install -y conky-all
      else
        info 'conky-all ya está instalado; se omite APT porque no hay candidato activo'
      fi
      configure_integrations
      ok 'Conky instalado; inicia al entrar en i3 u Openbox'
      ;;
    status) show_status ;;
  esac
}

main "$@"
