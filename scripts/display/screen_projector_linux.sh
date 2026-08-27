#!/usr/bin/env bash
# shellcheck shell=bash
# Controla la pantalla interna y un monitor/proyector externo en Xorg.
set -Eeuo pipefail

ACTION="check"
REQUESTED_MODE="status"
SCREEN_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/screen-projector"
SCREEN_STATE_FILE="$SCREEN_STATE_DIR/mode"
SCREEN_LOCK_FILE="$SCREEN_STATE_DIR/lock"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  screen_projector_linux.sh --check
  screen_projector_linux.sh --mode next
  screen_projector_linux.sh --mode internal|extend|mirror
  screen_projector_linux.sh --plan --mode next

Modos:
  internal  Solo pantalla interna.
  extend    Escritorio extendido; el externo queda a la derecha.
  mirror    Duplica la pantalla interna en el externo.
  next      Cicla internal → extend → mirror → internal.
  status    Muestra salidas y modo registrado, sin modificar nada.

Variables:
  SCREEN_INTERNAL  Fija la salida interna de xrandr.
  SCREEN_EXTERNAL  Fija la salida externa/proyector de xrandr.
  XDG_STATE_HOME   Directorio para estado y lock del usuario.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --mode)
        [[ $# -ge 2 ]] || die "--mode requiere un modo"
        REQUESTED_MODE="$2"
        shift 2
        ;;
      --status) REQUESTED_MODE="status"; ACTION="check"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
  case "$REQUESTED_MODE" in
    internal|extend|mirror|next|status) ;;
    *) die "modo inválido: $REQUESTED_MODE" ;;
  esac
}

require_session() {
  command -v xrandr >/dev/null 2>&1 || die "xrandr no está instalado"
  [[ -n "${DISPLAY:-}" ]] || die "DISPLAY no está definido; ejecuta el comando dentro de i3/Xorg"
  xrandr --query >/dev/null 2>&1 || die "no se pudo acceder a la sesión Xorg actual"
}

connected_outputs() { xrandr --query | awk '$2 == "connected" {print $1}'; }

is_connected() {
  local output="$1"
  xrandr --query | awk -v output="$output" \
    '$1 == output && $2 == "connected" {found=1} END {exit(found ? 0 : 1)}'
}

detect_internal() {
  local output="${SCREEN_INTERNAL:-}"
  if [[ -n "$output" ]]; then
    is_connected "$output" || die "SCREEN_INTERNAL no está conectada: $output"
    printf '%s\n' "$output"
    return
  fi
  output="$(connected_outputs | awk '$0 ~ /^(eDP|LVDS|DSI)(-|[0-9]|$)/ {print; exit}')"
  [[ -n "$output" ]] || output="$(connected_outputs | head -n 1)"
  [[ -n "$output" ]] || die "no se detectó una salida conectada"
  printf '%s\n' "$output"
}

detect_external() {
  local internal="$1" output="${SCREEN_EXTERNAL:-}"
  if [[ -n "$output" ]]; then
    is_connected "$output" && [[ "$output" != "$internal" ]] || return 1
    printf '%s\n' "$output"
    return
  fi
  connected_outputs | awk -v internal="$internal" \
    '$0 != internal && $0 ~ /^(HDMI|DP|DVI|VGA|DisplayPort|USB-C)(-|[0-9]|$)/ {print; exit}'
}

current_mode() {
  local output="$1"
  xrandr --query | awk -v output="$output" '
    $1 == output && $2 == "connected" {inside=1; next}
    inside && $1 ~ /^[A-Za-z][A-Za-z0-9-]*$/ && $2 == "connected" {exit}
    inside && $1 ~ /^[0-9]+x[0-9]+$/ && $0 ~ /\*/ {print $1; exit}
  '
}

first_mode() {
  local output="$1"
  xrandr --query | awk -v output="$output" '
    $1 == output && $2 == "connected" {inside=1; next}
    inside && $1 ~ /^[A-Za-z][A-Za-z0-9-]*$/ && $2 == "connected" {exit}
    inside && $1 ~ /^[0-9]+x[0-9]+$/ {
      if ($0 ~ /\+/) {print $1; found=1; exit}
      if (!first) first=$1
    }
    END {if (!found && first) print first}
  '
}

mode_width() { printf '%s\n' "${1%x*}"; }
mode_height() { printf '%s\n' "${1#*x}"; }

notify() {
  local title="$1" message="$2" icon="${3:-video-display}"
  [[ "$ACTION" == "plan" ]] && return 0
  if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    notify-send -u normal -t 1800 -i "$icon" "$title" "$message" || true
  fi
}

read_state() {
  local state=""
  if [[ -r "$SCREEN_STATE_FILE" ]]; then
    IFS= read -r state < "$SCREEN_STATE_FILE" || true
  fi
  case "$state" in
    internal|extend|mirror) printf '%s\n' "$state" ;;
    *) printf '%s\n' internal ;;
  esac
}

