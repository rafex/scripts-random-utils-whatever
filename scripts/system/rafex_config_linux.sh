#!/usr/bin/env bash
# rafex_config_linux.sh v1.0.0
# Publica de forma híbrida la configuración ThinkPad desde un checkout local.
set -Eeuo pipefail
umask 077
export LC_ALL=C

ACTION=status
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CHECKOUT="$DATA_HOME/rafex/thinkpad-config-repo"
GENERATED_ROOT="$STATE_HOME/rafex/config-generated/thinkpad"
PUBLISH_STATE_DIR="$STATE_HOME/rafex/config-publisher"
PUBLISH_LOG="$PUBLISH_STATE_DIR/publish.jsonl"
LOCK_FILE="$PUBLISH_STATE_DIR/deploy.lock"
BACKUP_ROOT=""
ALLOW_ADOPT=0

export RAFEX_PUBLISH_CHECKOUT="$CHECKOUT"
export RAFEX_PUBLISH_GENERATED_ROOT="$GENERATED_ROOT"
export RAFEX_PUBLISH_STATE_DIR="$PUBLISH_STATE_DIR"
export RAFEX_PUBLISH_LOG="$PUBLISH_LOG"
export RAFEX_PUBLISH_LOCK_FILE="$LOCK_FILE"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/rafex_config_publish_linux.sh"

PROFILE='dotfiles/profiles/thinkpad-x1-yoga-1st'
MANIFEST_REL="$PROFILE/rafex-config-manifest.tsv"
TARGET_I3="$CONFIG_HOME/i3/config"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  rafex_config_linux.sh --check
  rafex_config_linux.sh --status
  rafex_config_linux.sh --sync
  rafex_config_linux.sh --plan
  rafex_config_linux.sh --adopt
  rafex_config_linux.sh --deploy
  rafex_config_linux.sh --rollback
  rafex_config_linux.sh --doctor

`--adopt` hace la migración inicial con respaldos. `--deploy` solo publica
destinos ya administrados o ausentes; nunca reemplaza archivos manuales.
EOF
}

