#!/usr/bin/env bash
# configure_eww_battery_linux.sh v1.0.0
# Añade telemetría de alimentación de 10 segundos al dashboard EWW Rafex.
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

readonly VERSION="v1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly SOURCE_HELPER="${REPO_ROOT}/scripts/system/eww_battery_status_linux.sh"
readonly TARGET_HELPER="$HOME/.local/bin/eww-battery-status.sh"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"
readonly TARGET_YUCK="${CONFIG_ROOT}/eww.yuck"
readonly BACKUP_ROOT="$HOME/.local/share/rafex/eww-battery/rollback"
readonly BEGIN_POLL=";; BEGIN rafex EWW battery telemetry"
readonly END_POLL=";; END rafex EWW battery telemetry"
readonly BEGIN_CARD=";; BEGIN rafex EWW battery telemetry card"
readonly END_CARD=";; END rafex EWW battery telemetry card"

ACTION=check
STAMP="$(date '+%Y%m%d_%H%M%S')"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  configure_eww_battery_linux.sh --check
  configure_eww_battery_linux.sh --plan
  configure_eww_battery_linux.sh --status
  configure_eww_battery_linux.sh --apply
  configure_eww_battery_linux.sh --rollback

Añade a EWW un defpoll de 10 segundos con AC, carga, estado y salud
estimada. La salud procede de UPower cuando está disponible y no equivale
al porcentaje de carga actual.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --plan|--dry-run) ACTION=plan ;;
      --status) ACTION=status ;;
      --apply) ACTION=apply ;;
      --rollback) ACTION=rollback ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

require_linux_user() {
  [[ "$(uname -s)" == Linux ]] || die 'este script solo funciona en Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal'
}

require_commands() {
  local command_name
  for command_name in awk cmp cp date grep install mktemp mv rm; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: ${command_name}"
  done
}

validate_source() {
  [[ -s "$SOURCE_HELPER" ]] || die "falta el helper: $SOURCE_HELPER"
  [[ -s "$TARGET_YUCK" ]] || die "falta $TARGET_YUCK; ejecuta primero just install-eww --apply"
  grep -Fq 'BEGIN rafex EWW dashboard' "$TARGET_YUCK" || die 'el Yuck no parece una configuración EWW administrada'
}

block_file() {
  local kind="$1"
  case "$kind" in
    poll)
      cat <<'EOF'
;; BEGIN rafex EWW battery telemetry
(defpoll rafex-battery-telemetry :interval "10s" :initial "AC: N/D\nCarga: N/D\nEstado: N/D\nSalud: N/D" "$HOME/.local/bin/eww-battery-status.sh")
;; END rafex EWW battery telemetry
EOF
      ;;
    card)
      cat <<'EOF'
;; BEGIN rafex EWW battery telemetry card
(box :class "card compact-card battery-telemetry-card" :orientation "v" :space-evenly false
  (box :class "section-line" :orientation "h" :space-evenly false
    (label :class "card-title" :text "⚡  Telemetría" :xalign 0)
    (label :class "status-dot" :text "●" :xalign 1))
  (label :class "value compact telemetry-value" :text rafex-battery-telemetry :xalign 0 :wrap true)
  (label :class "hint" :text "Actualización cada 10 s · salud estimada" :xalign 0))
;; END rafex EWW battery telemetry card
EOF
      ;;
    *) die "bloque desconocido: $kind" ;;
  esac
}

replace_block() {
  local target="$1" begin="$2" end="$3" block="$4" anchor="${5:-}" temporary
  temporary="$(mktemp)"
  awk -v begin="$begin" -v end="$end" -v block="$block" -v anchor="$anchor" '
    function emit(line) {
      while ((getline line < block) > 0) print line
      close(block)
    }
    $0 == begin {
      if (!found) emit()
      inside=1
      found=1
      next
    }
    inside && $0 == end { inside=0; next }
    anchor != "" && $0 == anchor && !found && !inserted {
      emit()
      inserted=1
    }
    !inside { print }
    END { if (!found && !inserted) { print ""; emit() } }
  ' "$target" > "$temporary"
  if cmp -s "$target" "$temporary"; then
    rm -f -- "$temporary"
    return 0
  fi
  chmod --reference="$target" "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$target"
}

remove_block() {
  local target="$1" begin="$2" end="$3" temporary
  temporary="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside=1; next }
    inside && $0 == end { inside=0; next }
    !inside { print }
  ' "$target" > "$temporary"
  chmod --reference="$target" "$temporary" 2>/dev/null || true
  if cmp -s "$target" "$temporary"; then
    rm -f -- "$temporary"
  else
    mv -f -- "$temporary" "$target"
  fi
}

