#!/usr/bin/env bash
# install_eww_linux.sh v1.0.0
# Compila EWW fijado para X11 y prepara un widget opcional sin autostart.
# shellcheck disable=SC2015
set -Eeuo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export LC_ALL=C

ACTION=check
VERSION="v0.6.0"
STAMP="$(date +%Y%m%d_%H%M%S)"
SOURCE_ROOT="$HOME/.local/share/rafex/eww/${VERSION}-src"
TARGET="$HOME/.local/bin/eww"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/eww"

BUILD_PACKAGES=(git cargo rustc build-essential pkg-config libgtk-3-dev libpango1.0-dev
  libdbusmenu-gtk3-dev libcairo2-dev libglib2.0-dev libgdk-pixbuf-2.0-dev)

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check;;
      --plan|--dry-run) ACTION=plan;;
      --apply) ACTION=apply;;
      --status) ACTION=status;;
      --help|-h) printf 'Uso: install_eww_linux.sh --check|--plan|--apply|--status\n'; exit 0;;
      *) die "opción desconocida: $1";;
    esac
    shift
  done
}

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
candidate() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" {ok=1} END {exit !ok}'; }
backup() { [[ -e "$1" ]] && { cp -a -- "$1" "$1.bak.$STAMP"; info "respaldo: $1.bak.$STAMP"; } || true; }

write_config() {
  local yuck="$CONFIG_ROOT/eww.yuck" scss="$CONFIG_ROOT/eww.scss"
  mkdir -p -- "$CONFIG_ROOT"
  if [[ -e "$yuck" ]] && ! grep -Fq 'Rafex EWW status' "$yuck"; then backup "$yuck"; fi
  if [[ -e "$scss" ]] && ! grep -Fq 'Rafex EWW status' "$scss"; then backup "$scss"; fi
  cat > "$yuck" <<'EOF'
;; Rafex EWW status — no reserva espacio y no se inicia automáticamente.
(defpoll battery :interval "10s" :initial "N/D" "upower -i $(upower -e | grep battery | head -n 1) 2>/dev/null | awk -F: '/percentage/ {gsub(/ /, \"\", $2); print $2; exit}' || printf N/D")
(defpoll volume :interval "10s" :initial "N/D" "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100) \"%\"}' || printf N/D")
(defpoll network :interval "10s" :initial "N/D" "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1 == \"wifi\" {print $2; exit}' || printf N/D")
(defpoll theme :interval "30s" :initial "nord" "head -n 1 ~/.config/rafex/theme 2>/dev/null || printf nord")

(defwidget row [label value]
  (box :class "row" :orientation "h" :space-evenly false
    (label :class "label" :text label)
    (label :class "value" :text value)))

(defwindow status
  :monitor 0
  :geometry (geometry :x "18px" :y "48px" :width "280px" :height "150px" :anchor "top left")
  :stacking "bg"
  :wm-ignore true
  :windowtype "normal"
  (box :class "panel" :orientation "v"
    (label :class "title" :text "RAFEX · THINKPAD")
    (row :label "Batería" :value battery)
    (row :label "Audio" :value volume)
    (row :label "Wi-Fi" :value network)
    (row :label "Tema" :value theme)
    (label :class "hint" :text "EWW opcional · sin reserva")))
EOF
  cat > "$scss" <<'EOF'
/* Rafex EWW status — no reserva espacio y no se inicia automáticamente. */
.panel { background: rgba(46, 52, 64, 0.92); color: #e5e9f0; padding: 14px; border-radius: 8px; }
.title { color: #88c0d0; font-weight: bold; margin-bottom: 8px; }
.row { margin: 2px 0; }
.label { color: #81a1c1; min-width: 90px; }
.value { color: #eceff4; }
.hint { color: #a3be8c; margin-top: 8px; font-size: 10px; }
EOF
}

show_status() {
  echo "═══ EWW ${VERSION} ThinkPad ═══"
  command -v eww >/dev/null 2>&1 && ok "eww disponible: $(eww --version 2>/dev/null | head -n 1)" || warn 'eww no está instalado'
  [[ -x "$TARGET" ]] && ok "binario local: $TARGET" || warn "binario ausente: $TARGET"
  [[ -f "$CONFIG_ROOT/eww.yuck" && -f "$CONFIG_ROOT/eww.scss" ]] && ok "configuración: $CONFIG_ROOT" || warn 'configuración EWW ausente'
  if [[ -n "${DISPLAY:-}" && -x "$TARGET" ]]; then
    "$TARGET" ping >/dev/null 2>&1 && ok 'daemon EWW responde' || info 'daemon EWW detenido (normal: no hay autostart)'
  else
    info 'sin DISPLAY o binario; no se intenta iniciar EWW'
  fi
}

main() {
  parse_args "$@"
  [[ "$(uname -s)" == Linux ]] || die 'este instalador requiere Linux'
  command -v apt-cache >/dev/null 2>&1 || die 'falta apt-cache'
  case "$ACTION" in
    check)
      echo "═══ Comprobación EWW ${VERSION} ═══"
      local missing=() p
      for p in "${BUILD_PACKAGES[@]}"; do installed "$p" || missing+=("$p"); done
      ((${#missing[@]} == 0)) && ok 'dependencias de compilación instaladas' || warn "dependencias pendientes: ${missing[*]}"
      for p in "${BUILD_PACKAGES[@]}"; do installed "$p" || { candidate "$p" || warn "sin candidato APT: $p"; }; done
      show_status
      ;;
    plan)
      echo "═══ Plan EWW ${VERSION} ═══"
      info '[plan] instalar dependencias de compilación disponibles mediante APT'
      info "[plan] clonar ${VERSION} bajo $SOURCE_ROOT"
      info '[plan] compilar con --no-default-features --features x11'
      info "[plan] instalar $TARGET y configurar $CONFIG_ROOT"
      info '[plan] no activar autostart ni reservar espacio del escritorio'
      ;;
    apply)
      command -v sudo >/dev/null 2>&1 || die 'sudo no está instalado'
      local apt_packages=() p
      for p in "${BUILD_PACKAGES[@]}"; do
        if ! installed "$p"; then candidate "$p" || die "sin candidato APT: $p"; apt_packages+=("$p"); fi
      done
      if ((${#apt_packages[@]})); then sudo -v; sudo apt-get update; sudo apt-get install -y "${apt_packages[@]}"; fi
      command -v git >/dev/null 2>&1 || die 'falta git'
      command -v cargo >/dev/null 2>&1 || die 'falta cargo'
      mkdir -p -- "$(dirname -- "$SOURCE_ROOT")" "$HOME/.local/bin"
      if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
        git clone --branch "$VERSION" --depth 1 https://github.com/elkowar/eww.git "$SOURCE_ROOT"
      fi
      (cd "$SOURCE_ROOT" && cargo build --release --no-default-features --features x11)
      [[ -x "$SOURCE_ROOT/target/release/eww" ]] || die 'la compilación no produjo target/release/eww'
      if [[ -e "$TARGET" ]] && ! cmp -s "$SOURCE_ROOT/target/release/eww" "$TARGET"; then backup "$TARGET"; fi
      install -m 0755 -- "$SOURCE_ROOT/target/release/eww" "$TARGET"
      write_config
      ok "EWW ${VERSION} instalado sin autostart; usa eww-widgets --open status"
      ;;
    status) show_status;;
  esac
}

main "$@"