parse_args() {
  local chosen=0
  while (($#)); do
    case "$1" in
      --check|--status|--sync|--plan|--adopt|--deploy|--rollback|--doctor)
        (( chosen == 0 )) || die 'selecciona una sola acción'
        ACTION="${1#--}"; chosen=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este publicador requiere Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
  for command_name in awk cmp cp date git install ln mktemp mv realpath sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

require_lock_tool() {
  command -v flock >/dev/null 2>&1 || die 'falta flock de util-linux para una operación de escritura'
}

repo_root() {
  if [[ -d "$CHECKOUT/.git" ]]; then
    printf '%s\n' "$CHECKOUT"
  else
    printf '%s\n' "$REPO_ROOT"
  fi
}

validate_repo() {
  local root
  root="$(repo_root)"
  [[ -f "$root/$MANIFEST_REL" ]] || die "falta manifiesto: $root/$MANIFEST_REL"
  [[ -d "$root/$PROFILE/config" ]] || die "falta perfil ThinkPad: $root/$PROFILE/config"
}

checkout_clean() {
  if ! git -C "$CHECKOUT" diff --quiet || ! git -C "$CHECKOUT" diff --cached --quiet; then
    warn "checkout sucio; separa o guarda los cambios: $CHECKOUT"
    return 1
  fi
}

sync_checkout() {
  if [[ -d "$CHECKOUT/.git" ]]; then
    checkout_clean || die 'no se puede sincronizar un checkout sucio'
    git -C "$CHECKOUT" pull --ff-only
  else
    [[ -d "$REPO_ROOT/.git" ]] || die 'no existe un checkout Git local para inicializar el repositorio ThinkPad'
    git -C "$REPO_ROOT" diff --quiet || die 'el checkout fuente tiene cambios sin commit; no se clonará una fuente incompleta'
    git -C "$REPO_ROOT" diff --cached --quiet || die 'el checkout fuente tiene cambios staged; no se clonará una fuente incompleta'
    mkdir -p -- "$(dirname -- "$CHECKOUT")"
    git clone --local --no-hardlinks "$REPO_ROOT" "$CHECKOUT"
  fi
  validate_repo
  ok "checkout listo: $CHECKOUT"
}

create_backup_root() {
  BACKUP_ROOT="$PUBLISH_STATE_DIR/backups/$STAMP"
  mkdir -p -- "$BACKUP_ROOT"
  chmod 700 -- "$PUBLISH_STATE_DIR" "$PUBLISH_STATE_DIR/backups" "$BACKUP_ROOT"
  printf '%s\n' "$BACKUP_ROOT" > "$PUBLISH_STATE_DIR/last-backup"
  chmod 600 -- "$PUBLISH_STATE_DIR/last-backup"
}

source_path() { printf '%s/%s\n' "$(repo_root)" "$1"; }
target_path() {
  case "$1" in
    .config/*) printf '%s/%s\n' "$CONFIG_HOME" "${1#.config/}" ;;
    .local/bin/*) printf '%s/%s\n' "$HOME/.local/bin" "${1#.local/bin/}" ;;
    *) die "destino no permitido en manifiesto: $1" ;;
  esac
}

validate_manifest() {
  local kind resource source target mode source_file target_file
  awk -F'|' '
    /^#/ || NF == 0 {next}
    {resources[$2]++; targets[$4]++}
    END {
      for (key in resources) if (resources[key] > 1) {print "recurso duplicado: " key; bad=1}
      for (key in targets) if (targets[key] > 1) {print "destino duplicado: " key; bad=1}
      exit bad
    }
  ' "$(source_path "$MANIFEST_REL")" || die 'manifiesto con propietarios o destinos duplicados'
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ "$kind" == static || "$kind" == generated ]] || die "estrategia inválida en manifiesto: $kind"
    [[ "$resource" =~ ^[a-z0-9._-]+$ ]] || die "recurso inválido en manifiesto: $resource"
    [[ "$source" != /* && "$source" != *..* ]] || die "fuente insegura en manifiesto: $source"
    [[ "$target" != /* && "$target" != *..* ]] || die "destino inseguro en manifiesto: $target"
    [[ "$mode" =~ ^0[0-7]{3}$ ]] || die "modo inválido en manifiesto: $mode"
    source_file="$(source_path "$source")"
    target_file="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      [[ -f "$source_file" ]] || die "fuente del manifiesto ausente: $source_file"
    else
      [[ "$source" == @generated/* ]] || die "los generados deben usar @generated/: $source"
    fi
    printf '%s|%s|%s|%s|%s\n' "$kind" "$resource" "$source_file" "$target_file" "$mode"
  done < "$(source_path "$MANIFEST_REL")"
}

extract_block() {
  local source="$1" begin="$2" end="$3"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin {inside=1; print; next}
    inside {print}
    inside && $0 == end {exit}
  ' "$source"
}

strip_managed_blocks() {
  local source="$1"
  awk '
    /^include ~\/\.config\/i3\/rafex-bar-active\.conf[[:space:]]*$/ {next}
    /^# BEGIN rafex (theme|i3-gaps|ulauncher default|conky|eww|feh wallpaper|i3lock-color|clipboard|screenshots)$/ {skip=1; next}
    skip && /^# END rafex (theme|i3-gaps|ulauncher default|conky|eww|feh wallpaper|i3lock-color|clipboard|screenshots)$/ {skip=0; next}
    skip && /^# <<< rafex-picom-service managed <<</ {skip=0; next}
    /^# >>> rafex-picom-service managed >>>$/ {skip=1; next}
    !skip {print}
  ' "$source"
}

generate_i3_tree() {
  local root="$1" i3_source i3_dir staging temporary file
  i3_source="$root/$PROFILE/config/i3/config"
  i3_dir="$GENERATED_ROOT/i3"
  mkdir -p -- "$i3_dir"
  staging="$(mktemp -d "$GENERATED_ROOT/.i3-staging.XXXXXX")"
  strip_managed_blocks "$i3_source" > "$staging/base.conf"
  extract_block "$i3_source" '# BEGIN rafex theme' '# END rafex theme' > "$staging/theme.conf"
  extract_block "$i3_source" '# BEGIN rafex i3-gaps' '# END rafex i3-gaps' > "$staging/gaps.conf"
  extract_block "$i3_source" '# BEGIN rafex ulauncher default' '# END rafex ulauncher default' > "$staging/launcher.conf"
  extract_block "$i3_source" '# BEGIN rafex conky' '# END rafex conky' > "$staging/conky.conf"
  extract_block "$i3_source" '# BEGIN rafex eww' '# END rafex eww' > "$staging/eww.conf"
  extract_block "$i3_source" '# BEGIN rafex feh wallpaper' '# END rafex feh wallpaper' > "$staging/wallpaper.conf"
  extract_block "$i3_source" '# BEGIN rafex i3lock-color' '# END rafex i3lock-color' > "$staging/lock.conf"
  extract_block "$i3_source" '# BEGIN rafex clipboard' '# END rafex clipboard' > "$staging/clipboard.conf"
  extract_block "$i3_source" '# BEGIN rafex screenshots' '# END rafex screenshots' > "$staging/screenshots.conf"
  extract_block "$i3_source" '# >>> rafex-picom-service managed >>>' '# <<< rafex-picom-service managed <<<' > "$staging/picom.conf"
  printf '%s\n' '# Rafex controls are installed by install-i3-laptop-controls.' > "$staging/controls.conf"
  printf '%s\n' 'include ~/.config/i3/rafex-bar-active.conf' > "$staging/bar.conf"
  temporary="$(mktemp "$staging/config.XXXXXX")"
  {
    printf '%s\n' '# Generated by rafex_config_linux.sh; edit the repository, not this file.'
    for file in base.conf controls.conf gaps.conf launcher.conf theme.conf conky.conf eww.conf wallpaper.conf lock.conf clipboard.conf screenshots.conf picom.conf bar.conf; do
      printf 'include ~/.local/state/rafex/config-generated/thinkpad/i3/%s\n' "$file"
    done
  } > "$temporary"
  mv -f -- "$temporary" "$staging/config"
  for file in base.conf controls.conf gaps.conf launcher.conf theme.conf conky.conf eww.conf wallpaper.conf lock.conf clipboard.conf screenshots.conf picom.conf bar.conf config; do
    mv -f -- "$staging/$file" "$i3_dir/$file"
  done
  rmdir -- "$staging"
  chmod 600 -- "$i3_dir"/*.conf
}

generate_dynamic_files() {
  local root="$1" theme='nord' theme_file bar_source
  mkdir -p -- "$GENERATED_ROOT"
  if [[ -f "$CONFIG_HOME/rafex/theme" ]]; then theme="$(head -n 1 "$CONFIG_HOME/rafex/theme")"; fi
  [[ "$theme" =~ ^(paper|nord|everforest|dracula)$ ]] || theme=nord
  theme_file="$root/$PROFILE/config/rafex/themes/$theme/eww.scss"
  [[ -f "$theme_file" ]] || theme_file="$root/$PROFILE/config/rafex/themes/nord/eww.scss"
  local temporary
  temporary="$(mktemp "$GENERATED_ROOT/.eww.scss.XXXXXX")"
  install -m 0600 -- "$theme_file" "$temporary"
  mv -f -- "$temporary" "$GENERATED_ROOT/eww.scss"
  bar_source='polybar'
  if [[ -f "$CONFIG_HOME/rafex/i3-bar-profile" ]]; then bar_source="$(head -n 1 "$CONFIG_HOME/rafex/i3-bar-profile")"; fi
  [[ "$bar_source" =~ ^(i3bar|tint2|polybar)$ ]] || bar_source=polybar
  temporary="$(mktemp "$GENERATED_ROOT/.i3-bar-profile.XXXXXX")"
  printf '%s\n' "$bar_source" > "$temporary"
  mv -f -- "$temporary" "$GENERATED_ROOT/i3-bar-profile"
  chmod 600 -- "$GENERATED_ROOT/i3-bar-profile"
  generate_i3_tree "$root"
}

show_status() {
  local root kind resource source target mode
  root="$(repo_root)"
  printf 'checkout=%s\n' "$CHECKOUT"
  printf 'source=%s\n' "$root"
  printf 'generated=%s\n' "$GENERATED_ROOT"
  if [[ -d "$CHECKOUT/.git" ]]; then
    if git -C "$CHECKOUT" diff --quiet && git -C "$CHECKOUT" diff --cached --quiet; then printf 'checkout-clean=yes\n'; else printf 'checkout-clean=no\n'; fi
    printf 'revision=%s\n' "$(git -C "$CHECKOUT" rev-parse --short HEAD 2>/dev/null || printf unknown)"
  else
    printf 'checkout-clean=not-initialized\n'
  fi
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    target="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      if rafex_publish_is_exact_symlink "$target" "$(source_path "$source")"; then printf '%s=managed-symlink\n' "$resource"; else printf '%s=unmanaged-or-missing\n' "$resource"; fi
    else
      if [[ -L "$target" || -f "$target" ]]; then printf '%s=present\n' "$resource"; else printf '%s=missing\n' "$resource"; fi
    fi
  done < "$(source_path "$MANIFEST_REL")"
  [[ -f "$PUBLISH_STATE_DIR/last-backup" ]] && printf 'last-backup=%s\n' "$(<"$PUBLISH_STATE_DIR/last-backup")" || printf 'last-backup=none\n'
}

show_plan() {
  local root
  root="$(repo_root)"
  printf '═══ Plan de publicación Rafex ThinkPad ═══\n'
  printf 'checkout: %s\n' "$CHECKOUT"
  printf 'fuente: %s\n' "$root"
  printf 'generados: %s\n' "$GENERATED_ROOT"
  printf '%s\n' '1. validar manifiesto y propietario único'
  printf '%s\n' '2. generar i3 por fragmentos y EWW/bar dinámicos en estado Rafex'
  printf '%s\n' '3. publicar archivos estáticos como symlinks administrados'
  printf '%s\n' '4. publicar destinos dinámicos atómicamente'
  printf '%s\n' '5. rechazar destinos manuales salvo --adopt explícito'
  printf '%s\n' 'No se ejecutan sudo, git commit, git push, reinicios ni cambios de hardware.'
}

publish_all() {
  local root kind resource source target mode
  root="$(repo_root)"
  validate_manifest >/dev/null
  create_backup_root
  if [[ -d "$GENERATED_ROOT" ]]; then
    while IFS= read -r -d '' source; do
      rafex_publish_backup "$source" "${source#"$HOME/"}" "$BACKUP_ROOT" >/dev/null || true
    done < <(find "$GENERATED_ROOT" \( -type f -o -type l \) -print0)
  fi
  generate_dynamic_files "$root"
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    source="$(source_path "$source")"
    target="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      rafex_publish_install_symlink "$source" "$target" "$mode" "$ALLOW_ADOPT" "${target#"$HOME/"}" "$BACKUP_ROOT"
    else
      local generated
      generated="$GENERATED_ROOT/$resource.generated"
      case "$resource" in
        i3-config) generated="$GENERATED_ROOT/i3/config" ;;
        eww-style) generated="$GENERATED_ROOT/eww.scss" ;;
        bar-state) generated="$GENERATED_ROOT/i3-bar-profile" ;;
      esac
      rafex_publish_install_generated "$generated" "$target" "$mode" "$ALLOW_ADOPT" "${target#"$HOME/"}" "$BACKUP_ROOT"
    fi
  done < "$(source_path "$MANIFEST_REL")"
  ok 'publicación completada'
}

doctor() {
  local failures=0 target source resource kind
  validate_manifest >/dev/null || failures=$((failures + 1))
  if [[ -d "$CHECKOUT/.git" ]]; then checkout_clean || failures=$((failures + 1)); fi
  while IFS='|' read -r kind resource source target _mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    target="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      source="$(source_path "$source")"
      if [[ -L "$target" ]]; then
        if [[ ! -e "$target" ]]; then
          warn "$resource: enlace roto"
          failures=$((failures + 1))
          continue
        fi
        rafex_publish_assert_inside "$(readlink -f -- "$target")" "$CHECKOUT" || failures=$((failures + 1))
        rafex_publish_is_exact_symlink "$target" "$source" || { warn "$resource: enlace apunta a otra fuente"; failures=$((failures + 1)); }
      elif [[ -e "$target" ]]; then
        warn "$resource: archivo manual en lugar de symlink"
        failures=$((failures + 1))
      fi
    else
      local generated
      case "$resource" in
        i3-config) generated="$GENERATED_ROOT/i3/config" ;;
        eww-style) generated="$GENERATED_ROOT/eww.scss" ;;
        bar-state) generated="$GENERATED_ROOT/i3-bar-profile" ;;
        *) generated='' ;;
      esac
      if [[ -n "$generated" && -L "$target" ]]; then
        if [[ ! -e "$target" ]]; then
          warn "$resource: enlace generado roto"
          failures=$((failures + 1))
          continue
        fi
        rafex_publish_assert_inside "$(readlink -f -- "$target")" "$GENERATED_ROOT" || failures=$((failures + 1))
        [[ "$(readlink -f -- "$target")" == "$(realpath -m -- "$generated")" ]] || { warn "$resource: enlace generado incorrecto"; failures=$((failures + 1)); }
      elif [[ -n "$generated" && -e "$target" ]]; then
        warn "$resource: archivo manual en lugar de symlink generado"
        failures=$((failures + 1))
      fi
    fi
  done < "$(source_path "$MANIFEST_REL")"
  if [[ -f "$TARGET_I3" ]] && [[ -L "$TARGET_I3" ]] && ! grep -Fq 'Generated by rafex_config_linux.sh' "$TARGET_I3"; then
    warn 'i3 config: el enlace no apunta al árbol generado Rafex'
    failures=$((failures + 1))
  fi
  if (( failures == 0 )); then ok 'doctor: sin conflictos detectados'; else return 1; fi
}

rollback() {
  local root relative backup target
  [[ -f "$PUBLISH_STATE_DIR/last-backup" ]] || die 'no existe un respaldo del publicador'
  root="$(<"$PUBLISH_STATE_DIR/last-backup")"
  [[ -d "$root" ]] || die "respaldo ausente: $root"
  while IFS= read -r -d '' backup; do
    relative="${backup#"$root/"}"
    target="$HOME/$relative"
    mkdir -p -- "$(dirname -- "$target")"
    rm -f -- "$target"
    cp -a -- "$backup" "$target"
    rafex_publish_log rollback "$relative" "$target" absent "$(rafex_publish_sha256 "$target")" "backup=$backup"
  done < <(find "$root" \( -type f -o -type l \) -print0)
  ok "rollback restaurado: $root"
}

main() {
  parse_args "$@"
  require_linux
  [[ -f "$REPO_ROOT/$PROFILE/rafex-config-manifest.tsv" || -f "$CHECKOUT/$MANIFEST_REL" ]] || die 'manifiesto ThinkPad ausente'
  case "$ACTION" in
    check)
      validate_repo
      validate_manifest >/dev/null
      if [[ -d "$CHECKOUT/.git" ]]; then checkout_clean || exit 1; fi
      ok 'manifiesto, fuentes, rutas y checkout válidos'
      ;;
    status) validate_repo; show_status ;;
    plan) validate_repo; show_plan ;;
    sync) require_lock_tool; rafex_publish_lock; sync_checkout ;;
    adopt) require_lock_tool; rafex_publish_lock; sync_checkout; validate_repo; ALLOW_ADOPT=1; publish_all ;;
    deploy)
      require_lock_tool
      rafex_publish_lock
      if [[ ! -d "$CHECKOUT/.git" ]]; then sync_checkout; fi
      validate_repo
      publish_all
      ;;
    rollback) require_lock_tool; rafex_publish_lock; rollback ;;
    doctor) validate_repo; doctor ;;
  esac
}

main "$@"