install_helper() {
  local temporary
  mkdir -p -- "$(dirname -- "$TARGET_HELPER")"
  temporary="$(mktemp "${TARGET_HELPER}.tmp.XXXXXX")"
  cp -- "$SOURCE_HELPER" "$temporary"
  chmod 0700 "$temporary"
  mv -f -- "$temporary" "$TARGET_HELPER"
}

backup_yuck() {
  local backup_dir="$BACKUP_ROOT/$STAMP"
  mkdir -p -- "$backup_dir"
  chmod 0700 -- "$BACKUP_ROOT" "$backup_dir"
  cp -p -- "$TARGET_YUCK" "$backup_dir/eww.yuck"
  info "respaldo creado: $backup_dir/eww.yuck"
}

latest_backup() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -n 1
}

show_status() {
  echo "═══ Telemetría de batería EWW ${VERSION} ═══"
  printf 'configuración=%s\n' "$TARGET_YUCK"
  printf 'helper=%s\n' "$TARGET_HELPER"
  if [[ -x "$TARGET_HELPER" ]]; then
    ok 'helper instalado'
  else
    warn 'helper no instalado'
  fi
  if [[ -f "$TARGET_YUCK" ]] && grep -Fqx "$BEGIN_POLL" "$TARGET_YUCK" && grep -Fqx "$BEGIN_CARD" "$TARGET_YUCK"; then
    ok 'bloques EWW administrados presentes'
  else
    warn 'bloques EWW administrados ausentes'
  fi
  if [[ -n "${DISPLAY:-}" && -x "$HOME/.local/bin/eww-widgets.sh" ]]; then
    info 'puedes recargar con: just eww-widgets --reload'
  else
    info 'sin DISPLAY o helper EWW; no se recarga automáticamente'
  fi
}

apply_config() {
  local poll card
  validate_source
  poll="$(mktemp)"
  card="$(mktemp)"
  block_file poll > "$poll"
  block_file card > "$card"
  backup_yuck >/dev/null
  replace_block "$TARGET_YUCK" "$BEGIN_POLL" "$END_POLL" "$poll"
  replace_block "$TARGET_YUCK" "$BEGIN_CARD" "$END_CARD" "$card" ";; END rafex EWW dashboard"
  install_helper
  rm -f -- "$poll" "$card"
  ok 'telemetría EWW instalada: AC, Carga, Estado y Salud'
  if [[ -n "${DISPLAY:-}" && -x "$HOME/.local/bin/eww-widgets.sh" ]]; then
    "$HOME/.local/bin/eww-widgets.sh" --reload || warn 'no se pudo recargar EWW; ejecuta just eww-widgets --reload'
  else
    warn 'recarga EWW pendiente dentro de la sesión gráfica'
  fi
}

rollback_config() {
  local backup_dir
  [[ -f "$TARGET_YUCK" ]] || die "falta $TARGET_YUCK"
  backup_dir="$(latest_backup)"
  [[ -n "$backup_dir" && -f "$backup_dir/eww.yuck" ]] || die "no hay respaldo EWW en $BACKUP_ROOT"
  if ! grep -Fq 'BEGIN rafex EWW dashboard' "$TARGET_YUCK"; then
    die 'el Yuck actual no parece administrado; no se modifica'
  fi
  remove_block "$TARGET_YUCK" "$BEGIN_POLL" "$END_POLL"
  remove_block "$TARGET_YUCK" "$BEGIN_CARD" "$END_CARD"
  if [[ -f "$TARGET_HELPER" ]] && cmp -s "$SOURCE_HELPER" "$TARGET_HELPER"; then
    rm -f -- "$TARGET_HELPER"
  fi
  ok 'bloques de telemetría y helper administrado retirados'
  info "el respaldo completo queda disponible en $backup_dir/eww.yuck"
  if [[ -n "${DISPLAY:-}" && -x "$HOME/.local/bin/eww-widgets.sh" ]]; then
    "$HOME/.local/bin/eww-widgets.sh" --reload || warn 'no se pudo recargar EWW'
  fi
}

main() {
  parse_args "$@"
  require_linux_user
  require_commands
  case "$ACTION" in
    check)
      validate_source
      ok 'configuración EWW y helper fuente válidos; no se modificó nada'
      ;;
    plan)
      validate_source
      echo "═══ Plan telemetría batería EWW ═══"
      info "instalar $TARGET_HELPER"
      info "añadir defpoll de 10s y tarjeta administrada a $TARGET_YUCK"
      info 'recargar únicamente la instancia EWW administrada si DISPLAY está disponible'
      info 'no ejecutar watch, sudo ni comandos de energía'
      ;;
    status) show_status ;;
    apply) apply_config ;;
    rollback) rollback_config ;;
  esac
}

main "$@"