next_mode() {
  local external="$2" state
  [[ -n "$external" ]] || { printf '%s\n' internal; return; }
  state="$(read_state)"
  case "$state" in
    internal) printf '%s\n' extend ;;
    extend) printf '%s\n' mirror ;;
    mirror) printf '%s\n' internal ;;
    *) printf '%s\n' internal ;;
  esac
}

write_state() {
  local mode="$1"
  mkdir -p "$SCREEN_STATE_DIR"
  printf '%s\n' "$mode" > "$SCREEN_STATE_FILE"
}

xrandr_apply() {
  if [[ "$ACTION" == "plan" ]]; then
    printf '%s\n' "[plan] xrandr $*"
  else
    xrandr "$@"
  fi
}

disable_other_outputs_args() {
  local internal="$1" external="${2:-}" output
  while IFS= read -r output; do
    [[ -n "$output" && "$output" != "$internal" && "$output" != "$external" ]] || continue
    printf '%s\0' --output "$output" --off
  done < <(connected_outputs)
}

apply_internal() {
  local internal="$1" item
  local args=(--output "$internal" --auto --primary --rotate normal)
  while IFS= read -r -d '' item; do args+=("$item"); done < <(disable_other_outputs_args "$internal")
  xrandr_apply "${args[@]}"
  ok "solo pantalla interna: $internal"
  notify "Pantalla" "Solo pantalla interna ($internal)"
}

apply_extend() {
  local internal="$1" external="$2"
  local args=(--output "$internal" --auto --primary --rotate normal
              --output "$external" --auto --right-of "$internal" --rotate normal)
  local item
  while IFS= read -r -d '' item; do args+=("$item"); done < <(disable_other_outputs_args "$internal" "$external")
  xrandr_apply "${args[@]}"
  ok "escritorio extendido: $internal + $external"
  notify "Pantalla" "Escritorio extendido; proyector en $external"
}

apply_mirror() {
  local internal="$1" external="$2"
  local internal_mode external_mode internal_width internal_height
  internal_mode="$(current_mode "$internal")"
  [[ -n "$internal_mode" ]] || internal_mode="$(first_mode "$internal")"
  external_mode="$(current_mode "$external")"
  [[ -n "$external_mode" ]] || external_mode="$(first_mode "$external")"
  [[ -n "$internal_mode" && -n "$external_mode" ]] || \
    die "no se encontró un modo de vídeo para $internal y $external"

  internal_width="$(mode_width "$internal_mode")"
  internal_height="$(mode_height "$internal_mode")"
  local args=(--output "$internal" --mode "$internal_mode" --primary --rotate normal
              --output "$external" --mode "$external_mode" --same-as "$internal" --rotate normal)
  if [[ "$internal_mode" != "$external_mode" ]]; then
    args+=(--scale-from "${internal_width}x${internal_height}")
    info "el externo no tiene $internal_mode; se usará escalado desde ${internal_width}x${internal_height}"
  fi
  local item
  while IFS= read -r -d '' item; do args+=("$item"); done < <(disable_other_outputs_args "$internal" "$external")
  xrandr_apply "${args[@]}"
  ok "pantallas duplicadas: $internal + $external"
  notify "Pantalla" "Espejo activo en $external"
}

print_status() {
  local internal external
  internal="$(detect_internal)"
  external="$(detect_external "$internal" || true)"
  echo "Salida interna: $internal"
  echo "Salida externa: ${external:-ninguna}"
  echo "Modo registrado: $(read_state)"
  echo
  xrandr --query
}

main() {
  local internal external target
  parse_args "$@"
  require_session
  internal="$(detect_internal)"
  external="$(detect_external "$internal" || true)"

  if [[ "$REQUESTED_MODE" == "status" || "$ACTION" == "check" ]]; then
    print_status
    exit 0
  fi
  if [[ "$REQUESTED_MODE" == "next" ]]; then
    target="$(next_mode "$internal" "$external")"
  else
    target="$REQUESTED_MODE"
  fi
  if [[ "$target" != internal && -z "$external" ]]; then
    warn "no hay monitor/proyector externo conectado; se aplicará solo pantalla interna"
    target=internal
  fi

  if [[ "$ACTION" == "apply" ]]; then
    mkdir -p "$SCREEN_STATE_DIR"
    exec 9>"$SCREEN_LOCK_FILE"
    flock -n 9 || die "ya hay otro cambio de pantalla en curso"
  fi
  case "$target" in
    internal) apply_internal "$internal" ;;
    extend) apply_extend "$internal" "$external" ;;
    mirror) apply_mirror "$internal" "$external" ;;
    *) die "modo inválido: $target" ;;
  esac
  if [[ "$ACTION" == "apply" ]]; then
    write_state "$target"
  else
    info "[plan] no se guardó el estado"
  fi
}

main "$@"
