#!/usr/bin/env bash
# shellcheck shell=bash
# thinkpad_config_audit_linux.sh v1.1.0
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
HISTORY_ROOT="${RAFEX_THINKPAD_HISTORY:-$HOME/.local/share/rafex-thinkpad}"
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
info() { emit "• $*"; }
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

list_physical_collisions() {
  emit '| Destino físico | Recursos registrados | Propietarios | Políticas |'
  emit '|---|---|---|---|'
  awk -F'|' '
    !/^#/ && NF >= 7 {
      target=$3
      sub(/#.*/, "", target)
      count[target]++
      resources[target]=resources[target] sprintf("`%s` ", $1)
      owners[target]=owners[target] sprintf("`%s` ", $2)
      policies[target]=policies[target] sprintf("`%s` ", $7)
    }
    END {
      for (target in count) {
        if (count[target] > 1) {
          printf "| `%s` | %s | %s | %s |\n", target, resources[target], owners[target], policies[target]
        }
      }
    }
  ' "$REGISTRY" | sort
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

list_target_writer_candidates() {
  local script display_path guard surface
  emit '| Script | Superficie | Modo de escritura |'
  emit '|---|---|---|'
  while IFS= read -r script; do
    display_path="${script#"$REPO_ROOT"/}"
    case "$display_path" in
      scripts/system/thinkpad_config_audit_linux.sh|scripts/backup/*)
        continue
        ;;
    esac
    if ! rg -q '(^|[[:space:]])(cp|mv|install|ln|sed|awk|tee|printf|cat)[[:space:]].*(\.config/i3/config|I3_CONFIG|\.config/eww|\.config/picom|i3-bars|openbox|tlp\.d|xorg\.conf\.d)' "$script" \
      && [[ "$display_path" != scripts/install/migrate_laptop_linux.sh ]] \
      && [[ "$display_path" != scripts/system/generate_terminal_themes_linux.sh ]] \
      && [[ "$display_path" != dotfiles/install.sh ]]; then
      continue
    fi
    if [[ "$display_path" == dotfiles/install.sh ]]; then
      guard='seed-only (no sobrescribe)'
    elif rg -q 'rafex_i3_fragment_replace|GENERATED_EWW_CONFIG' "$script"; then
      guard='fragment-aware / destino generado'
    elif rg -q 'thinkpad_config_guard|rafex_guard_require_owner' "$script"; then
      guard='guardado, bloque o archivo exclusivo'
    else
      guard='NO — conflicto potencial'
    fi
    surface='i3/EWW/Picom/barras/Openbox/hardware'
    emit "| \`$display_path\` | $surface | $guard |"
  done < <(
    rg -l --glob '*.sh' --glob '*.py' --glob '*.just' \
      '(\.config/i3/config|I3_CONFIG|\.config/eww|\.config/picom|i3-bars|openbox|tlp\.d|xorg\.conf\.d)' \
      "$REPO_ROOT/scripts" "$REPO_ROOT/dotfiles" 2>/dev/null | sort -u
  )
}

list_graph() {
  emit '```mermaid'
  emit 'flowchart TD'
  emit '  Profile[ThinkPad Rafex]'
  awk -F'|' '
    !/^#/ && NF >= 7 {
      owner=$2; owner_id=owner; gsub(/[^A-Za-z0-9_]/, "_", owner_id)
      resource=$1; resource_id=resource; gsub(/[^A-Za-z0-9_]/, "_", resource_id)
      target=$3; gsub(/"/, "\\\"", target)
      owners[owner_id]=owner
      resources[resource_id]=resource
      labels[resource_id]=target
      edges[owner_id "\034" resource_id]=1
    }
    END {
      for (owner_id in owners) printf "  Owner_%s[\"%s\"]\n", owner_id, owners[owner_id]
      for (resource_id in resources) printf "  Resource_%s[\"%s — %s\"]\n", resource_id, resources[resource_id], labels[resource_id]
      for (edge in edges) {
        split(edge, parts, "\034")
        printf "  Owner_%s --> Resource_%s\n", parts[1], parts[2]
      }
    }
  ' "$REGISTRY" | sort
  emit '  Profile --> Owner_rafex_config'
  emit '```'
}

check_file() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    ok "$label: $(relative_home "$path")"
  else
    warn "$label ausente: $(relative_home "$path")"
  fi
}

check_history_repo() {
  if [[ ! -d "$HISTORY_ROOT/.git" ]]; then
    warn "historial ThinkPad no inicializado: $(relative_home "$HISTORY_ROOT")"
    return 0
  fi
  if ! git -C "$HISTORY_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    warn "historial ThinkPad sin commits: $(relative_home "$HISTORY_ROOT")"
    return 0
  fi
  if [[ -z "$(git -C "$HISTORY_ROOT" status --porcelain --untracked-files=all)" ]]; then
    ok "historial ThinkPad limpio: $(relative_home "$HISTORY_ROOT")"
  else
    warn "historial ThinkPad tiene cambios sin registrar: $(relative_home "$HISTORY_ROOT")"
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

semantic_i3_check() {
  local config="$CONFIG_HOME/i3/config" result
  [[ -f "$config" ]] || return 0

  result="$(awk '
    BEGIN { split("mod term launcher laptop_menu browser_search refresh_i3status ws1 ws2 ws3 ws4 ws5 ws6 ws7 ws8 ws9 ws10", required) }
    function fail(message) { print message; bad=1 }
    /^# (BEGIN |>>> )/ { if (marker_depth) fail("bloques administrados anidados"); marker_depth++; next }
    /^# (END |<<< )/ { if (!marker_depth) fail("bloque END sin BEGIN"); marker_depth--; next }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^set[[:space:]]+\$[A-Za-z_]/ {
      variable=$2; sub(/^\$/, "", variable); defined[variable]=NR
    }
    {
      for (index_name in required) {
        variable=required[index_name]
        if (index($0, "$" variable) && !(variable in defined) && $1 != "set") fail("variable usada antes de definir: $" variable)
      }
    }
    /^mode[[:space:]]+"[^"]+"[[:space:]]*\{/ {
      mode=$0; sub(/^.*mode[[:space:]]+"/, "", mode); sub(/".*$/, "", mode); depth++
      if (mode == "resize") section_modes=NR
      next
    }
    /^[[:space:]]*\}/ { if (depth > 0) { depth--; mode="default" }; next }
    /^[[:space:]]*bindsym[[:space:]]/ {
      key=$2; bucket=mode SUBSEP key; binds[bucket]++
      if (binds[bucket] > 1 && key != "$mod+r") fail("keybinding duplicado: " mode ":" key)
    }
    /^[[:space:]]*include[[:space:]]+.*rafex-bar-active\.conf/ { bars++; bar_line=NR }
    /^[[:space:]]*include[[:space:]]+/ { includes++ }
    /^[[:space:]]*exec(_always)?[[:space:]]/ {
      line=$0; sub(/^[[:space:]]*exec(_always)?[[:space:]]+/, "", line)
      sub(/^--no-startup-id[[:space:]]+/, "", line)
      if (line ~ /lxpolkit/) lifecycle["lxpolkit"]++
      if (line ~ /eww([^[:alnum:]]|$).*daemon/) lifecycle["eww-daemon"]++
      if (line ~ /(^|[[:space:]])(picom|polybar|tint2)([[:space:]]|$)/) lifecycle["visual"]++
    }
    /^[[:space:]]*assign[[:space:]]+\[/ {
      line=$0; sub(/^.*class="/, "", line); sub(/".*$/, "", line); klass=line
      line=$0; sub(/^.*workspace number[[:space:]]+/, "", line); sub(/[[:space:]].*$/, "", line); workspace=line
      if (klass != $0 && workspace != $0) {
        if (assign[klass] != "" && assign[klass] != workspace) fail("assign contradictorio: " klass)
        assign[klass]=workspace
      }
    }
    /^set[[:space:]]+\$theme_bar_bg/ { section_theme=NR }
    /^gaps[[:space:]]+inner/ { section_gaps=NR }
    /^[[:space:]]*exec(_always)?[[:space:]]/ && !section_exec { section_exec=NR }
    /^[[:space:]]*bindsym[[:space:]]/ && !section_bind { section_bind=NR }
    /^[[:space:]]*for_window[[:space:]]/ && !section_rules { section_rules=NR }
    /^set[[:space:]]+\$ws1/ { section_workspaces=NR }
    END {
      if (depth != 0) fail("mode sin cierre")
      if (marker_depth != 0) fail("bloque BEGIN sin END")
      if (bars != 1) fail("inclusiones de barra Rafex: " bars)
      if (lifecycle["lxpolkit"] > 1) fail("autostart duplicado: lxpolkit")
      if (lifecycle["eww-daemon"] > 1) fail("autostart duplicado: eww daemon")
      if (lifecycle["visual"] > 1) fail("autostart visual duplicado: picom/polybar/tint2")
      if (!section_theme || !section_gaps || !section_exec || !section_bind || !section_rules || !section_workspaces || !section_modes || !bar_line) fail("secciones canónicas incompletas")
      if (!(section_theme < section_gaps && section_gaps < section_exec && section_exec < section_bind && section_bind < section_rules && section_rules < section_workspaces && section_workspaces < section_modes && section_modes < bar_line)) fail("orden de secciones no canónico")
      if (bad) exit 1
    }
  ' "$config" 2>&1)" || {
    while IFS= read -r result; do [[ -n "$result" ]] && warn "i3 semántico: $result"; done <<< "$result"
    return 1
  }
  ok 'i3 semántico: bloques, atajos, autostarts, asignaciones y barra coherentes'
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
  if awk -F'|' '!/^#/ && NF >= 7 { target=$3; sub(/#.*/, "", target); count[target]++ } END { for (target in count) if (count[target] > 1) found=1; exit(found ? 0 : 1) }' "$REGISTRY"; then
    info 'registro: existen destinos físicos compartidos; deben publicarse por fragmentos, no por reemplazo completo'
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
  check_history_repo
  # Las acciones pueden estar referenciadas mediante las variables canónicas
  # de i3; auditar la expansión declarada evita exigir comandos duplicados.
  # shellcheck disable=SC2016 # el patrón necesita los símbolos $ literales de i3.
  check_i3_binding 'XF86Tools usa ratmenu' 'bindsym[[:space:]]+XF86Tools.*(\$laptop_menu|rafex-ratmenu\.sh)'
  # shellcheck disable=SC2016 # el patrón necesita los símbolos $ literales de i3.
  check_i3_binding 'XF86Search abre DuckDuckGo' 'bindsym[[:space:]]+XF86Search.*(\$browser_search|duckduckgo\.com)'
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
    semantic_i3_check || true
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
  emit '## Colisiones por destino físico'
  emit
  list_physical_collisions
  emit
  emit '## Grafo'
  list_graph
  emit
  emit '## Scripts detectados'
  list_scripts
  emit
  emit '## Candidatos que escriben superficies administradas'
  list_target_writer_candidates
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
