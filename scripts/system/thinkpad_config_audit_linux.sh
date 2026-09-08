#!/usr/bin/env bash
# shellcheck shell=bash
# thinkpad_config_audit_linux.sh v1.0.0
# Audita propietarios, bloques y dependencias de la sesión ThinkPad sin escribir
# salvo al solicitar explícitamente --report --output.
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE_ROOT="$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
REGISTRY="$PROFILE_ROOT/thinkpad-ownership.tsv"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/thinkpad-config"
ACTION=status
OUTPUT=''
FAILURES=0

usage() {
  cat <<'EOF'
Uso:
  thinkpad_config_audit_linux.sh --check
  thinkpad_config_audit_linux.sh --status
  thinkpad_config_audit_linux.sh --report [--output <archivo>]

No modifica la configuración. Con --output escribe un reporte Markdown fuera
del repositorio; por defecto, --report se imprime en stdout.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION=check ;;
      --status) ACTION=status ;;
      --report) ACTION=report ;;
      --output)
        shift
        (($#)) || { usage >&2; exit 2; }
        OUTPUT="$1"
        ;;
      --help|-h) usage; exit 0 ;;
      *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
  done
}

emit() { printf '%s\n' "$*"; }
ok() { emit "✓ $*"; }
warn() { emit "⚠ $*"; FAILURES=$((FAILURES + 1)); }

relative_home() {
  local path="$1"
  printf '%s\n' "${path/#$HOME/~}"
}

list_registry() {
  awk -F'|' '
    BEGIN {
      print "| Recurso | Propietario | Destino o bloque | Dependencias | Validador | Exclusiones | Política |"
      print "|---|---|---|---|---|---|---|"
    }
    /^#/ || NF < 7 { next }
    { printf "| `%s` | `%s` | `%s` | `%s` | `%s` | `%s` | %s |\n", $1, $2, $3, $4, $5, $6, $7 }
  ' "$REGISTRY"
}

script_surface() {
  local script="$1" data tags=() name
  name="$(basename -- "$script")"
  case "$name" in
    *firefoxos*|*android*|*java*|*node*|*graal*|*maven*|*gradle*)
      printf '%s' 'fuera-superficie-escritorio'
      return 0
      ;;
  esac
  data="$(<"$script")"
  [[ "$data" == *I3_CONFIG* || "$data" == *'.config/i3/config'* ]] && tags+=(i3)
  [[ "$data" == *openbox/* || "$data" == *OPENBOX_* ]] && tags+=(openbox)
  [[ "$data" == *eww.yuck* || "$data" == *eww.scss* ]] && tags+=(EWW)
  [[ "$data" == *conky.conf* ]] && tags+=(Conky)
  [[ "$data" == *picom* ]] && tags+=(Picom)
  [[ "$data" == *polybar* || "$data" == *tint2* || "$data" == *rafex-bar-active* ]] && tags+=(barras)
  [[ "$data" == *'/etc/X11'* || "$data" == *xorg.conf* ]] && tags+=(Xorg)
  [[ "$data" == *'/etc/default/grub'* || "$data" == *update-initramfs* || "$data" == *logind.conf* ]] && tags+=(arranque-energía)
  [[ "$data" == *NetworkManager* || "$data" == *nmcli* || "$data" == *ufw* ]] && tags+=(red)
  [[ "$data" == *'.local/bin'* ]] && tags+=(helpers)
  (IFS=,; printf '%s' "${tags[*]:-consulta}")
}

list_scripts() {
  local script display_path
  emit '| Script | Superficies detectadas |'
  emit '|---|---|'
  while IFS= read -r script; do
    display_path="${script#"$REPO_ROOT"/}"
    emit "| \`$display_path\` | $(script_surface "$script") |"
  done < <(
    {
      rg -l -i '(thinkpad|x1.yoga|i3|openbox|eww|picom|conky|ratmenu|ulauncher|polybar|tint2|touchpad|tpm|mem_sleep|lid|tlp|brightness|wifi|flight|screen|dunst|wallpaper|theme|clipboard|power|wacom|udisk)' \
        "$REPO_ROOT/scripts" --glob '*.sh' --glob '*.bash' || true
      if [[ -f "$REPO_ROOT/dotfiles/install.sh" ]] && rg -qi '(thinkpad|i3|openbox|eww|picom|conky|bar|wallpaper)' "$REPO_ROOT/dotfiles/install.sh"; then
        printf '%s\n' "$REPO_ROOT/dotfiles/install.sh"
      fi
    } | sort -u
  )
}

check_file() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    ok "$label: $(relative_home "$path")"
  else
    warn "$label ausente: $(relative_home "$path")"
  fi
}

check_i3_binding() {
  local label="$1" pattern="$2"
  if [[ -f "$CONFIG_HOME/i3/config" ]] && grep -Eq "$pattern" "$CONFIG_HOME/i3/config"; then
    ok "$label"
  else
    warn "$label no está configurado"
  fi
}

validate_registry() {
  local duplicate_resource duplicate_target
  duplicate_resource="$(awk -F'|' '!/^#/ && NF >= 7 { count[$1]++ } END { for (key in count) if (count[key] > 1) print key }' "$REGISTRY" | awk 'NF { printf "%s%s", separator, $0; separator = "," } END { print "" }')"
  duplicate_target="$(awk -F'|' '!/^#/ && NF >= 7 { count[$3]++ } END { for (key in count) if (count[key] > 1) print key }' "$REGISTRY" | awk 'NF { printf "%s%s", separator, $0; separator = "," } END { print "" }')"
  if [[ -z "$duplicate_resource" ]]; then
    ok 'registro: un propietario por recurso'
  else
    warn "registro: recursos duplicados: $duplicate_resource"
  fi
  if [[ -z "$duplicate_target" ]]; then
    ok 'registro: destinos y bloques sin duplicados'
  else
    warn "registro: destinos/bloques duplicados: $duplicate_target"
  fi
}

checks() {
  [[ -f "$REGISTRY" ]] || { emit "✗ falta registro: $REGISTRY"; return 2; }
  validate_registry
  check_file 'i3 config' "$CONFIG_HOME/i3/config"
  check_file 'Conky config' "$CONFIG_HOME/conky/conky.conf"
  check_file 'EWW Yuck' "$CONFIG_HOME/eww/eww.yuck"
  check_file 'EWW SCSS' "$CONFIG_HOME/eww/eww.scss"
  check_file 'Picom config' "$CONFIG_HOME/picom/picom.conf"
  check_file 'selector de barra' "$CONFIG_HOME/rafex/i3-bar-profile"
  check_file 'helper ratmenu' "$HOME/.local/bin/rafex-ratmenu.sh"
  check_file 'helper panel Rafex' "$HOME/.local/bin/rafex-control-panel.sh"
  check_i3_binding 'XF86Tools usa ratmenu' 'bindsym[[:space:]]+XF86Tools.*rafex-ratmenu\.sh'
  check_i3_binding 'XF86Search abre DuckDuckGo' 'bindsym[[:space:]]+XF86Search.*duckduckgo\.com'
  # shellcheck disable=SC2016 # el patrón necesita los símbolos $ literales de i3.
  check_i3_binding 'Super+Space usa Ulauncher' 'bindsym[[:space:]]+\$mod\+space.*\$launcher'
  if [[ -f "$CONFIG_HOME/i3/config" ]]; then
    local duplicate
    duplicate="$(awk '/^[[:space:]]*bindsym[[:space:]]/ { n[$2]++ } END { for (key in n) if (n[key] > 1 && key != "$mod+r") print key }' "$CONFIG_HOME/i3/config" | awk 'NF { printf "%s%s", separator, $0; separator = "," } END { print "" }')"
    if [[ -z "$duplicate" ]]; then
      ok 'sin keybindings duplicados fuera del modo resize'
    else
      warn "keybindings duplicados: $duplicate"
    fi
    if command -v i3 >/dev/null 2>&1 && i3 -C -c "$CONFIG_HOME/i3/config" >/dev/null 2>&1; then
      ok 'i3 -C válido'
    else
      warn 'i3 -C no valida la configuración'
    fi
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user cat rafex-picom.service >/dev/null 2>&1; then
      ok 'unidad rafex-picom disponible'
    else
      warn 'unidad rafex-picom ausente'
    fi
  fi
  local process_count selected_bar
  if pgrep -x picom >/dev/null 2>&1; then ok 'Picom activo'; else warn 'Picom no está activo'; fi
  if [[ -x "$HOME/.local/bin/picom" ]]; then
    warn 'existe ~/.local/bin/picom heredado; rafex-picom.service usa /usr/bin/picom, pero retíralo tras validar que no es necesario'
  fi
  if [[ -f /etc/xdg/autostart/picom.desktop && ! -f "$CONFIG_HOME/autostart/picom.desktop" ]]; then
    warn 'Picom genérico sigue disponible para dex; instala el servicio Rafex para aislar su ciclo de vida'
  fi
  # `eww open` puede permanecer asociado a la ventana; no debe contarse como
  # otro daemon. Solo se auditan líneas de comando que solicitan `daemon`.
  process_count="$(pgrep -af '(^|/)eww daemon$' 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [[ "$process_count" -le 1 ]]; then ok "EWW: ${process_count} daemon"; else warn "EWW duplicado: ${process_count} daemons"; fi
  selected_bar='i3bar'
  [[ -f "$CONFIG_HOME/rafex/i3-bar-profile" ]] && selected_bar="$(head -n 1 "$CONFIG_HOME/rafex/i3-bar-profile")"
  case "$selected_bar" in
    tint2|polybar)
      process_count="$(pgrep -x "$selected_bar" 2>/dev/null | wc -l | tr -d ' ' || true)"
      if [[ "$process_count" -le 1 ]]; then ok "$selected_bar: ${process_count} proceso"; else warn "$selected_bar duplicado: ${process_count} procesos"; fi
      ;;
    i3bar) ok 'barra seleccionada: i3bar (gestionada por i3)' ;;
    *) warn "perfil de barra inválido: $selected_bar" ;;
  esac
}

report() {
  emit '# Auditoría de configuración ThinkPad'
  emit
  emit "- Generado: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # shellcheck disable=SC2016 # Markdown con backticks literales.
  emit '- Perfil: `thinkpad-x1-yoga-1st`'
  emit "- Estado: \`$STATE_HOME\`"
  emit
  emit '## Propietarios'
  list_registry
  emit
  emit '## Grafo'
  cat <<'EOF'
```mermaid
flowchart TD
  Profile[dotfiles/install] --> I3[i3 config]
  Controls[i3 controls] --> I3
  Eww[install EWW] --> I3
  Conky[install Conky] --> I3
  Picom[Picom service] --> I3
  Bars[bar selector] --> I3
  Theme[theme toggle] --> I3
  I3 --> Ratmenu[XF86Tools]
  I3 --> Search[XF86Search]
```
EOF
  emit
  emit '## Scripts detectados'
  list_scripts
  emit
  emit '## Comprobaciones actuales'
  checks || true
}

main() {
  parse_args "$@"
  case "$ACTION" in
    report)
      if [[ -n "$OUTPUT" ]]; then
        mkdir -p -- "$(dirname -- "$OUTPUT")"
        report > "$OUTPUT"
        chmod 600 "$OUTPUT"
        emit "reporte=$OUTPUT"
      else
        report
      fi
      ;;
    status|check)
      checks
      [[ "$ACTION" == check && "$FAILURES" -gt 0 ]] && exit 1
      ;;
  esac
}

main "$@"
